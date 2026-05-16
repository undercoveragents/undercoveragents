import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    const datetime = this.element.getAttribute("datetime")
    if (!datetime) return

    const date = new Date(datetime)
    this.element.textContent = date.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })
  }
}
