import { Controller } from "@hotwired/stimulus"

// Collapsible sections in the inspector
export default class extends Controller {
  static targets = ["body", "icon"]
  static values = { expanded: { type: Boolean, default: true } }

  connect() {
    this.#render()
  }

  toggle() {
    this.expandedValue = !this.expandedValue
    this.#render()
  }

  #render() {
    if (this.hasBodyTarget) {
      this.bodyTarget.style.display = this.expandedValue ? "" : "none"
    }
    if (this.hasIconTarget) {
      this.iconTarget.style.transform = this.expandedValue ? "rotate(0deg)" : "rotate(-90deg)"
    }
  }
}
