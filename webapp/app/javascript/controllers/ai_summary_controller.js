import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["content", "status", "toggle", "retry"]
  static values = { url: String, token: String }

  connect() {
    this.observer = new ResizeObserver(() => this.updateToggle())
    this.observer.observe(this.contentTarget)
    if (this.contentTarget.textContent) return
    this.load()
  }

  disconnect() {
    this.request?.abort()
    this.observer.disconnect()
  }

  async load() {
    this.request?.abort()
    const request = new AbortController()
    this.request = request
    this.retryTarget.hidden = true
    this.statusTarget.hidden = false
    this.statusTarget.textContent = "Loading AI summary…"
    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        signal: request.signal,
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
        },
        body: JSON.stringify({ token: this.tokenValue })
      })
      const data = await response.json()
      if (!response.ok) throw new Error(data.error || "The AI summary is unavailable. Please try again.")
      this.contentTarget.textContent = data.summary
      this.contentTarget.hidden = false
      this.statusTarget.textContent = "AI summary loaded."
      this.statusTarget.classList.add("visually-hidden")
      this.updateToggle()
    } catch (error) {
      if (request.signal.aborted) return
      this.statusTarget.textContent = error.message
      this.retryTarget.hidden = false
    }
  }

  updateToggle() {
    const expanded = this.toggleTarget.getAttribute("aria-expanded") === "true"
    this.toggleTarget.hidden = !expanded && this.contentTarget.scrollHeight <= this.contentTarget.clientHeight + 1
  }

  toggle() {
    const expanded = this.toggleTarget.getAttribute("aria-expanded") !== "true"
    this.toggleTarget.setAttribute("aria-expanded", String(expanded))
    this.toggleTarget.textContent = expanded ? "Show less" : "Show more"
    this.contentTarget.classList.toggle("is-expanded", expanded)
    this.updateToggle()
  }

  dismiss() {
    this.element.remove()
  }
}
