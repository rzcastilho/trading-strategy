/**
 * BuilderFormHook - Phoenix LiveView Hook for Advanced Strategy Builder
 *
 * Handles:
 * - 300ms debouncing for builder form changes (FR-008)
 * - Batching multiple field changes into single sync event
 * - Form state tracking
 *
 * Usage in template:
 * <div id="builder-form" phx-hook="BuilderFormHook">
 *   <!-- Builder form fields here -->
 * </div>
 */

const BuilderFormHook = {
  mounted() {
    console.log('[BuilderFormHook] Mounted');

    this.debounceTimer = null;
    this.pendingChanges = {};

    // Listen for all input changes within the builder form
    this.el.addEventListener('input', (e) => {
      this.handleInputChange(e);
    });

    // Listen for indicator add/remove actions
    this.el.addEventListener('click', (e) => {
      if (e.target.matches('[data-action="add-indicator"]')) {
        this.handleAddIndicator(e);
      } else if (e.target.matches('[data-action="remove-indicator"]')) {
        this.handleRemoveIndicator(e);
      }
    });
  },

  /**
   * Handle input field changes with debouncing
   */
  handleInputChange(event) {
    const field = event.target;
    const fieldName = field.name;
    const fieldValue = field.value;

    console.log(`[BuilderFormHook] Field changed: ${fieldName} = ${fieldValue}`);

    // Track the pending change
    this.pendingChanges[fieldName] = fieldValue;

    // Clear existing debounce timer
    clearTimeout(this.debounceTimer);

    // Set new debounce timer (300ms as per FR-008)
    this.debounceTimer = setTimeout(() => {
      this.syncToServer();
    }, 300);
  },

  /**
   * Sync accumulated changes to server
   */
  syncToServer() {
    if (Object.keys(this.pendingChanges).length === 0) {
      return;
    }

    console.log('[BuilderFormHook] Syncing to server:', this.pendingChanges);

    // Build builder_state object from form data
    const builderState = this.collectFormData();

    // Send to Phoenix LiveView
    this.pushEvent('builder_changed', {
      builder_state: builderState,
      timestamp: Date.now()
    });

    // Clear pending changes
    this.pendingChanges = {};
  },

  /**
   * Collect all form data into builder_state structure
   */
  collectFormData() {
    const formData = new FormData(this.el.querySelector('form') || this.el);
    const data = {};

    // Basic fields
    data.name = formData.get('name') || '';
    data.trading_pair = formData.get('trading_pair') || '';
    data.timeframe = formData.get('timeframe') || '';
    data.description = formData.get('description') || '';

    // Conditions
    data.entry_conditions = formData.get('entry_conditions') || '';
    data.exit_conditions = formData.get('exit_conditions') || '';
    data.stop_conditions = formData.get('stop_conditions') || '';

    // Indicators (collect all indicator field groups)
    data.indicators = this.collectIndicators();

    // Position sizing
    data.position_sizing = {
      type: formData.get('position_sizing_type') || 'percentage',
      percentage_of_capital: parseFloat(formData.get('percentage_of_capital')) || null,
      fixed_amount: parseFloat(formData.get('fixed_amount')) || null,
      _id: formData.get('position_sizing_id') || this.generateId()
    };

    // Risk parameters
    data.risk_parameters = {
      max_daily_loss: parseFloat(formData.get('max_daily_loss')) || null,
      max_drawdown: parseFloat(formData.get('max_drawdown')) || null,
      max_position_size: parseFloat(formData.get('max_position_size')) || null,
      _id: formData.get('risk_parameters_id') || this.generateId()
    };

    return data;
  },

  /**
   * Collect all indicators from the form
   */
  collectIndicators() {
    const indicators = [];
    const indicatorElements = this.el.querySelectorAll('[data-indicator-id]');

    indicatorElements.forEach((indicatorEl) => {
      const id = indicatorEl.getAttribute('data-indicator-id');
      const type = indicatorEl.querySelector('[name$="[type]"]')?.value || '';
      const name = indicatorEl.querySelector('[name$="[name]"]')?.value || '';

      // Collect parameters
      const parameters = {};
      indicatorEl.querySelectorAll('[data-parameter]').forEach((paramEl) => {
        const paramName = paramEl.getAttribute('data-parameter');
        const paramValue = paramEl.value;
        parameters[paramName] = this.parseParameterValue(paramValue);
      });

      indicators.push({
        type,
        name,
        parameters,
        _id: id
      });
    });

    return indicators;
  },

  /**
   * Parse parameter value (number vs string)
   */
  parseParameterValue(value) {
    const num = parseFloat(value);
    return isNaN(num) ? value : num;
  },

  /**
   * Handle adding a new indicator
   */
  handleAddIndicator(event) {
    event.preventDefault();
    console.log('[BuilderFormHook] Add indicator clicked');

    // Push add_indicator event to server
    this.pushEvent('add_indicator', {
      type: 'rsi', // Default type, server can override
      name: `indicator_${Date.now()}`,
      parameters: {}
    });
  },

  /**
   * Handle removing an indicator
   */
  handleRemoveIndicator(event) {
    event.preventDefault();
    const indicatorId = event.target.closest('[data-indicator-id]')?.getAttribute('data-indicator-id');

    if (indicatorId) {
      console.log('[BuilderFormHook] Remove indicator:', indicatorId);

      this.pushEvent('remove_indicator', {
        indicator_id: indicatorId
      });
    }
  },

  /**
   * Generate a unique ID for new elements
   */
  generateId() {
    return `${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
  },

  /**
   * Handle external updates from DSL editor
   * This is called when DSL changes and we need to update the builder form
   */
  updated() {
    // Check if builder_state was updated from server (DSL sync)
    const newBuilderState = this.el.getAttribute('data-builder-state');

    if (newBuilderState) {
      console.log('[BuilderFormHook] Builder state updated from DSL');
      // Update form fields to reflect DSL changes
      // This prevents sync loops by not triggering debounced events
      this.updateFormFields(JSON.parse(newBuilderState));
    }
  },

  /**
   * Update form fields without triggering sync events
   */
  updateFormFields(builderState) {
    // Temporarily disable input listener to prevent sync loop
    const inputHandler = this.handleInputChange.bind(this);
    this.el.removeEventListener('input', inputHandler);

    // Update form fields
    if (builderState.name) {
      this.setFieldValue('name', builderState.name);
    }
    if (builderState.trading_pair) {
      this.setFieldValue('trading_pair', builderState.trading_pair);
    }
    if (builderState.timeframe) {
      this.setFieldValue('timeframe', builderState.timeframe);
    }

    // Re-enable input listener after a short delay
    setTimeout(() => {
      this.el.addEventListener('input', inputHandler);
    }, 100);
  },

  /**
   * Set form field value safely
   */
  setFieldValue(name, value) {
    const field = this.el.querySelector(`[name="${name}"]`);
    if (field && field.value !== value) {
      field.value = value;
    }
  },

  destroyed() {
    console.log('[BuilderFormHook] Destroyed');
    clearTimeout(this.debounceTimer);
  }
};

export default BuilderFormHook;
