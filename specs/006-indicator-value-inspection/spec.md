# Feature Specification: Indicator Output Values Display

**Feature Branch**: `006-indicator-value-inspection`
**Created**: 2026-02-11
**Status**: Draft
**Input**: User description: "When I add an indicator in advanced strateegy builder, create a way to check the values available in this indicator to use in conditions? For instance, some indicators like sma have single value, but bolinger bands have 3 values that can be used."

## Clarifications

### Session 2026-02-11

- Q: How should output value information be revealed in the configured indicators list? → A: Tooltip on hover/click - Information appears in a floating tooltip when user hovers or clicks an info icon
- Q: When indicator metadata cannot be retrieved due to a system error, what should happen? → A: Show generic fallback, allow adding - Display "Output information unavailable" message but allow user to add indicator normally
- Q: What is the acceptable maximum latency for displaying indicator output information after selecting an indicator type? → A: Under 200 milliseconds
- Q: Should this feature support mobile devices, or is it desktop-only? → A: Desktop only initially - Optimize for desktop browsers; mobile support can be added in future iteration
- Q: Should this feature be accessible via keyboard navigation and screen readers? → A: Basic keyboard support - Info icons accessible via Tab key, tooltips shown/hidden with Enter/Escape, but no full screen reader optimization

## User Scenarios & Testing *(mandatory)*

### User Story 1 - View Output Values When Adding Indicator (Priority: P1)

When a user is adding an indicator to their strategy, they need to understand what output values that indicator will produce before committing to add it. This helps them make informed decisions about which indicators to use based on the values they need for their trading conditions.

**Why this priority**: This is the most critical touchpoint where users make decisions about indicator selection. Showing output information upfront prevents trial-and-error and reduces frustration.

**Independent Test**: Can be fully tested by selecting an indicator type in the "Add Indicator" form and verifying that output value information is displayed before the indicator is added. Delivers immediate value by educating users about indicator capabilities during selection.

**Acceptance Scenarios**:

1. **Given** the user has opened the "Add Indicator" form, **When** they select "Bollinger Bands" from the indicator type dropdown, **Then** they see a list of 5 output values: upper_band, middle_band, lower_band, percent_b, and bandwidth with descriptions for each
2. **Given** the user has opened the "Add Indicator" form, **When** they select "SMA" from the indicator type dropdown, **Then** they see information indicating this is a single-value indicator that can be referenced directly
3. **Given** the user selects different indicator types, **When** switching between SMA (single-value) and MACD (multi-value), **Then** the output information updates to show the correct fields for each indicator type
4. **Given** the user is viewing output values for Bollinger Bands, **When** they read the field descriptions, **Then** each field shows its unit (e.g., "price" for bands, "%" for percent_b) and a clear description of what it represents

---

### User Story 2 - View Output Values in Configured Indicators List (Priority: P2)

After adding indicators to a strategy, users need to reference back to what values each indicator provides when building conditions. The configured indicators list should display output value information so users don't need to remember or look up this information elsewhere.

**Why this priority**: This is a secondary reference point after indicators are added. While important for condition building, it's less critical than the upfront information shown during selection (P1).

**Independent Test**: Can be tested by adding one or more indicators and verifying that the configured indicators list shows output value information for each indicator. Delivers value by providing in-context reference material.

**Acceptance Scenarios**:

1. **Given** the user has added a Bollinger Bands indicator with period=20, **When** viewing the configured indicators list, **Then** they see an info icon that reveals a tooltip showing the 5 available output fields when hovered or clicked
2. **Given** the user has configured multiple indicators (e.g., SMA, RSI, MACD), **When** they need to reference output values, **Then** they can view output information for any indicator without leaving the strategy builder page
3. **Given** the user hovers over or clicks the info icon for an indicator in the configured list, **When** the tooltip is displayed, **Then** it includes example usage syntax (e.g., "bb_20.upper_band > close")

---

### User Story 3 - Contextual Help in Condition Builder (Priority: P3)

When users are creating conditions that reference indicator values, they need quick access to available values and their correct syntax. This prevents errors and speeds up condition creation.

**Why this priority**: While valuable, this can be deferred since users can reference the information from Stories 1 and 2. It's a convenience enhancement rather than a blocking requirement.

**Independent Test**: Can be tested in isolation by opening the condition builder interface and verifying that indicator value suggestions or help text appears when typing indicator references. Works independently of other stories.

**Acceptance Scenarios**:

1. **Given** the user is typing a condition that references an indicator, **When** they type "bb_20." (indicator name with dot), **Then** they see an autocomplete or suggestion list showing the 5 available fields for Bollinger Bands
2. **Given** the user has added indicators to their strategy, **When** they open the condition builder, **Then** they can access a reference panel or help overlay showing all configured indicators and their output values
3. **Given** the user attempts to reference an invalid field (e.g., "sma_20.value"), **When** the validation runs, **Then** they receive a helpful error message indicating that SMA is single-value and should be referenced as "sma_20" directly

---

### Edge Cases

- What happens when an indicator type doesn't have output metadata available? **Expected**: Display "Output information unavailable" message and allow user to proceed with adding the indicator
- How does the system handle custom or user-defined indicators that may not have standardized metadata? **Expected**: Fall back to showing parameter configuration only, with a note that output information is unavailable
- What if an indicator has conditional outputs (different fields based on configuration)? **Expected**: Show all possible output fields with notes indicating when each is available (e.g., "available when include_signal=true")
- How should very complex indicators with 10+ output fields be displayed without overwhelming the UI? **Expected**: Group related fields or use collapsible sections; show most commonly used fields by default

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST retrieve and display output value metadata for all supported indicator types when users interact with the indicator builder
- **FR-002**: System MUST clearly distinguish between single-value indicators (e.g., SMA, RSI) and multi-value indicators (e.g., Bollinger Bands, MACD) in the UI
- **FR-003**: System MUST show field names, data types/units, and descriptions for each output value of multi-value indicators
- **FR-004**: System MUST display output value information in the "Add Indicator" form before the indicator is added to the strategy
- **FR-005**: System MUST provide access to output value information for already-configured indicators in the indicators list
- **FR-006**: System MUST include example usage syntax showing how to reference indicator values in conditions (e.g., "bb_20.upper_band", "sma_20")
- **FR-007**: Users MUST be able to view output information without leaving the strategy builder interface (no external documentation required)
- **FR-008**: System MUST handle indicators with missing or incomplete metadata gracefully by displaying "Output information unavailable" message while still allowing users to add and configure the indicator normally
- **FR-009**: Output value information MUST be presented via tooltips triggered by hover or click on info icons to avoid cluttering the interface while keeping information readily accessible
- **FR-010**: System MUST keep output information synchronized with the indicator type selected or configured (updates immediately when indicator type changes)
- **FR-011**: Info icons and tooltips MUST be accessible via keyboard navigation (Tab to focus info icon, Enter to show tooltip, Escape to hide tooltip)

### Key Entities *(include if feature involves data)*

- **Indicator Output Metadata**: Describes the values an indicator produces
  - Type classification (single-value vs multi-value)
  - List of output fields for multi-value indicators
  - Field attributes: name, description, unit/data type
  - Example usage syntax

- **Output Field**: Individual value produced by a multi-value indicator
  - Field name (e.g., "upper_band", "macd", "signal")
  - Description explaining what the field represents
  - Unit or data type (e.g., "price", "%", "volume")
  - Usage syntax in conditions

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can identify available output values for any indicator without consulting external documentation (measured by task completion without help)
- **SC-002**: 90% of users successfully create conditions using multi-value indicator fields on first attempt without validation errors
- **SC-003**: Time to create a condition referencing an indicator value reduces by 40% compared to baseline (measured from opening condition builder to valid condition)
- **SC-004**: Zero user-reported incidents of confusion about how to reference indicator values in conditions within first month after release
- **SC-005**: Support requests related to "How do I use indicator X in conditions?" decrease by 70%
- **SC-006**: Users correctly distinguish between single-value and multi-value indicators in 95% of cases when building strategies
- **SC-007**: Indicator output information appears within 200 milliseconds of selecting an indicator type, ensuring perceived instant feedback

### Assumptions

- The `TradingStrategy.StrategyEditor.IndicatorMetadata` module provides accurate and complete metadata for all standard indicators
- Users understand basic indicator concepts (e.g., what SMA or Bollinger Bands measure)
- The strategy builder UI has sufficient space to display output information without major layout changes
- Indicator metadata includes field descriptions in English
- The condition builder supports dot-notation syntax for accessing multi-value indicator fields (e.g., "indicator.field")
- Users access the strategy builder primarily via desktop browsers; mobile device support is not required for initial release

### Dependencies

- Requires `TradingStrategy.StrategyEditor.IndicatorMetadata` module to be functioning correctly
- Depends on the TradingIndicators library providing `output_fields_metadata/0` for each indicator module
- May depend on existing UI components for tooltips, expandable panels, or help overlays
- Integration with the IndicatorBuilder LiveComponent (existing component)

### Out of Scope

- Modifying how indicators calculate or return values (backend logic unchanged)
- Adding new indicators or indicator types (only displaying information for existing indicators)
- Customizing indicator metadata or allowing users to edit field descriptions
- Advanced autocomplete or IDE-like features in the condition builder (beyond basic field suggestions)
- Historical or real-time preview of indicator values on charts
- Tutorials or guided workflows for learning about specific indicators
- Mobile device optimization or touch-specific interactions (desktop browsers only for initial release)
- Full WCAG 2.1 AA compliance or comprehensive screen reader optimization (basic keyboard support only)
