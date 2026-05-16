import { Controller } from "@hotwired/stimulus"

// Opens / closes the shared expression-guide <dialog>.
// Place `data-action="click->expression-guide#open"` on any trigger.
export default class extends Controller {
  static targets = ["dialog"]

  open(e) {
    e.preventDefault()
    this.dialogTarget.showModal()
  }

  close() {
    this.dialogTarget.close()
  }

  backdropClick(e) {
    if (e.target === this.dialogTarget) this.dialogTarget.close()
  }
}
