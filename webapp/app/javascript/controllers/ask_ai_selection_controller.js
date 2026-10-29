import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["link", "status"]
  static values = { href: String }

  connect() {
    this.update()
  }

  update() {
    const ids = Array.from(document.querySelectorAll("[data-ask-ai-select]:checked"), (input) => input.value)

    const url = new URL(this.hrefValue, window.location.origin)
    ids.forEach((id) => url.searchParams.append("selected_ids[]", id))
    this.linkTarget.href = url.pathname + url.search

    this.statusTarget.textContent = ids.length === 0 ? "" : `${ids.length} ${ids.length === 1 ? "result" : "results"} selected`
  }
}
