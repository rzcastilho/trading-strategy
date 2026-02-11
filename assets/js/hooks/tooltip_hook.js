/**
 * TooltipHook - Accessible tooltip with keyboard navigation
 *
 * Implements WCAG 2.1 Success Criterion 1.4.13 (Content on Hover or Focus):
 * - Dismissible: Can be closed with Escape key without moving pointer
 * - Hoverable: Content remains visible when mouse moves over tooltip
 * - Persistent: Content remains until dismissed (doesn't auto-hide on blur)
 *
 * Keyboard Accessibility:
 * - Tab: Focus trigger (tooltip stays hidden)
 * - Enter/Space: Show/hide tooltip
 * - Escape: Dismiss tooltip and keep focus on trigger
 * - Click outside: Dismiss tooltip
 *
 * Mouse Interaction:
 * - Hover: Show tooltip after 300ms delay (WCAG 1.4.13)
 * - Leave: Hide tooltip
 * - Click: Toggle tooltip visibility
 */

const TooltipHook = {
  mounted() {
    // Get references to elements
    this.tooltipId = this.el.dataset.tooltipId
    this.position = this.el.dataset.tooltipPosition || 'top'
    this.trigger = this.el.querySelector(`#${this.tooltipId}-trigger`)
    this.content = this.el.querySelector(`#${this.tooltipId}-content`)
    this.isOpen = false
    this.hoverTimeout = null

    // Bind event handlers to maintain 'this' context
    this.onTriggerClick = this.onTriggerClick.bind(this)
    this.onTriggerKeydown = this.onTriggerKeydown.bind(this)
    this.onTriggerMouseEnter = this.onTriggerMouseEnter.bind(this)
    this.onTriggerMouseLeave = this.onTriggerMouseLeave.bind(this)
    this.onContentMouseEnter = this.onContentMouseEnter.bind(this)
    this.onContentMouseLeave = this.onContentMouseLeave.bind(this)
    this.onEscape = this.onEscape.bind(this)
    this.onDocumentClick = this.onDocumentClick.bind(this)

    // Register event listeners
    this.setupEventListeners()
  },

  destroyed() {
    // Cleanup event listeners to prevent memory leaks
    this.teardownEventListeners()
    this.clearHoverTimeout()
  },

  setupEventListeners() {
    // Trigger events
    this.trigger.addEventListener('click', this.onTriggerClick)
    this.trigger.addEventListener('keydown', this.onTriggerKeydown)
    this.trigger.addEventListener('mouseenter', this.onTriggerMouseEnter)
    this.trigger.addEventListener('mouseleave', this.onTriggerMouseLeave)

    // Content events (for hoverable requirement)
    this.content.addEventListener('mouseenter', this.onContentMouseEnter)
    this.content.addEventListener('mouseleave', this.onContentMouseLeave)

    // Global events
    document.addEventListener('keydown', this.onEscape)
    document.addEventListener('click', this.onDocumentClick)
  },

  teardownEventListeners() {
    this.trigger.removeEventListener('click', this.onTriggerClick)
    this.trigger.removeEventListener('keydown', this.onTriggerKeydown)
    this.trigger.removeEventListener('mouseenter', this.onTriggerMouseEnter)
    this.trigger.removeEventListener('mouseleave', this.onTriggerMouseLeave)

    this.content.removeEventListener('mouseenter', this.onContentMouseEnter)
    this.content.removeEventListener('mouseleave', this.onContentMouseLeave)

    document.removeEventListener('keydown', this.onEscape)
    document.removeEventListener('click', this.onDocumentClick)
  },

  // Event Handlers

  onTriggerClick(event) {
    event.preventDefault()
    event.stopPropagation()
    this.toggle()
  },

  onTriggerKeydown(event) {
    // Enter or Space: Toggle tooltip
    if (event.key === 'Enter' || event.key === ' ') {
      event.preventDefault()
      this.toggle()
    }
  },

  onTriggerMouseEnter() {
    // Show tooltip after 300ms delay (WCAG 1.4.13)
    this.clearHoverTimeout()
    this.hoverTimeout = setTimeout(() => {
      this.show()
    }, 300)
  },

  onTriggerMouseLeave() {
    // Clear hover timeout and hide tooltip (unless mouse is over content)
    this.clearHoverTimeout()
    // Small delay to allow mouse to move to content
    setTimeout(() => {
      if (!this.content.matches(':hover')) {
        this.hide()
      }
    }, 100)
  },

  onContentMouseEnter() {
    // Keep tooltip open when mouse is over content (hoverable requirement)
    this.clearHoverTimeout()
  },

  onContentMouseLeave() {
    // Hide tooltip when mouse leaves content
    this.hide()
  },

  onEscape(event) {
    // Dismiss tooltip on Escape key without moving focus
    if (event.key === 'Escape' && this.isOpen) {
      event.preventDefault()
      this.hide()
      this.trigger.focus()
    }
  },

  onDocumentClick(event) {
    // Close tooltip when clicking outside (dismissible requirement)
    if (this.isOpen && !this.el.contains(event.target)) {
      this.hide()
    }
  },

  // State Management

  show() {
    if (this.isOpen) return

    this.isOpen = true
    this.content.classList.remove('hidden')
    this.trigger.setAttribute('aria-expanded', 'true')

    // Position tooltip relative to trigger
    this.positionTooltip()
  },

  hide() {
    if (!this.isOpen) return

    this.isOpen = false
    this.content.classList.add('hidden')
    this.trigger.setAttribute('aria-expanded', 'false')
  },

  toggle() {
    if (this.isOpen) {
      this.hide()
    } else {
      this.show()
    }
  },

  positionTooltip() {
    // Get bounding rectangles
    const triggerRect = this.trigger.getBoundingClientRect()
    const contentRect = this.content.getBoundingClientRect()

    // Calculate position based on preference
    let top, left

    switch (this.position) {
      case 'top':
        top = -contentRect.height - 8
        left = (triggerRect.width - contentRect.width) / 2
        break

      case 'bottom':
        top = triggerRect.height + 8
        left = (triggerRect.width - contentRect.width) / 2
        break

      case 'left':
        top = (triggerRect.height - contentRect.height) / 2
        left = -contentRect.width - 8
        break

      case 'right':
        top = (triggerRect.height - contentRect.height) / 2
        left = triggerRect.width + 8
        break

      default:
        top = -contentRect.height - 8
        left = (triggerRect.width - contentRect.width) / 2
    }

    // Apply position
    this.content.style.top = `${top}px`
    this.content.style.left = `${left}px`

    // Ensure tooltip stays within viewport
    this.adjustForViewport()
  },

  adjustForViewport() {
    const contentRect = this.content.getBoundingClientRect()
    const viewportWidth = window.innerWidth
    const viewportHeight = window.innerHeight

    let adjustment = {}

    // Check if tooltip overflows viewport
    if (contentRect.right > viewportWidth) {
      adjustment.left = `${viewportWidth - contentRect.right - 16}px`
    } else if (contentRect.left < 0) {
      adjustment.left = `${-contentRect.left + 16}px`
    }

    if (contentRect.bottom > viewportHeight) {
      adjustment.top = `${viewportHeight - contentRect.bottom - 16}px`
    } else if (contentRect.top < 0) {
      adjustment.top = `${-contentRect.top + 16}px`
    }

    // Apply adjustments
    Object.assign(this.content.style, adjustment)
  },

  clearHoverTimeout() {
    if (this.hoverTimeout) {
      clearTimeout(this.hoverTimeout)
      this.hoverTimeout = null
    }
  }
}

export default TooltipHook
