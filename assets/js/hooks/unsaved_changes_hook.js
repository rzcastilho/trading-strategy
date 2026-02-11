/**
 * UnsavedChangesHook - Warns users before navigating away with unsaved changes.
 *
 * Implements FR-018: Unsaved changes warning when navigating away.
 *
 * This hook:
 * - Listens for browser navigation (close, refresh, back button)
 * - Shows browser's native "unsaved changes" dialog if changes exist
 * - Integrates with LiveView's socket assigns
 *
 * Usage:
 *   <div id="editor-container" phx-hook="UnsavedChangesHook" data-unsaved={@unsaved_changes}>
 *     ...
 *   </div>
 */

const UnsavedChangesHook = {
  mounted() {
    this.hasUnsavedChanges = false;
    this.beforeUnloadHandler = this.handleBeforeUnload.bind(this);

    // Read initial state from data attribute
    this.updateUnsavedState();

    // Attach beforeunload event listener
    window.addEventListener("beforeunload", this.beforeUnloadHandler);

    console.log("[UnsavedChangesHook] Mounted, tracking unsaved changes");
  },

  updated() {
    // Update unsaved state when LiveView pushes new data
    this.updateUnsavedState();
  },

  destroyed() {
    // Clean up event listener when hook is destroyed
    window.removeEventListener("beforeunload", this.beforeUnloadHandler);
    console.log("[UnsavedChangesHook] Destroyed, removed event listeners");
  },

  /**
   * Update unsaved changes state from data attribute.
   */
  updateUnsavedState() {
    const unsavedAttr = this.el.dataset.unsaved;
    const previousState = this.hasUnsavedChanges;

    // Parse data attribute (LiveView sends "true"/"false" as strings)
    this.hasUnsavedChanges = unsavedAttr === "true";

    // Log state changes for debugging
    if (previousState !== this.hasUnsavedChanges) {
      console.log(
        `[UnsavedChangesHook] Unsaved changes: ${previousState} → ${this.hasUnsavedChanges}`
      );
    }
  },

  /**
   * Handle browser beforeunload event.
   *
   * Returns a warning message if there are unsaved changes.
   * Modern browsers show a generic message, but returning any string
   * triggers the warning dialog.
   */
  handleBeforeUnload(event) {
    if (this.hasUnsavedChanges) {
      // Standard way to show warning dialog
      const message = "You have unsaved changes. Are you sure you want to leave?";
      event.preventDefault();
      event.returnValue = message; // Chrome requires returnValue to be set
      return message; // Some browsers use the return value
    }
  },

  /**
   * Public API: Check if navigation should be blocked.
   *
   * Can be called by other hooks or JavaScript code to check unsaved state.
   */
  shouldBlockNavigation() {
    return this.hasUnsavedChanges;
  },

  /**
   * Public API: Clear unsaved changes flag.
   *
   * Call this after successfully saving to remove warning.
   */
  markAsSaved() {
    this.hasUnsavedChanges = false;
    console.log("[UnsavedChangesHook] Marked as saved, navigation warning cleared");
  }
};

export default UnsavedChangesHook;
