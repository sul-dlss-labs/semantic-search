import { Controller } from "@hotwired/stimulus"

const storageKey = "safari-notice-dismissed"

// Shows the Safari compatibility notice to Safari users until they dismiss it.
// Safari's PDF viewer ignores the #page fragment, so deep links into PDFs open at the first page.
export default class extends Controller {
  connect() {
    this.element.hidden = !this.isSafari() || this.isDismissed()
  }

  dismiss() {
    this.element.hidden = true
    try {
      localStorage.setItem(storageKey, "true")
    } catch {
      // Storage can be unavailable (e.g. private browsing); the notice just returns next page load.
    }
  }

  // Chromium, Firefox, Edge, and Opera all mention "Safari" in their user agents too.
  isSafari() {
    const userAgent = navigator.userAgent
    return /Safari/.test(userAgent) && !/Chrome|Chromium|CriOS|FxiOS|EdgiOS|Edg|OPR|Android/.test(userAgent)
  }

  isDismissed() {
    try {
      return localStorage.getItem(storageKey) === "true"
    } catch {
      return false
    }
  }
}
