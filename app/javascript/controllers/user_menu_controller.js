import { Controller } from "@hotwired/stimulus"

// Toggles a dropdown user menu anchored above the sidebar footer.
//
// Usage:
//   %div{ data: { controller: "user-menu" } }
//     %button{ data: { action: "click->user-menu#toggle", "user-menu-target": "button" } }
//       ...trigger content...
//     .user-menu-dropdown{ data: { "user-menu-target": "dropdown" } }
//       ...menu items...
export default class extends Controller {
  static targets = ["dropdown"]

  connect() {
    this._clickOutside = this.clickOutside.bind(this)
    document.addEventListener("click", this._clickOutside)
  }

  disconnect() {
    document.removeEventListener("click", this._clickOutside)
  }

  toggle(event) {
    event.stopPropagation()
    this.dropdownTarget.classList.toggle("is-open")
  }

  close() {
    this.dropdownTarget.classList.remove("is-open")
  }

  clickOutside(event) {
    if (!this.element.contains(event.target)) {
      this.close()
    }
  }
}
