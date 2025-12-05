# Research Findings: Trading Strategy DSL Library

**Feature**: 001-strategy-dsl-library
**Date**: 2025-12-04
**Phase**: Phase 0 - Outline & Research

This document consolidates research findings for all technical clarifications identified in the Technical Context section of plan.md. Each decision is documented with rationale, alternatives considered, and implementation guidance.

---

## 1. DSL Parser Library Selection

### Decision
**Primary**: `yaml_elixir` (v2.12+) for YAML parsing
**Secondary**: `toml` (v0.7+) for optional TOML support

### Rationale

**YAML as Primary Format:**
- Better for complex nested indicator configurations and multi-condition signal logic
- Supports anchors/aliases to reduce repetition (DRY principle for common indicator parameters)
- Industry standard for configuration in cloud-native/DevOps environments (familiar to users)
- All required indicators specified in FR-003 are well-represented in YAML structure

**yaml_elixir Library Advantages:**
- Latest version 2.12.0 (September 2024) - actively maintained
- 21.88M total downloads, used by production projects (Livebook, K8s, Vapor)
- Zero open issues, indicating excellent maintenance
- Wraps `yamerl` (mature Erlang YAML 1.2 parser with no external dependencies)
- Native Erlang implementation - no compilation issues, works across all platforms
- Provides sigil support for inline YAML (`~y` sigil)

**TOML as Optional Secondary:**
- Explicit typing prevents ambiguity (e.g., "30" vs 30 for indicator periods)
- No indentation sensitivity reduces configuration errors
- Native datetime support useful for backtest date ranges
- Simpler for flat key-value configs (risk parameters, session settings)

### Alternatives Considered

**fast_yaml** (Rejected):
- Requires native C library compilation (`libyaml` headers)
- Adds deployment complexity (system dependencies)
- Performance gains not critical for one-time DSL parsing
- Only 52 stars, smaller community

**Direct yamerl usage** (Rejected):
- `yaml_elixir` provides superior Elixir-native API
- Handles atom conversion safety (critical security concern)
- No advantage over the wrapper

**tomlex/toml_elixir alternatives** (Rejected):
- Less community adoption than `toml` by bitwalker
- `toml` is the de facto standard in Elixir ecosystem

### Implementation Guidance

```elixir
# mix.exs
defp deps do
  [
    {:yaml_elixir, "~> 2.12"},
    {:toml, "~> 0.7"},  # Optional
  ]
end

# Usage pattern
case YamlElixir.read_from_file("strategies/momentum_strategy.yaml") do
  {:ok, strategy_config} ->
    Strategy.new(strategy_config)
  {:error, reason} ->
    Logger.error("Failed to parse strategy: #{inspect(reason)}")
end
```

**Security Note**: Never use `atoms: true` option with user-supplied YAML files - atoms are not garbage collected in BEAM. Always validate parsed data structure before execution.

---

## 2. Technical Indicators Library

### Decision
**Use trading-indicators library (v0.1.0+)** from github.com/rzcastilho/trading-indicators

### Rationale

**Why trading-indicators:**
- **Project requirement**: Explicitly specified in feature specification (spec.md:L6)
- **Production-ready**: 777 comprehensive tests with 100% pass rate
- **Comprehensive coverage**: 22 indicators across 4 categories (Trend, Momentum, Volatility, Volume)
- **All FR-003 requirements met**: RSI, MACD, Bollinger Bands, SMA, EMA, volume indicators
- **Financial precision**: Uses Decimal library to eliminate floating-point errors (critical for trading)
- **Real-time streaming support**: `init_stream/update_stream` API for incremental calculations
- **Batch processing**: Supports >1000 updates/second for historical backtests
- **Data quality tools**: Gap filling, outlier detection, time-series validation
- **Parameter introspection**: Dynamic validation via `parameter_metadata/0`

**Performance Expectations:**
- Backtest 2 years daily data (730 bars × 5 indicators): ~50-200ms with native Elixir
- Well within SC-002 requirement (< 30 seconds)
- Decimal precision prevents accumulation errors in multi-year backtests
- Streaming API ideal for real-time paper/live trading (SC-003: <5s signal detection)

### Alternatives Considered

**Indicado** (Rejected):
- Not the project-specified library
- Unknown test coverage and production readiness
- No documented Decimal precision support
- Missing streaming API for real-time use cases

**Python TA-Lib wrapper via Ports** (Rejected):
- External process complexity (Erlang ports)
- Python runtime dependency
- Difficult deployment (requires TA-Lib C library + Python)
- Serialization overhead

**Rust NIFs** (Rejected for MVP):
- Premature optimization (backtest performance likely I/O bound, not CPU bound)
- Compilation complexity (requires Rust toolchain)
- Harder debugging during MVP phase
- Native Elixir performance sufficient for requirements

### API Contract

```elixir
# Module organization by category
TradingIndicators.Trend      # SMA, EMA, WMA, HMA, KAMA, MACD
TradingIndicators.Momentum   # RSI, Stochastic, Williams %R, CCI, ROC, Momentum
TradingIndicators.Volatility # Bollinger Bands, ATR, Standard Deviation, Volatility Index
TradingIndicators.Volume     # OBV, VWAP, A/D Line, CMF

# Dynamic indicator discovery
TradingIndicators.categories()
# => [:Trend, :Momentum, :Volatility, :Volume]

TradingIndicators.Trend.available_indicators()
# => [TradingIndicators.Trend.SMA, TradingIndicators.Trend.EMA, ...]

# Batch calculation (for backtesting)
{:ok, results} = TradingIndicators.Trend.sma(ohlcv_data, period: 20)
{:ok, results} = TradingIndicators.Momentum.rsi(ohlcv_data, period: 14)

# Streaming calculation (for real-time trading)
state = TradingIndicators.Trend.init_stream(TradingIndicators.Trend.SMA, period: 20)
{:ok, new_state, result} = TradingIndicators.Trend.update_stream(state, new_bar)

# Complex indicators with multiple outputs
{:ok, macd_result} = TradingIndicators.Trend.macd(data, short: 12, long: 26, signal: 9)
# => %{macd: [...], signal: [...], histogram: [...]}

{:ok, bb_result} = TradingIndicators.Volatility.bollinger_bands(data, period: 20, std_dev: 2.0)
# => %{upper: [...], middle: [...], lower: [...]}

# TradingIndicators.Behaviour - metadata inspection
TradingIndicators.Momentum.RSI.parameter_metadata()
# => %{
#   period: %{
#     type: :integer,
#     default: 14,
#     min: 2,
#     max: 100,
#     description: "Number of periods for RSI calculation"
#   }
# }

# Use behaviour for dynamic validation
defmodule IndicatorValidator do
  def validate(indicator_module, params) do
    metadata = indicator_module.parameter_metadata()

    Enum.reduce_while(params, :ok, fn {param_name, value}, _acc ->
      case Map.get(metadata, param_name) do
        nil -> {:halt, {:error, "Unknown parameter: #{param_name}"}}
        schema -> validate_param(value, schema)
      end
    end)
  end

  defp validate_param(value, %{type: :integer, min: min, max: max}) do
    cond do
      not is_integer(value) -> {:halt, {:error, "Expected integer"}}
      value < min -> {:halt, {:error, "Value below minimum #{min}"}}
      value > max -> {:halt, {:error, "Value above maximum #{max}"}}
      true -> {:cont, :ok}
    end
  end
end
```

### Data Format

**Input**: OHLCV maps with Decimal values (financial precision)
```elixir
%{
  timestamp: ~U[2024-01-01 00:00:00Z],
  open: Decimal.new("42150.00"),
  high: Decimal.new("42350.00"),
  low: Decimal.new("42050.00"),
  close: Decimal.new("42280.00"),
  volume: Decimal.new("125.45")
}
```

**Output**: All indicator values returned as lists or maps with float values

### Coverage Verification

| Indicator Category | trading-indicators Support | FR-003 Requirement |
|-------------------|---------------------------|-------------------|
| Moving Averages (SMA/EMA/WMA/HMA/KAMA) | ✅ (6 indicators) | ✅ |
| RSI | ✅ TradingIndicators.Momentum.rsi | ✅ |
| MACD | ✅ TradingIndicators.Trend.macd | ✅ |
| Bollinger Bands | ✅ TradingIndicators.Volatility.bollinger_bands | ✅ |
| Volume Indicators | ✅ (OBV, VWAP, A/D, CMF) | ✅ |
| Stochastic | ✅ TradingIndicators.Momentum.stochastic | ✅ |
| Williams %R, CCI, ATR | ✅ (additional indicators) | ✅ (exceeds requirements) |

**Total**: 22 indicators across 4 categories (exceeds FR-003 minimum requirements)

---

## 3. Cryptocurrency Exchange Integration

### Decision
**Use crypto-exchange library (v0.1.0+)** from github.com/rzcastilho/crypto-exchange

### Rationale

**Why crypto-exchange:**
- **Project requirement**: Explicitly specified in feature specification (spec.md:L6)
- **Production-ready**: 373+ comprehensive tests with full coverage
- **Binance support included**: Complete implementation for largest exchange by volume
- **All FR-017 through FR-027 requirements met**: Real-time data, historical data, order placement
- **Built-in resilience**: Circuit breaker protection, automatic reconnection with exponential backoff
- **WebSocket streaming**: Real-time ticker, order book depth, trade streams via Phoenix.PubSub
- **Historical data retrieval**: `get_historical_klines` and `get_historical_klines_bulk` with pagination
- **Trading operations**: Place orders (LIMIT, MARKET, STOP_LOSS), cancel orders, check balances, track status
- **Health monitoring**: Built-in system for connectivity status
- **Supervision tree**: Registry, Phoenix.PubSub, WebSocket connections, dynamic user management
- **Rate limiting**: Built-in protection with message buffering during outages
- **Structured logging**: Performance tracking and error classification

**Why NOT Build Custom:**
- Violates Constitution Principle VII (Simplicity & Transparency) - reinventing existing wheel
- crypto-exchange already provides all required functionality
- 373+ tests provide proven reliability
- Immediate availability accelerates delivery
- Reduces maintenance burden
- Focus implementation effort on trading strategy logic, not exchange integration

### API Contract

The crypto-exchange library provides the `CryptoExchange.API` module with the following interface:

```elixir
# User connection and authentication (FR-018)
CryptoExchange.API.connect_user(user_id, api_key, secret_key)
# => {:ok, user_pid} | {:error, reason}

# Real-time WebSocket subscriptions (FR-012, FR-025)
CryptoExchange.API.subscribe_to_ticker(symbol)
# => {:ok, subscription_id} | {:error, reason}
# Updates delivered via Phoenix.PubSub: {:ticker_update, data}

CryptoExchange.API.subscribe_to_trades(symbol)
# => {:ok, subscription_id} | {:error, reason}
# Updates delivered via Phoenix.PubSub: {:trade_update, data}

CryptoExchange.API.subscribe_to_depth(symbol, levels \\ 20)
# => {:ok, subscription_id} | {:error, reason}
# Updates delivered via Phoenix.PubSub: {:depth_update, data}

# Historical data retrieval (FR-024)
CryptoExchange.API.get_historical_klines(symbol, interval, start_time, end_time, limit \\ 1000)
# => {:ok, [kline_data, ...]} | {:error, reason}

CryptoExchange.API.get_historical_klines_bulk(symbol, interval, start_time, end_time)
# => {:ok, [kline_data, ...]} | {:error, reason}
# Automatic pagination for large datasets

# Trading operations (FR-017, FR-019)
CryptoExchange.API.place_order(user_id, order_params)
# order_params: %{symbol, side, type (:LIMIT | :MARKET | :STOP_LOSS), quantity, price (optional)}
# => {:ok, order_response} | {:error, reason}

CryptoExchange.API.cancel_order(user_id, symbol, order_id)
# => {:ok, cancel_response} | {:error, reason}

# Account information (FR-020)
CryptoExchange.API.get_balance(user_id)
# => {:ok, balances} | {:error, reason}

CryptoExchange.API.get_open_orders(user_id, symbol \\ nil)
# => {:ok, [order, ...]} | {:error, reason}

CryptoExchange.API.get_order_status(user_id, symbol, order_id)
# => {:ok, order_status} | {:error, reason}
```

### Data Formats

**OHLCV Kline Data:**
```elixir
%{
  open_time: 1609459200000,
  open: "29000.00",
  high: "29500.00",
  low: "28800.00",
  close: "29200.00",
  volume: "1234.56",
  close_time: 1609462799999,
  quote_asset_volume: "35897520.00",
  number_of_trades: 12345,
  taker_buy_base_asset_volume: "617.28",
  taker_buy_quote_asset_volume: "17946876.00"
}
```

**Ticker Update:**
```elixir
%{
  symbol: "BTCUSDT",
  price_change: "100.00",
  price_change_percent: "0.34",
  last_price: "29300.00",
  volume: "12345.67",
  # ... 20+ additional fields
}
```

### Exchanges Supported

**Phase 1 (MVP) - Included:**
1. **Binance** (Complete implementation)
   - REST API + WebSocket streaming
   - Spot trading (LIMIT, MARKET, STOP_LOSS orders)
   - Real-time klines, ticker, depth, trades
   - Historical data with bulk retrieval
   - Built-in rate limiting and circuit breaker

**Phase 2 - Extensible Architecture:**
2. **Coinbase Pro/Advanced Trade** - Add adapter using same CryptoExchange.API interface
3. **Kraken** - Add adapter following library's extensible pattern

### Built-In Resilience Features

**Rate Limiting (FR-023):**
- Automatic request throttling per exchange limits
- Message buffering during rate limit windows
- Priority not exposed in current API (future enhancement if needed)

**Connectivity Handling (FR-022):**
- Circuit breaker protection for API failures
- Automatic reconnection with exponential backoff
- Health monitoring system
- WebSocket ping/pong handling

**Error Handling:**
- Comprehensive error classification
- Supervision tree with :one_for_one restart strategy
- Dynamic user connection management
- Let it crash philosophy with supervisor recovery

### Integration Pattern

**For Backtesting (FR-024):**
```elixir
# Retrieve 2 years of daily data
{:ok, klines} = CryptoExchange.API.get_historical_klines_bulk(
  "BTCUSDT",
  "1d",
  ~U[2022-01-01 00:00:00Z],
  ~U[2024-01-01 00:00:00Z]
)

# Convert to internal OHLCV format for indicators
market_data = Enum.map(klines, &convert_kline_to_ohlcv/1)
```

**For Paper Trading (FR-012, FR-013, FR-025):**
```elixir
# Subscribe to real-time ticker updates
{:ok, _sub_id} = CryptoExchange.API.subscribe_to_ticker("BTCUSDT")

# Handle updates via Phoenix.PubSub
def handle_info({:ticker_update, ticker_data}, state) do
  # Evaluate strategy signals with latest price
  # Log simulated trades (no real orders)
end
```

**For Live Trading (FR-017, FR-019):**
```elixir
# Connect user with API credentials
{:ok, user_pid} = CryptoExchange.API.connect_user(
  "user_123",
  api_key,
  secret_key
)

# Place real order when signal detected
{:ok, order} = CryptoExchange.API.place_order("user_123", %{
  symbol: "BTCUSDT",
  side: "BUY",
  type: :MARKET,
  quantity: 0.001
})
```

### Testing Support

The library includes comprehensive test coverage. For our integration:
- Use Binance testnet credentials for integration tests
- Mock CryptoExchange.API module for unit tests
- Library's 373+ tests ensure reliability of exchange interactions

---

## 4. Session Persistence Pattern

### Decision
**Hybrid Approach: GenServer State + PostgreSQL Snapshots**

### Rationale

**Why Hybrid:**
1. **Performance Requirements Met**: Constitution Principle VI mandates <50ms p95 strategy decision latency. Pure database queries violate this; hybrid provides <10ms reads from GenServer state.
2. **Auditability Compliance**: Constitution Principle IV requires structured logging. PostgreSQL provides ACID guarantees and queryable audit trails.
3. **Multi-Strategy Support**: PostgreSQL enables cross-session portfolio-level risk queries (FR-021) that isolated ETS cannot provide.
4. **OTP Philosophy Alignment**: Database snapshots provide verified recovery points following "let it crash" philosophy.

### Implementation Pattern

**Architecture:**
- **GenServer state**: In-memory for fast position reads (<1ms, no DB hit)
- **Async DB writes**: Trade persistence doesn't block GenServer
- **Periodic snapshots**: Every 60 seconds, save full session state to database
- **Graceful shutdown**: `terminate/2` callback saves final snapshot
- **Recovery**: `init/1` loads last snapshot + replays delta trades

**Database Schema:**
```elixir
# Session snapshots (state checkpoints)
schema "paper_trading_sessions" do
  field :session_id, :binary_id, primary_key: true
  field :strategy_id, :string
  field :status, :string  # :active, :paused, :stopped
  field :capital_allocated, :decimal
  field :capital_available, :decimal
  field :cumulative_pnl, :decimal
  field :positions, :map  # JSONB for current positions
  field :snapshot_at, :utc_datetime
  timestamps()
end

# Individual trades (append-only log)
schema "paper_trades" do
  field :trade_id, :binary_id, primary_key: true
  field :session_id, :binary_id
  field :symbol, :string
  field :side, :string  # :buy, :sell
  field :quantity, :decimal
  field :price, :decimal
  field :timestamp, :utc_datetime
  field :signal_type, :string  # :entry, :exit, :stop
  field :pnl, :decimal
  timestamps()
end
```

**Supervision Tree:**
```elixir
# :transient restart strategy - restart on abnormal exit only
{DynamicSupervisor,
  name: TradingStrategy.PaperTrading.SessionSupervisor,
  strategy: :one_for_one}
```

### Alternatives Considered

**ETS + DETS** (Rejected):
- DETS is single-threaded, max ~2GB per table
- No ACID guarantees (risk of corruption on unclean shutdown)
- Cannot perform cross-session portfolio risk queries (violates FR-021)
- No audit trail (violates Constitution Principle IV)

**Pure PostgreSQL** (Rejected):
- Violates latency requirements (<50ms p95 decision latency impossible with DB round-trips)
- Synchronous queries block GenServer
- Connection pool contention at scale

**Event Sourcing with Commanded** (Rejected for MVP):
- Overengineering - adds complexity without proven need
- Violates Constitution Principle VII (Simplicity & Transparency)
- Eventual consistency conflicts with real-time trading
- Consider for future if audit requirements expand

### Performance Validation

| Approach | Latency (p95) | Durability | Auditability | Portfolio Queries |
|----------|---------------|------------|--------------|-------------------|
| **Hybrid (Chosen)** | <10ms | High | High | Yes |
| ETS + DETS | <1ms | Medium | Low | No |
| Pure PostgreSQL | 50-200ms | Highest | Highest | Yes |
| Event Sourcing | 10-50ms | Highest | Highest | Yes |

Meets SC-003: paper trading detects signals within 5 seconds (position reads <1ms, trade writes <5ms).

---

## 5. Exchange API Rate Limiting

### Decision
**Hybrid: Hammer + Custom GenServer Priority Queue**

### Rationale

**Components:**
1. **Hammer** (v7.1+) with Redis backend for distributed rate limit tracking
2. Custom **RateLimitedClient GenServer** implementing priority queue
3. **Task.Supervisor** for non-blocking async request execution
4. **Retry library** (ElixirRetry) for exponential backoff with jitter
5. **DynamicSupervisor** for managing multiple exchange clients

**Why Hammer Over ExRated:**
- ExRated only persists to ETS (unsuitable for distributed deployments)
- Hammer supports pluggable backends (ETS for single-node, Redis for distributed)
- Production-proven for multi-node deployments
- Supports multiple algorithms (token bucket, fixed window, sliding window)

**Why Custom GenServer:**
- Hammer handles rate limit tracking, but not priority queuing or backpressure
- GenServer provides:
  - Priority queue (`:critical` for stop-loss, `:normal` for standard orders)
  - Request buffering when rate limited
  - Integration point for exponential backoff retry logic
  - State management for in-flight requests

**Why Token Bucket Algorithm:**
- Allows bursts (critical for stop-loss orders)
- Smoother traffic than leaky bucket
- Maps directly to exchange rate limits ("X requests per Y seconds")

### Priority Queue Pattern

```elixir
defmodule TradingStrategy.ExchangeClient.RateLimitedClient do
  use GenServer

  defstruct [
    :exchange,
    :hammer_id,
    :rate_limit,              # {requests, milliseconds}
    :critical_queue,          # :queue.queue() for stop-loss
    :normal_queue,            # :queue.queue() for standard
    :in_flight,               # MapSet of request IDs
    :task_supervisor,
    :retry_config
  ]

  # Dequeue priority: critical first, then normal
  defp dequeue_next(state) do
    case :queue.out(state.critical_queue) do
      {{:value, request}, critical_queue} ->
        {:ok, request, %{state | critical_queue: critical_queue}}
      {:empty, _} ->
        case :queue.out(state.normal_queue) do
          {{:value, request}, normal_queue} ->
            {:ok, request, %{state | normal_queue: normal_queue}}
          {:empty, _} ->
            {:empty, state}
        end
    end
  end

  defp check_rate_limit(state) do
    {requests, milliseconds} = state.rate_limit
    Hammer.check_rate(state.hammer_id, milliseconds, requests)
  end
end
```

### Supervision Strategy

```elixir
# Supervision tree
TradingStrategy.ExchangeClient.Supervisor (one_for_one)
├── Task.Supervisor (for async HTTP requests)
├── Hammer.Backend.Redis (rate limit state storage)
└── DynamicSupervisor (one_for_one)
    ├── RateLimitedClient (Binance)
    ├── RateLimitedClient (Coinbase)
    └── RateLimitedClient (Kraken)
```

**Restart Strategy:**
- **:one_for_one** for main supervisor
- **:one_for_one** for DynamicSupervisor (isolated exchange clients)
- **:transient** for RateLimitedClient processes
- **:temporary** for Task.Supervisor tasks (handled by retry logic)

### Exponential Backoff Configuration

Per FR-023: queue requests and retry with exponential backoff (1s, 2s, 4s, 8s).

```elixir
# Using ElixirRetry library
Retry.retry with: exponential_backoff(1_000) |> randomize(0.1) |> cap(60_000) do
  case exchange_api_call() do
    {:ok, result} -> {:ok, result}
    {:error, :rate_limited} -> raise "Retriable error"
    {:error, reason} -> {:error, reason}
  end
end
```

**Jitter:** 10% randomization prevents thundering herd on retry

### Alternatives Considered

**GenStage/Broadway** (Rejected): Overkill for low-rate API clients (20-100 req/sec), designed for high-throughput pipelines

**ExRated Alone** (Rejected): No distributed support, no request queuing, no priority

**Poolboy + Manual Rate Limiting** (Rejected): Worker pools ≠ rate limiting (limits concurrent processes, not requests-per-time-window)

**Custom GenServer Only** (Rejected): Reinventing battle-tested libraries, maintenance burden

**Fuse Circuit Breaker Alone** (Rejected): Complements rate limiting but doesn't replace it

---

## 6. Data Provider Failover Mechanism

### Decision
**Multi-Layer Failover: GenStateMachine + Circuit Breakers + Aggregation Pattern**

### Rationale

**Architecture:**
1. **GenStateMachine** handles connection lifecycle (disconnected → connecting → connected → failing → failed)
2. **ExternalService circuit breakers** (wraps Erlang `fuse`) handle request-level failures
3. **:rest_for_one supervision** ensures dependent workers restart when connection restarts
4. **Aggregation pattern** enables runtime selection of active exchange based on health

**Why This Design:**
- Separation of concerns (connection lifecycle vs request failures)
- OTP fault tolerance built-in
- Automatic failover when circuit trips
- Self-healing via automatic fuse reset

### Circuit Breaker Library: ExternalService

**Configuration:**
```elixir
use ExternalService.Gateway,
  fuse_strategy: {:standard, 5, 10_000},  # 5 failures in 10s trips fuse
  fuse_refresh: 5_000,                     # Reset after 5s
  rate_limit: {5, :timer.seconds(1)}       # 5 calls/sec max

ExternalService.call(retry_opts, fuse_name, fn ->
  WebSocket.subscribe_to_market_data(exchange, symbol)
end)
```

Returns `{:error, :fuse_blown}` when circuit is open.

### Health Check Pattern: Three Layers

**1. WebSocket-Level:**
- Monitor WebSocket process with `Process.monitor/1`
- Receive `:DOWN` message when WebSocket terminates
- Trigger immediate failover

**2. Application-Level Heartbeat:**
- GenServer with `Process.send_after/3` for periodic ping/pong
- Frequency: 30-60 seconds (configurable per exchange)
- Timeout if no pong received within 5 seconds

**3. Data Flow Monitoring:**
- Track last received message timestamp
- Alert if no messages within expected interval (market-dependent)
- Proactively reconnect if data stream stalls

### Data Consistency Handling

**Normalization Requirements:**

1. **Timestamp Standardization**: Convert all to UTC microseconds
2. **Price Normalization**: Decimal.new() with exchange-specific precision
3. **Symbol Mapping**: Canonical registry (BTC/USD ↔ BTCUSDT/BTC-USD/XBT/USD)
4. **Failover Continuity**: Log discontinuity, emit failover marker event, request snapshot from secondary

**Failover Flow:**
```elixir
def handle_exchange_switch(from_exchange, to_exchange, state) do
  # Mark last sequence from primary
  last_seq = state.last_sequence_number

  # Request snapshot from secondary
  snapshot = request_snapshot(to_exchange, state.symbol)

  # Emit failover marker event
  emit_event(%{
    type: :exchange_failover,
    from: from_exchange,
    to: to_exchange,
    last_primary_seq: last_seq,
    gap_detection_required: true
  })

  %{state | active_exchange: to_exchange}
end
```

### Supervision Architecture

```
MarketDataSupervisor [:rest_for_one]
├── ExchangeRegistry (Registry)
├── PrimaryExchangeManager (GenStateMachine)
│   ├── CircuitBreaker (ExternalService/Fuse)
│   ├── WebSocketConnection (WebSockex)
│   └── HealthChecker (GenServer)
├── SecondaryExchangeManager (GenStateMachine)
│   └── [same structure]
├── FailoverCoordinator (GenServer)
└── DataNormalizer (GenServer)
```

### Alternatives Considered

**Distributed Erlang Failover** (Rejected): Overkill for single-node provider failover, network partition complexity

**Manual Failover** (Rejected): Slow response time (minutes vs milliseconds), requires 24/7 staffing

**Round-Robin Load Balancer** (Rejected): Duplicate data processing, complex deduplication, increased API costs

**Pure State Machine Without Circuit Breakers** (Rejected): Reimplements battle-tested patterns, mixing concerns

**Supervisor :one_for_all** (Rejected): Unnecessary restarts of healthy connections

---

## Implementation Roadmap

### Phase 0: Foundation (Complete)
- ✅ Research technical clarifications
- ✅ Document decisions and rationale
- ✅ Identify libraries and patterns

### Phase 1: Design & Contracts (Next)
1. Extract entities from spec → data-model.md
2. Generate API contracts from functional requirements → /contracts/
3. Create quickstart.md with getting started guide
4. Update agent context with technology stack

### Phase 2: Implementation Planning (After Phase 1)
- Generate tasks.md with dependency-ordered implementation tasks
- Convert tasks to GitHub issues (optional)

---

## References

**DSL & Parsing:**
- yaml_elixir: https://hex.pm/packages/yaml_elixir
- toml: https://hex.pm/packages/toml
- YAML vs TOML comparison: https://dev.to/leapcell/json-vs-yaml-vs-toml-vs-xml-best-data-format-in-2025-5444

**Indicators:**
- Indicado: https://github.com/thisiscetin/indicado
- ta-rs (Rust): https://github.com/greyblake/ta-rs
- rust_ti: https://crates.io/crates/rust_ti
- Rustler: https://github.com/rusterlium/rustler

**Exchange Integration:**
- ExCcxt: https://hexdocs.pm/ex_ccxt/readme.html
- binance package: https://hex.pm/packages/binance
- WebSockex: https://github.com/Azolo/websockex
- Binance WebSocket Streams: https://developers.binance.com/docs/binance-spot-api-docs/web-socket-streams
- Elixir Adapter Pattern: https://aaronrenner.io/2023/07/22/elixir-adapter-pattern.html

**Persistence:**
- GenServer state recovery: https://www.bounga.org/elixir/2020/02/29/genserver-supervision-tree-and-state-recovery-after-crash/
- ETS patterns: https://blog.jola.dev/patterns-for-managing-ets-tables
- Commanded (event sourcing): https://hexdocs.pm/commanded/aggregates.html

**Rate Limiting:**
- Hammer: https://hexdocs.pm/hammer/readme.html
- ExternalService: https://hexdocs.pm/external_service/readme.html
- Rate Limiting with GenServers: https://akoutmos.com/post/rate-limiting-with-genservers/
- ElixirRetry: https://github.com/safwank/ElixirRetry

**Failover & Circuit Breakers:**
- Fuse: https://github.com/jlouis/fuse
- GenStateMachine: https://hexdocs.pm/gen_state_machine/GenStateMachine.html
- Aggregation of Services Pattern: https://ulisses.dev/elixir/2021/03/05/aggregation-of-services-pattern.html
- OTP Supervision: https://hexdocs.pm/elixir/Supervisor.html
