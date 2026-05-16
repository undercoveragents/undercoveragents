import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    collapsed: { type: Boolean, default: false },
  }
  static targets = ["chatList", "sidebar"]

  connect() {
    this.syncState()
  }

  toggle() {
    this.collapsedValue = !this.collapsedValue
    this.syncState()
  }

  open() {
    this.collapsedValue = false
    this.syncState()
  }

  close() {
    this.collapsedValue = true
    this.syncState()
  }

  syncState() {
    if (!this.hasSidebarTarget) return
    if (this.collapsedValue) {
      this.sidebarTarget.classList.add("collapsed")
    } else {
      this.sidebarTarget.classList.remove("collapsed")
    }
  }
}
