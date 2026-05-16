import { Controller } from "@hotwired/stimulus"

// A confirmation modal controller for destructive actions.
// Intercepts form submissions and shows a styled modal dialog.
//
// Attach to the button inside a button_to form:
//   button_to path, method: :delete, data: { controller: "confirm", confirm_message_value: "Are you sure?" }
//
// Works on both <form> and <button> elements — when attached to a button,
// it finds the parent form to intercept submission.
export default class extends Controller {
  static values = {
    message: { type: String, default: "Are you sure?" },
    title: { type: String, default: "Confirm Action" },
    confirmLabel: { type: String, default: "Confirm" },
    confirmIcon: { type: String, default: "" },
    confirmStyle: { type: String, default: "primary" },
    cancelLabel: { type: String, default: "Cancel" },
  }

  connect() {
    // button_to puts data attrs on the <button>, not the <form>
    this.form = this.element.closest("form") || this.element
    this.form.addEventListener("submit", this.intercept)
  }

  disconnect() {
    this.form.removeEventListener("submit", this.intercept)
    this.removeModal()
  }

  intercept = (event) => {
    if (this.confirmed) {
      this.confirmed = false
      return // allow the real submission
    }

    event.preventDefault()
    event.stopPropagation()
    this.showModal()
  }

  showModal() {
    this.overlay = document.createElement("div")
    this.overlay.className = "confirm-overlay"
    this.overlay.innerHTML = `
      <div class="confirm-modal" role="dialog" aria-modal="true" aria-labelledby="confirm-title">
        <div class="confirm-header">
          <div class="confirm-icon">
            <i class="fa-solid fa-triangle-exclamation"></i>
          </div>
          <h3 id="confirm-title" class="confirm-title">${this.titleValue}</h3>
        </div>
        <p class="confirm-message">${this.messageValue}</p>
        <div class="confirm-actions">
          <button type="button" class="btn btn-secondary" data-action="cancel">
            ${this.cancelLabelValue}
          </button>
          <button type="button" class="btn ${this.confirmBtnClass}" data-action="confirm">
            ${this.confirmIconHtml}
            ${this.confirmLabelValue}
          </button>
        </div>
      </div>
    `

    this.overlay.addEventListener("click", this.onOverlayClick)
    this.handleKeydown = (e) => { if (e.key === "Escape") this.cancel() }
    document.addEventListener("keydown", this.handleKeydown)

    document.body.appendChild(this.overlay)

    // Focus the cancel button
    requestAnimationFrame(() => {
      this.overlay.querySelector('[data-action="cancel"]')?.focus()
    })
  }

  onOverlayClick = (event) => {
    const action = event.target.closest("[data-action]")?.dataset?.action
    if (action === "confirm") {
      this.confirmAction()
    } else if (action === "cancel" || event.target === this.overlay) {
      this.cancel()
    }
  }

  get confirmBtnClass() {
    return this.confirmStyleValue === "danger" ? "btn-danger-outline" : "btn-primary"
  }

  get confirmIconHtml() {
    return this.confirmIconValue ? `<i class="${this.confirmIconValue} mr-1"></i>` : ""
  }

  confirmAction() {
    this.removeModal()
    this.confirmed = true
    this.form.requestSubmit()
  }

  cancel() {
    this.removeModal()
  }

  removeModal() {
    if (this.overlay) {
      document.removeEventListener("keydown", this.handleKeydown)
      this.overlay.remove()
      this.overlay = null
    }
  }
}
