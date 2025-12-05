# Feature Specification: Trading Strategy DSL Library

**Feature Branch**: `001-strategy-dsl-library`
**Created**: 2025-12-03
**Status**: Draft
**Input**: User description: "I want to build a trading strategy library focused in backtesting, realtime testing, and realtime trading. This library will use the trading-indicators library to calculate indicators and the crypto-exchange library to get realtime, historical data, and execute trades. To define the trading strategies let's define a DSL where you configure the indicators that will be used and logic to trigger signal, the signals could be entry, exit and stop (risk management - gain or loss)."

## Clarifications

### Session 2025-12-03

- Q: What format should the DSL use for strategy definitions? → A: YAML/TOML configuration files
- Q: When entry and exit signal conditions are both true at the same time, which action should the system take? → A: Context-dependent: If in position, exit; if flat, entry. If both apply to current state, exit takes priority
- Q: When the exchange API rate limit is exceeded during live trading, how should the system respond? → A: Queue pending requests and retry with exponential backoff
- Q: How should exchange API credentials (API keys, secrets) be stored and managed? → A: User provides credentials at runtime for each session
- Q: How should the system alert traders when critical events occur (connectivity loss, risk limits exceeded, etc.)? → A: Log to console/terminal output

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Define Strategy Using DSL (Priority: P1)

A quantitative trader wants to define a new trading strategy by declaring which indicators to use and the conditions that trigger buy, sell, and stop-loss signals, without writing procedural code.

**Why this priority**: This is the core value proposition - enabling strategy definition through declarative configuration rather than imperative programming. Without this, the library has no purpose.

**Independent Test**: Can be fully tested by creating a strategy definition using the DSL syntax, validating it parses correctly, and confirming the strategy structure is correctly represented. Delivers immediate value by allowing traders to express their logic clearly.

**Acceptance Scenarios**:

1. **Given** a trader has a momentum strategy idea, **When** they write a DSL definition specifying RSI and MACD indicators with entry condition "RSI < 30 AND MACD crosses above signal", **Then** the system accepts and validates the strategy definition
2. **Given** a valid strategy DSL definition, **When** the system parses it, **Then** all indicators, entry signals, exit signals, and stop conditions are correctly identified and structured
3. **Given** an incomplete strategy definition (missing required exit signal), **When** the system validates it, **Then** clear validation errors are returned specifying what's missing

---

### User Story 2 - Backtest Strategy with Historical Data (Priority: P2)

A trader wants to validate their strategy by running it against historical market data to see how it would have performed, including metrics like win rate, total return, and maximum drawdown.

**Why this priority**: Backtesting is essential for strategy validation before risking real capital. This is the first "proof of value" step after defining a strategy.

**Independent Test**: Can be fully tested by providing a strategy definition and historical price data, executing the backtest engine, and receiving performance metrics. Delivers value by showing whether a strategy would have been profitable historically.

**Acceptance Scenarios**:

1. **Given** a validated strategy definition and 2 years of historical price data, **When** the trader runs a backtest, **Then** the system executes all trades that would have been triggered and returns performance metrics
2. **Given** a completed backtest, **When** the trader views results, **Then** they see total return, win rate, maximum drawdown, Sharpe ratio, number of trades, and average trade duration
3. **Given** historical data with data gaps or anomalies, **When** the backtest runs, **Then** the system handles missing data gracefully and logs warnings without crashing
4. **Given** a backtest in progress, **When** a trader checks status, **Then** they see progress percentage and estimated time remaining

---

### User Story 3 - Paper Trade Strategy in Real-Time (Priority: P3)

A trader wants to run their strategy in real-time market conditions using live data feeds, but without executing actual trades, to validate behavior before deploying real capital.

**Why this priority**: Paper trading bridges the gap between historical backtesting and live trading, revealing issues like latency, data feed reliability, and real-time decision making that backtests cannot simulate.

**Independent Test**: Can be fully tested by starting a paper trading session with a strategy, connecting to live market data, observing simulated trades being logged, and verifying no real orders are placed. Delivers value by proving the strategy works in live conditions.

**Acceptance Scenarios**:

1. **Given** a validated strategy definition, **When** the trader starts a paper trading session, **Then** the system connects to live market data and begins monitoring for signal conditions
2. **Given** an active paper trading session, **When** market conditions match an entry signal, **Then** the system logs a simulated trade with entry price, timestamp, and position size
3. **Given** active simulated positions, **When** exit or stop conditions are met, **Then** the system logs trade closure with exit price, profit/loss, and hold duration
4. **Given** a paper trading session running for multiple days, **When** the trader views session results, **Then** they see cumulative P&L, all simulated trades, and performance metrics

---

### User Story 4 - Execute Strategy in Live Trading (Priority: P4)

A trader wants to deploy their validated strategy to execute real trades automatically using live market data, with the system managing order placement and position tracking.

**Why this priority**: This is the ultimate goal but requires all previous capabilities (DSL, backtesting, paper trading) to be proven reliable first. Highest risk due to real capital.

**Independent Test**: Can be fully tested by starting a live trading session with real exchange credentials, minimal capital allocation, and observing actual orders placed and filled. Delivers value by automating trading execution.

**Acceptance Scenarios**:

1. **Given** a strategy validated through backtesting and paper trading, **When** the trader starts a live trading session with allocated capital, **Then** the system connects to the exchange and begins monitoring for signals
2. **Given** an active live trading session, **When** entry signal conditions are met, **Then** the system places a real market or limit order through the exchange
3. **Given** an open position, **When** stop-loss conditions are triggered, **Then** the system immediately places an exit order to limit losses
4. **Given** multiple concurrent live trading sessions, **When** portfolio risk limits are approached, **Then** the system prevents new positions that would exceed risk thresholds
5. **Given** exchange connectivity issues, **When** the connection is lost, **Then** the system pauses trading, logs the incident, and alerts the trader

---

### Edge Cases

- What happens when indicator calculation requires more historical data than available (e.g., 200-period moving average but only 100 bars exist)?
- **Conflicting signals**: When entry and exit conditions are both true simultaneously, the system prioritizes based on current position state - if holding a position, exit signal takes priority; if flat (no position), entry signal takes priority. In ambiguous cases, exit always takes priority for risk management.
- **Exchange API rate limits**: When rate limits are exceeded, the system queues pending requests and retries with exponential backoff (e.g., 1s, 2s, 4s, 8s). Critical orders (stop-loss) receive priority in the queue.
- How does the system behave when a stop-loss order cannot be filled at the specified price (slippage)?
- What happens during backtesting when a signal occurs on the last available data point?
- How does paper trading handle order fills when real market liquidity might not support the simulated position size?
- What happens when a strategy DSL contains circular dependencies between indicators?

## Requirements *(mandatory)*

### Functional Requirements

**DSL & Strategy Definition**:
- **FR-001**: System MUST allow traders to define strategies using YAML or TOML configuration files specifying indicators, entry conditions, exit conditions, and stop-loss rules
- **FR-002**: System MUST validate strategy definitions and return specific errors for missing required fields or invalid syntax
- **FR-003**: System MUST support common technical indicators including moving averages, RSI, MACD, Bollinger Bands, and volume indicators
- **FR-004**: System MUST allow combining multiple indicator conditions using logical operators (AND, OR, NOT)
- **FR-005**: System MUST support three signal types: entry (open position), exit (close position), and stop (risk management - gain or loss)
- **FR-006**: System MUST resolve conflicting signals by prioritizing exit over entry when both conditions are true, with context-awareness for current position state

**Backtesting**:
- **FR-007**: System MUST execute backtests using historical market data to simulate strategy performance
- **FR-008**: System MUST calculate and report performance metrics including total return, win rate, maximum drawdown, Sharpe ratio, number of trades, and average trade duration
- **FR-009**: System MUST handle missing or incomplete historical data without crashing, logging data quality issues
- **FR-010**: System MUST support backtesting with configurable starting capital and position sizing rules
- **FR-011**: System MUST account for realistic trading costs including commissions and slippage in backtest results

**Paper Trading**:
- **FR-012**: System MUST connect to live market data feeds to monitor real-time price movements
- **FR-013**: System MUST simulate trade execution without placing real orders when paper trading mode is active
- **FR-014**: System MUST log all simulated trades with timestamps, prices, position sizes, and P&L
- **FR-015**: System MUST track simulated portfolio state including open positions, available capital, and cumulative returns
- **FR-016**: System MUST continue paper trading sessions across system restarts by persisting session state

**Live Trading**:
- **FR-017**: System MUST connect to cryptocurrency exchanges to place real orders when live trading mode is active
- **FR-018**: System MUST authenticate with exchange APIs using credentials provided by the trader at session start time (not stored persistently)
- **FR-019**: System MUST place market or limit orders based on strategy signal type and configuration
- **FR-020**: System MUST monitor open positions and execute exit orders when stop-loss or exit signal conditions are met
- **FR-021**: System MUST enforce portfolio-level risk limits preventing positions that exceed configured thresholds
- **FR-022**: System MUST handle exchange connectivity failures by pausing trading and logging critical alerts to console/terminal output
- **FR-023**: System MUST handle exchange API rate limits by queueing requests and retrying with exponential backoff, prioritizing critical orders (stop-loss) in the queue

**Data Management**:
- **FR-024**: System MUST retrieve historical market data (OHLCV - Open, High, Low, Close, Volume) for backtesting
- **FR-025**: System MUST retrieve real-time market data for paper trading and live trading
- **FR-026**: System MUST calculate indicator values based on retrieved market data
- **FR-027**: System MUST cache calculated indicator values to avoid redundant computation

**Observability**:
- **FR-028**: System MUST log all trading decisions including signals detected, conditions evaluated, and actions taken
- **FR-029**: System MUST provide session status showing current mode (backtest/paper/live), active positions, and performance metrics
- **FR-030**: System MUST record all errors and warnings with sufficient context for debugging

### Key Entities

- **Strategy Definition**: Declarative YAML or TOML configuration file specifying indicators to calculate, conditions for entry/exit/stop signals, position sizing rules, and risk parameters. Relationships: references indicator types, consumed by all trading modes
- **Indicator**: Calculated technical analysis metric (e.g., RSI, MACD, moving average) derived from market data. Attributes include indicator type, calculation parameters (e.g., period length), and current value. Relationships: depends on market data, used in signal conditions
- **Market Data**: Time-series price and volume information (OHLCV bars) for a trading pair. Attributes include timestamp, open/high/low/close prices, volume, and data source. Relationships: consumed by indicators, drives signal evaluation
- **Signal**: Event indicating a trading action should occur (entry, exit, or stop). Attributes include signal type, timestamp, triggering conditions, and associated strategy. Relationships: produced by strategy evaluation, triggers trades
- **Trade**: Record of a position being opened or closed. Attributes include trade type (buy/sell), timestamp, price, quantity, fees, and mode (backtest/paper/live). Relationships: linked to strategy and signal, tracked in session results
- **Trading Session**: Execution context for running a strategy in one of three modes (backtest, paper, live). Attributes include mode, strategy definition, start time, allocated capital, open positions, and cumulative P&L. Relationships: contains trades, uses strategy definition
- **Position**: Open trade waiting for exit or stop conditions. Attributes include entry price, quantity, entry timestamp, unrealized P&L, and stop-loss level. Relationships: created by entry signal, closed by exit/stop signal
- **Performance Metrics**: Calculated statistics summarizing strategy results. Attributes include total return, win rate, max drawdown, Sharpe ratio, trade count, and average hold time. Relationships: computed from completed trades in a session

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Traders can define a complete strategy (indicators + entry/exit/stop signals) in under 10 minutes using the DSL
- **SC-002**: Backtests process 2 years of daily historical data in under 30 seconds
- **SC-003**: Paper trading sessions detect and log signals within 5 seconds of live market conditions being met
- **SC-004**: Live trading mode places orders on the exchange within 10 seconds of signal detection (decision latency + order placement)
- **SC-005**: 90% of traders successfully complete their first backtest without errors on the first attempt
- **SC-006**: System maintains 99.9% uptime for live trading sessions (excluding exchange outages)
- **SC-007**: Zero unintended real trades are placed during paper trading mode (100% isolation)
- **SC-008**: All trading decisions are logged with complete context, enabling full audit trail reconstruction

### Assumptions

- Traders using this library have basic understanding of technical analysis indicators
- Historical market data is available from external sources in OHLCV format
- Exchange APIs provide WebSocket or REST endpoints for real-time data and order placement
- Initial version focuses on cryptocurrency markets (extensible to other asset classes later)
- Strategies operate on single trading pairs (no portfolio optimization or multi-asset strategies initially)
- Position sizing uses percentage of capital allocation (e.g., 10% per trade) rather than complex Kelly criterion
- Backtests assume orders are filled at close price of the signal bar (no intra-bar execution modeling)
- Paper trading simulates instant fills at current market price (no order book depth simulation)
- Stop-loss orders are market orders (guaranteed execution, price slippage accepted)
- Risk limits are enforced at strategy level (no global portfolio risk manager initially)
- Exchange credentials are provided at runtime when starting sessions (not persisted) for maximum security and trader accountability
