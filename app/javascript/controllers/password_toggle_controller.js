import { Controller } from "@hotwired/stimulus"

// Toggles password field visibility between masked and plain text
export default class extends Controller {
  static targets = ["input", "icon"]

  toggle() {
    const isPassword = this.inputTarget.type === "password"
    this.inputTarget.type = isPassword ? "text" : "password"

    this.iconTarget
      .querySelector("i")
      .classList.replace(
        isPassword ? "fa-eye" : "fa-eye-slash",
        isPassword ? "fa-eye-slash" : "fa-eye"
      )
  }
}
