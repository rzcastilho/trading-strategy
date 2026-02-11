// Phoenix LiveView initialization with hooks support
// Feature 005: Bidirectional Strategy Editor Synchronization

// Import LiveView hooks
import BuilderFormHook from "./hooks/builder_form_hook.js"
import DSLEditorHook from "./hooks/dsl_editor_hook.js"
import UnsavedChangesHook from "./hooks/unsaved_changes_hook.js"
import KeyboardShortcutsHook from "./hooks/keyboard_shortcuts_hook.js"
import TooltipHook from "./hooks/tooltip_hook.js"

// Wait for DOM to be ready
document.addEventListener("DOMContentLoaded", function() {
  console.log("Initializing LiveView...")

  // Check if Phoenix and LiveView are loaded
  if (typeof window.Phoenix === "undefined") {
    console.error("Phoenix library not loaded!")
    return
  }

  if (typeof window.LiveView === "undefined") {
    console.error("LiveView library not loaded!")
    return
  }

  // Get CSRF token
  const csrfToken = document.querySelector("meta[name='csrf-token']")?.getAttribute("content")

  if (!csrfToken) {
    console.error("CSRF token not found!")
    return
  }

  console.log("Creating LiveSocket...")

  // Initialize hooks object for LiveView hooks
  const Hooks = {}

  // Register hooks (T019, T043, T080, T081)
  Hooks.BuilderFormHook = BuilderFormHook
  Hooks.DSLEditorHook = DSLEditorHook  // Phase 4: DSL Editor with CodeMirror 6
  Hooks.UnsavedChangesHook = UnsavedChangesHook  // Phase 7: Unsaved changes warning (FR-018)
  Hooks.KeyboardShortcutsHook = KeyboardShortcutsHook  // Phase 7: Keyboard shortcuts (FR-019)
  Hooks.TooltipHook = TooltipHook  // Feature 006: Indicator output values tooltip

  // Create LiveSocket with hooks support
  const liveSocket = new window.LiveView.LiveSocket("/live", window.Phoenix.Socket, {
    longPollFallbackMs: 2500,
    params: {_csrf_token: csrfToken},
    hooks: Hooks,
    dom: {
      onBeforeElUpdated(from, to) {
        if (from._x_dataStack) {
          window.Alpine.clone(from, to)
        }
      }
    }
  })

  // Connect to the server
  liveSocket.connect()

  // Expose for debugging
  window.liveSocket = liveSocket
  window.Hooks = Hooks

  console.log("LiveView connected!")
})
