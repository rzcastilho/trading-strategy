# Feature Specification: Fix Backtesting Issues

**Feature Branch**: `003-fix-backtesting`
**Created**: 2026-02-03
**Status**: Draft
**Input**: User description: "Test and fix any problems in backtesting feature."

## Clarifications

### Session 2026-02-03

- Q: When a backtest is interrupted by an application restart, what should happen to the partially completed work? → A: Mark as failed, save partial progress/metrics if available, allow manual resume from last checkpoint
- Q: What granularity should the equity curve data be stored at? → A: At trades plus sampled bars (e.g., every 100th bar for visualization continuity)
- Q: What unit should position age be calculated in? → A: Both available (bars and time, maximum flexibility but adds complexity)
- Q: When a backtest completes with zero trades, what should the system return? → A: Return success with flat equity curve at initial capital, metrics show 0% return, null/N/A for trade-dependent metrics (win rate, avg trade, etc.)
- Q: Should there be a limit on concurrent backtests, and if so, how should excess requests be handled? → A: Hard limit with queueing (e.g., max 5-10 concurrent, queue excess requests)

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Accurate Progress Monitoring (Priority: P1)

A trader running a backtest over a large historical dataset needs to monitor progress in real-time to estimate completion time and ensure the backtest is progressing correctly.

**Why this priority**: Progress tracking is critical for user experience. Without it, users cannot determine if a long-running backtest is frozen or working. The current placeholder returns 50% regardless of actual progress, making it impossible to estimate completion time or detect failures.

**Independent Test**: Can be fully tested by starting a backtest with 1000+ bars of data and polling the progress endpoint every 5 seconds to verify percentage increases from 0% to 100% proportionally to bars processed.

**Acceptance Scenarios**:

1. **Given** a backtest is running with 500 bars of historical data, **When** the progress endpoint is polled after 250 bars are processed, **Then** the progress should report approximately 50%
2. **Given** a backtest has completed all bars, **When** the progress endpoint is polled, **Then** the progress should report 100%
3. **Given** a backtest is just starting, **When** the progress endpoint is polled immediately, **Then** the progress should report 0% or a small percentage based on actual bars processed

---

### User Story 2 - Complete Results Visualization (Priority: P1)

A trader completes a backtest and wants to review the equity curve showing portfolio value over time, along with complete configuration details to understand exactly what parameters were tested.

**Why this priority**: Equity curves are fundamental to evaluating strategy performance. Without them, traders cannot see portfolio evolution, identify drawdown periods, or assess risk-adjusted returns visually. Missing configuration data makes results unreproducible.

**Independent Test**: Can be fully tested by running a backtest to completion and verifying the result contains a non-empty equity curve array with timestamp-value pairs and all original configuration parameters (trading pair, date range, initial capital).

**Acceptance Scenarios**:

1. **Given** a completed backtest with 100 trades, **When** retrieving the result, **Then** the equity curve should contain at least 100 data points showing portfolio value progression
2. **Given** a backtest was run on BTC/USD from 2024-01-01 to 2024-06-30, **When** retrieving the result, **Then** the configuration should show the exact trading pair and date range used
3. **Given** a backtest started with $10,000 initial capital, **When** retrieving the result, **Then** the configuration should reflect the $10,000 starting balance

---

### User Story 3 - Reliable Backtest Management (Priority: P2)

A trader wants to run multiple backtests concurrently and be confident that results are tracked reliably even if the server restarts or processes crash.

**Why this priority**: Reliability is essential for production use. Current implementation stores task references in process memory, which is lost on restart. This affects user trust and wastes computational resources when backtests must be rerun.

**Independent Test**: Can be tested by starting a backtest, storing its ID, simulating a server restart (stop/start the application), and verifying the backtest status is correctly retrieved and reflects actual state (running, completed, or failed).

**Acceptance Scenarios**:

1. **Given** a backtest is running, **When** the application restarts, **Then** the backtest should be marked as failed, partial progress and metrics should be saved if available, and users can manually resume from the last checkpoint
2. **Given** multiple backtests are running concurrently, **When** one crashes, **Then** the other backtests should continue unaffected
3. **Given** a backtest completes while the server is offline, **When** the server restarts, **Then** the result should still be retrievable from the database
4. **Given** the concurrent limit (5-10) is reached, **When** a new backtest is requested, **Then** it should be queued and automatically start when a slot becomes available

---

### User Story 4 - Accurate Trade Analytics (Priority: P2)

A trader reviews individual trade performance to understand which trades contributed most to profits and how long positions were typically held.

**Why this priority**: Trade-level analytics are essential for strategy refinement. Currently, trades are stored with PnL = 0 and no duration data, making detailed analysis impossible. Traders need this granularity to identify patterns and improve strategy rules.

**Independent Test**: Can be tested by running a backtest with at least 10 trades and verifying each trade record includes actual PnL (profit or loss), entry/exit timestamps, and calculated duration in hours or days.

**Acceptance Scenarios**:

1. **Given** a completed backtest with 20 trades, **When** retrieving trade details, **Then** each trade should show actual PnL matching the difference between exit and entry value
2. **Given** a trade was held for 48 hours, **When** reviewing trade analytics, **Then** the duration should be reported as 48 hours or 2 days
3. **Given** a winning trade with $500 profit, **When** summing all trade PnLs, **Then** the total should match the overall backtest return

---

### User Story 5 - Comprehensive Testing Coverage (Priority: P3)

Developers modifying the backtesting engine need automated unit tests to ensure changes don't break existing functionality and edge cases are handled correctly.

**Why this priority**: Automated tests prevent regressions and document expected behavior. Currently, testing relies on manual integration scripts. Comprehensive unit tests enable confident refactoring and faster iteration.

**Independent Test**: Can be tested by running the test suite (e.g., `mix test`) and verifying all backtesting modules have test coverage above 80% with edge cases explicitly tested (empty data, single trade, zero capital scenarios).

**Acceptance Scenarios**:

1. **Given** the MetricsCalculator module, **When** running unit tests, **Then** tests should cover edge cases like zero trades, all winning trades, and all losing trades
2. **Given** the Engine module, **When** running unit tests, **Then** tests should verify correct handling of insufficient historical data (warmup period)
3. **Given** the PositionManager module, **When** running unit tests, **Then** tests should cover opening multiple positions, closing with partial fills, and calculating unrealized PnL

---

### Edge Cases

- **Zero trades (no entry signals matched)**: System returns success status with flat equity curve at initial capital value, 0% total return, and null/N/A for trade-dependent metrics (win rate, average trade, profit factor)
- How does the system handle backtests with insufficient historical data for indicator warmup periods?
- What occurs if a user requests progress for a non-existent backtest ID?
- How are rounding errors managed when calculating PnL and equity values?
- What happens when market data has gaps (missing bars) during the backtest period?
- How does the system handle backtests that run out of capital mid-execution?
- What occurs when exit signals trigger but positions are already closed?
- How are concurrent modification conflicts handled when multiple backtests access the same database records?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST accurately track backtest progress as a percentage based on bars processed versus total bars
- **FR-002**: System MUST generate and persist the equity curve showing portfolio value at trade entry/exit points plus sampled intermediate bars (e.g., every 100th bar) for visualization continuity
- **FR-003**: System MUST store all backtest configuration parameters (trading pair, date range, initial capital, timeframe) in the database for reproducibility
- **FR-004**: System MUST calculate and store actual PnL for each individual trade
- **FR-005**: System MUST calculate and store trade duration from entry to exit timestamps
- **FR-006**: System MUST handle backtest state reliably across application restarts by marking interrupted backtests as failed, preserving partial progress and metrics when available, and enabling manual resume from checkpoints
- **FR-007**: System MUST calculate position age in both bars (count since entry) and time duration (hours/minutes since entry) to support flexible exit condition strategies
- **FR-008**: System MUST provide comprehensive unit test coverage for all backtesting modules
- **FR-009**: System MUST validate that sufficient historical data exists before starting a backtest
- **FR-010**: System MUST handle edge cases gracefully, including zero trades (return flat equity curve with null trade metrics), insufficient capital (halt execution with clear message), and missing data (validate before execution)
- **FR-011**: System MUST optimize bar processing to avoid O(n²) complexity with large datasets
- **FR-012**: System MUST return the equity curve in backtest results for visualization
- **FR-013**: System MUST link signals to the trades they generated for correlation analysis
- **FR-014**: System MUST handle multiple timeframes if specified in strategy configuration
- **FR-015**: System MUST provide accurate Sharpe ratio calculations appropriate for 24/7 crypto markets
- **FR-016**: System MUST enforce a concurrent backtest limit (5-10 simultaneous executions) and queue excess requests for sequential processing

### Key Entities

- **Backtest Result**: Represents a completed backtest session with metrics, trades, equity curve, and configuration
- **Trade Record**: Individual trade with entry/exit prices, timestamps, PnL, duration, and linked signal
- **Equity Curve Point**: Timestamp and portfolio value pair for visualizing performance over time
- **Progress Status**: Current state of running backtest with percentage completion and bars processed
- **Backtest Configuration**: Parameters used to run the backtest (pair, date range, capital, timeframe)

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can monitor backtest progress with accuracy within 5% of actual completion percentage
- **SC-002**: 100% of completed backtests return a non-empty equity curve with data points at each trade entry/exit plus sampled intermediate bars for continuity
- **SC-003**: Backtest results include all configuration parameters enabling exact reproduction of the test
- **SC-004**: Trade-level PnL calculations match aggregate position-level PnL within 0.01% (rounding tolerance)
- **SC-005**: Unit test coverage for backtesting modules exceeds 80% as measured by code coverage tools
- **SC-006**: Backtests processing 10,000+ bars complete without memory errors or performance degradation
- **SC-007**: System correctly handles and reports all edge cases (zero trades, insufficient data) without crashes
- **SC-008**: 95% of backtests can be resumed or their status accurately retrieved after application restart
- **SC-009**: Trade duration calculations are accurate within 1 minute for intraday strategies
- **SC-010**: Backtest execution performance improves by at least 30% after optimizing O(n²) complexity

## Assumptions

- Historical market data is available and accessible through the MarketData module
- Database schema supports storing equity curve data (may require migration)
- Existing strategy definitions follow the YAML DSL format
- Users have sufficient system resources to run backtests on large datasets
- Backtests are designed for single-asset testing (not portfolio-level multi-asset)
- Progress tracking will be based on bars processed (not time elapsed)
- Trade timestamps are stored with sufficient precision (microsecond level)
- The application uses a single-node deployment (multi-node clustering not required initially)

## Out of Scope

- Multi-asset portfolio backtesting (testing multiple trading pairs simultaneously)
- Multi-position trading (opening multiple positions on the same asset concurrently)
- Live trading integration or paper trading modes
- Advanced order types (stop-limit, trailing stops, iceberg orders)
- Real-time strategy optimization or parameter sweeping
- Distributed backtest execution across multiple nodes
- Historical data fetching or integration with data providers
- Strategy creation or modification user interfaces
- Advanced risk models (VaR, CVaR, Monte Carlo simulations)
- Commission tiers or volume-based fee structures
- Tax calculation or reporting for trades

## Dependencies

- **MarketData Module**: Must provide historical OHLCV data with timestamps
- **Strategy DSL**: YAML strategy definitions must be parsable and evaluable
- **Database**: Ecto schemas for TradingSession, PerformanceMetrics, Position, Trade, Signal
- **Signal Evaluator**: Must accept position context for exit condition evaluation
- **Task Supervision**: Application supervision tree to manage backtest worker processes

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Database schema changes required for equity curve storage | Medium - Requires migration and may affect existing data | Design backward-compatible migration; test with production data snapshots |
| Performance degradation with large datasets (>50K bars) | High - Unusable for long-term backtests | Implement optimizations early (indexed access, streaming); benchmark with realistic data |
| Task tracking across restarts is complex | Medium - May require architectural changes | Start with database-backed task registry; consider external job queue if needed |
| Floating-point rounding errors accumulate in PnL calculations | Low - Small discrepancies acceptable | Use Decimal type consistently; document rounding behavior |
| Insufficient test coverage takes significant time | Medium - Delays delivery | Prioritize critical path tests first; use property-based testing for edge cases |
| Incomplete market data causes backtest failures | Low - Users can validate data first | Enhance data quality validation endpoint; fail fast with clear error messages |
