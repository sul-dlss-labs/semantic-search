import { Controller } from "@hotwired/stimulus"

// Publishes the element's own height so the stylesheet can park it one card-height above the
// bottom of the viewport and let `position: sticky` do the scroll math.
export default class extends Controller {
  connect() {
    // Published before the class lands, so the card is never sticky with the height still unset.
    this.publishHeight()
    this.observer = new ResizeObserver(() => this.publishHeight())
    this.observer.observe(this.element)
    this.element.classList.add("is-dockable")
  }

  disconnect() {
    this.observer.disconnect()
    this.element.classList.remove("is-dockable")
  }

  publishHeight() {
    this.element.style.setProperty("--ask-ai-card-height", `${this.element.offsetHeight}px`)
  }
}
