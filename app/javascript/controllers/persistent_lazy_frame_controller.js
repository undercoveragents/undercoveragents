import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.stabilize()
  }

  stabilize() {
    if (!this.element.hasAttribute("complete")) return

    this.element.removeAttribute("src")
  }
}
