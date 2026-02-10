// Phoenix LiveView initialization
// This file initializes the LiveView socket connection

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

  // Create LiveSocket
  const liveSocket = new window.LiveView.LiveSocket("/live", window.Phoenix.Socket, {
    longPollFallbackMs: 2500,
    params: {_csrf_token: csrfToken},
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

  console.log("LiveView connected!")
})
