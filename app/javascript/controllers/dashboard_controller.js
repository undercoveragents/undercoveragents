import { Controller } from "@hotwired/stimulus"

const DISMISS_KEY = "dashboard_getting_started_dismissed"

export default class extends Controller {
  connect() {
    if (localStorage.getItem(DISMISS_KEY)) {
      this.element.remove()
    }
  }

  dismissGettingStarted() {
    localStorage.setItem(DISMISS_KEY, "1")
    this.element.remove()
  }

  openAgentAlpha(event) {
    event.preventDefault()

    document.dispatchEvent(new CustomEvent("ms:activate-sidebar-tab", {
      detail: { tab: "assistant" },
    }))
  }
}
