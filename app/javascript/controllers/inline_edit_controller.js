import { Controller } from "@hotwired/stimulus"

// Toggles between display and edit mode for inline editable sections
export default class extends Controller {
  static targets = ["display", "editor", "editBtn"]

  toggle() {
    this.displayTarget.classList.toggle("hidden")
    this.editorTarget.classList.toggle("hidden")

    if (this.editorTarget.classList.contains("hidden")) {
      this.editBtnTarget.innerHTML =
        '<i class="fa-solid fa-pen mr-1"></i>Edit'
    } else {
      this.editBtnTarget.innerHTML =
        '<i class="fa-solid fa-xmark mr-1"></i>Cancel'
    }
  }
}
