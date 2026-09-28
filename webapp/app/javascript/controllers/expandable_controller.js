import { Controller } from "@hotwired/stimulus"

// Clamps long content, revealing a toggle only when the content actually overflows the clamp.
export default class extends Controller {
  static targets = ["content", "toggle", "label"]

  connect() {
    this.observer = new ResizeObserver(() => this.updateToggle())
    this.observer.observe(this.contentTarget)

    document.fonts?.ready.then(() => {
      if (this.element.isConnected) this.updateToggle()
    })
  }

  disconnect() {
    this.observer.disconnect()
  }

  updateToggle() {
    const expanded = this.toggleTarget.getAttribute("aria-expanded") === "true"
    this.toggleTarget.hidden = !expanded && this.contentTarget.scrollHeight <= this.contentTarget.clientHeight + 1
  }

  toggle() {
    const expanded = this.toggleTarget.getAttribute("aria-expanded") !== "true"
    this.toggleTarget.setAttribute("aria-expanded", String(expanded))
    this.labelTarget.textContent = expanded ? "Show less" : "Show more"
    this.contentTarget.classList.toggle("is-expanded", expanded)
    this.updateToggle()
  }
}
