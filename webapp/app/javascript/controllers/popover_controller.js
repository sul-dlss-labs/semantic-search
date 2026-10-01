import { Controller } from "@hotwired/stimulus"
// The pinned Bootstrap build is UMD, so the components hang off the default export.
import bootstrap from "bootstrap"

// Dismissible popovers in the SUL component-library style: the header carries a close button so the
// popover stays put while it is read or copied out of, instead of closing on the next click.
// See https://sul-dlss.github.io/component-library/popovers/
const template = `<div class="popover" role="tooltip">
                    <div class="popover-arrow"></div>
                    <div class="popover-header"></div>
                    <div class="popover-body"></div>
                  </div>`

const header = (title) => `<div class="d-flex justify-content-between align-content-center">
                             <div class="fw-semibold align-self-center">${title}</div>
                             <button type="button" class="btn p-0 ms-2 fs-5 lh-1"
                                     aria-label="Close" data-popover-dismiss>
                               <i class="bi bi-x"></i>
                             </button>
                           </div>`

const allowList = {
  "*": [ "class", "role", /^aria-[\w-]+$/ ],
  div: [],
  button: [ "type", "data-popover-dismiss" ],
  i: []
}

export default class extends Controller {
  static targets = ["trigger"]

  connect() {
    this.popovers = this.triggerTargets.map((trigger) => this.build(trigger))
  }

  disconnect() {
    this.popovers.forEach((popover) => popover.dispose())
  }

  build(trigger) {
    const popover = new bootstrap.Popover(trigger, {
      template,
      html: true,
      title: () => header(trigger.dataset.bsTitle),
      allowList
    })

    trigger.addEventListener("shown.bs.popover", () => {
      const tip = document.getElementById(trigger.getAttribute("aria-describedby"))
      tip?.querySelector("[data-popover-dismiss]")?.addEventListener("click", () => popover.hide())
    })

    return popover
  }
}
