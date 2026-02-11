/**
 * KeyboardShortcutsHook - Global keyboard shortcuts for strategy editor.
 *
 * Implements FR-019: Keyboard shortcuts for common actions.
 *
 * Shortcuts:
 * - Ctrl+Z / Cmd+Z: Undo last change
 * - Ctrl+Shift+Z / Cmd+Shift+Z: Redo last undone change
 * - Ctrl+S / Cmd+S: Save strategy (prevents browser default)
 *
 * Usage:
 *   <div id="editor-shortcuts" phx-hook="KeyboardShortcutsHook">
 *     ...
 *   </div>
 */

const KeyboardShortcutsHook = {
  mounted() {
    this.keydownHandler = this.handleKeydown.bind(this);
    document.addEventListener("keydown", this.keydownHandler);

    console.log("[KeyboardShortcutsHook] Mounted, keyboard shortcuts active");
    console.log("  Ctrl+Z: Undo");
    console.log("  Ctrl+Shift+Z: Redo");
    console.log("  Ctrl+S: Save");
  },

  destroyed() {
    document.removeEventListener("keydown", this.keydownHandler);
    console.log("[KeyboardShortcutsHook] Destroyed, keyboard shortcuts disabled");
  },

  /**
   * Handle global keydown events and trigger Phoenix events.
   */
  handleKeydown(event) {
    // Detect Ctrl or Cmd key (Mac)
    const isMac = navigator.platform.toUpperCase().indexOf("MAC") >= 0;
    const modifierKey = isMac ? event.metaKey : event.ctrlKey;

    if (!modifierKey) {
      return; // Not a shortcut
    }

    // Undo: Ctrl+Z / Cmd+Z (without Shift)
    if (event.key === "z" && !event.shiftKey) {
      event.preventDefault();
      this.pushEvent("undo", {});
      console.log("[KeyboardShortcutsHook] Triggered: Undo");
      return;
    }

    // Redo: Ctrl+Shift+Z / Cmd+Shift+Z
    if (event.key === "Z" && event.shiftKey) {
      event.preventDefault();
      this.pushEvent("redo", {});
      console.log("[KeyboardShortcutsHook] Triggered: Redo");
      return;
    }

    // Save: Ctrl+S / Cmd+S
    if (event.key === "s" || event.key === "S") {
      event.preventDefault();
      this.pushEvent("save_strategy", {});
      console.log("[KeyboardShortcutsHook] Triggered: Save");
      return;
    }
  },

  /**
   * Check if an element is an input/textarea to avoid conflicts.
   *
   * Returns true if keyboard shortcuts should be disabled for this element.
   */
  isInputElement(element) {
    const tagName = element.tagName.toLowerCase();
    const isContentEditable = element.isContentEditable;
    const isInput = ["input", "textarea", "select"].includes(tagName);

    return isInput || isContentEditable;
  }
};

export default KeyboardShortcutsHook;
