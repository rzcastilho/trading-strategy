# API Contracts

**Feature**: 006-indicator-value-inspection
**Date**: 2026-02-11

## No API Contracts Required

This feature does **not** introduce new API endpoints or external contracts. Here's why:

### Feature Scope

This is a **UI-only enhancement** that displays existing metadata from the TradingIndicators library. No new backend APIs, HTTP endpoints, or data services are created.

### Data Sources

1. **TradingIndicators Library** (External Dependency):
   - Location: `/Users/castilho/code/github.com/rzcastilho/trading-indicators`
   - Interface: `TradingIndicators.Behaviour.output_fields_metadata/0` callback
   - Contract: Defined by external library, not by this feature
   - Stability: Stable behavior contract (all 20 indicators implement it)

2. **Internal Helper Module**:
   - Module: `TradingStrategy.StrategyEditor.IndicatorMetadata`
   - Purpose: Format metadata into tooltip content
   - Scope: Internal module (not exposed as public API)
   - Usage: Called directly from LiveView components

### Why No Contract Files?

API contracts (OpenAPI, GraphQL schemas, etc.) are typically created when:
- ✅ Exposing new HTTP/REST endpoints
- ✅ Creating new WebSocket channels
- ✅ Integrating with external services
- ✅ Defining public APIs for external consumers

This feature does **none of the above**. Instead, it:
- ❌ Uses existing Phoenix LiveView components (no new endpoints)
- ❌ Fetches metadata from in-process modules (no network calls)
- ❌ Displays information client-side (no backend changes)

### Relevant Contracts Elsewhere

If you need to understand the indicator metadata contract, refer to:

**TradingIndicators Library Documentation**:
- Behavior definition: `lib/trading_indicators/behaviour.ex`
- Type specifications: `lib/trading_indicators/types.ex`
- Example implementations: `lib/trading_indicators/trend/sma.ex`, `lib/trading_indicators/volatility/bollinger_bands.ex`

**Internal Data Model**:
- See `specs/006-indicator-value-inspection/data-model.md` for entity structures and validation rules

### Future Considerations

If this feature is later extended to include:
- REST API endpoint for fetching indicator metadata (e.g., `/api/indicators/:name/metadata`)
- WebSocket channel for real-time indicator updates
- GraphQL queries for indicator information

Then appropriate contract files (OpenAPI spec, GraphQL schema, etc.) should be added to this directory.

---

**Summary**: No API contracts are needed for this UI-only feature. Metadata comes from the TradingIndicators library (external contract) and is consumed internally by LiveView components.
