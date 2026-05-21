import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "category", "comment", "positiveButton", "negativeButton", "error"]

  static values = {
    feedbackUrl: String,
    uiContextSelector: String,
  }

  async submitPositiveFeedback(event) {
    event.preventDefault()
    await this.submitFeedback("positive", event.currentTarget)
  }

  openNegativeFeedback(event) {
    event.preventDefault()
    if (!this.hasDialogTarget) return

    this.clearError()
    this.element.classList.add("is-open")
    this.dialogTarget.showModal()
  }

  closeFeedback(event) {
    event?.preventDefault?.()
    if (!this.hasDialogTarget) return

    this.element.classList.remove("is-open")
    if (this.dialogTarget.open) this.dialogTarget.close()
  }

  backdropClick(event) {
    if (event.target === this.dialogTarget) {
      this.closeFeedback()
    }
  }

  async submitNegativeFeedback(event) {
    event.preventDefault()
    await this.submitFeedback("negative", event.currentTarget, {
      category: this.hasCategoryTarget ? this.categoryTarget.value : "",
      comment: this.hasCommentTarget ? this.commentTarget.value : "",
    })
  }

  async submitFeedback(value, button, details = {}) {
    if (!this.hasFeedbackUrlValue) return

    this.clearError()
    this.setBusy(button, true)

    const formData = new FormData()
    formData.append("feedback[value]", value)
    if (details.category) formData.append("feedback[category]", details.category)
    if (details.comment) formData.append("feedback[comment]", details.comment)

    try {
      await this.post(this.feedbackUrlValue, formData)
      this.markFeedbackSelection(value)
      if (value === "negative") this.closeFeedback()
    } catch (error) {
      this.showError(error.message)
    } finally {
      this.setBusy(button, false)
    }
  }

  markFeedbackSelection(value) {
    if (this.hasPositiveButtonTarget) {
      this.toggleFeedbackButton(this.positiveButtonTarget, value === "positive", "positive")
    }

    if (this.hasNegativeButtonTarget) {
      this.toggleFeedbackButton(this.negativeButtonTarget, value === "negative", "negative")
    }
  }

  toggleFeedbackButton(button, selected, value) {
    button.classList.toggle("is-selected", selected)
    if (selected) {
      button.dataset.feedbackValue = value
    } else {
      delete button.dataset.feedbackValue
    }
  }

  setBusy(button, busy) {
    if (!button) return

    button.disabled = busy
    button.classList.toggle("is-busy", busy)
  }

  showError(message) {
    if (!this.hasErrorTarget) return

    this.errorTarget.textContent = message
    this.errorTarget.classList.remove("hidden")
  }

  clearError() {
    if (!this.hasErrorTarget) return

    this.errorTarget.textContent = ""
    this.errorTarget.classList.add("hidden")
  }

  currentUiContextToken() {
    if (!this.hasUiContextSelectorValue) return null

    return document.querySelector(this.uiContextSelectorValue)?.dataset?.pageContextToken || null
  }

  async post(url, body, { accept = "application/json" } = {}) {
    const response = await fetch(url, {
      method: "POST",
      body,
      credentials: "same-origin",
      headers: {
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content,
        Accept: accept,
      },
    })

    if (response.ok) return response

    const message = await this.errorMessage(response)
    throw new Error(message)
  }

  async errorMessage(response) {
    const contentType = response.headers.get("content-type") || ""

    if (contentType.includes("application/json")) {
      const payload = await response.json()
      if (Array.isArray(payload.errors) && payload.errors.length > 0) {
        return payload.errors.join(", ")
      }
    }

    return "Could not submit your request."
  }
}
