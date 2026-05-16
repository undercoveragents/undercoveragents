import { Controller } from "@hotwired/stimulus"

// A generic dialog controller using the HTML <dialog> element.
// Opens/closes a modal dialog and handles backdrop clicks and Escape key.
//
// Usage:
//   %div{ data: { controller: "dialog" } }
//     %button{ data: { action: "dialog#open" } } Open
//     %dialog{ data: { dialog_target: "dialog" } }
//       %button{ data: { action: "dialog#close" } } Close
export default class extends Controller {
  static targets = ["dialog"]

  open() {
    this.dialogTarget.showModal()
  }

  close() {
    this.dialogTarget.close()
  }

  // Close on backdrop click (click on the <dialog> element itself, not its content)
  backdropClick(event) {
    if (event.target === this.dialogTarget) {
      this.close()
    }
  }
}
