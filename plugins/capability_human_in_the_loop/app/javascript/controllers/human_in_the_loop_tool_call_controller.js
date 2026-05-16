import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    stylesheetUrl: String,
  }

  connect() {
    this.ensureStylesheet()
  }

  async submit(event) {
    event.preventDefault()

    const form = event.currentTarget
    const wrapperId = this.element.id
    const optimisticMessage = this.buildOptimisticMessage(form)
    const optimisticId = optimisticMessage ? this.generateOptimisticId() : null
    this.setBusy(true, form)

    if (optimisticMessage && optimisticId) {
      this.dispatch("submitted", { detail: { content: optimisticMessage, optimisticId } })
    }

    await this.waitForChatStreamConnection()

    try {
      const response = await fetch(form.action, {
        method: (form.method || "post").toUpperCase(),
        headers: {
          Accept: "text/html",
          "X-CSRF-Token": this.csrfToken(),
        },
        body: new FormData(form),
        credentials: "same-origin",
      })

      const html = await response.text()

      if (!response.ok && optimisticId) {
        this.dispatch("failed", { detail: { optimisticId } })
      }

      this.element.outerHTML = html

      if (!response.ok) {
        document.getElementById(wrapperId)?.querySelector(".hitl-widget__error, .hitl-widget__error-banner")
          ?.scrollIntoView({ behavior: "smooth", block: "nearest" })
      }
    } catch {
      if (optimisticId) {
        this.dispatch("failed", { detail: { optimisticId } })
      }

      this.element.insertAdjacentHTML("afterbegin", this.errorMarkup("Could not submit your answers. Please try again."))
    } finally {
      this.setBusy(false, form)
    }
  }

  scrollToQuestion(event) {
    const questionId = event.currentTarget.dataset.questionId
    if (!questionId) return

    const target = this.element.querySelector(`[data-question-anchor="${questionId}"]`)
    if (!target) return

    target.classList.add("is-focused")
    target.scrollIntoView({ behavior: "smooth", block: "nearest" })
    window.setTimeout(() => target.classList.remove("is-focused"), 1200)
  }

  syncSelection(event) {
    const question = event.currentTarget.closest("[data-question-anchor]")
    if (!question) return

    const textarea = question.querySelector(".hitl-widget__custom-textarea")
    if (textarea && textarea.value.trim().length === 0) return

    if (textarea) textarea.value = ""
  }

  customInput(event) {
    if (event.currentTarget.value.trim().length === 0) return

    const question = event.currentTarget.closest("[data-question-anchor]")
    if (!question) return

    question.querySelectorAll(".hitl-widget__choice-input").forEach((input) => {
      input.checked = false
    })
  }

  ensureStylesheet() {
    if (!this.hasStylesheetUrlValue) return
    if (document.head.querySelector(`link[data-hitl-stylesheet="${this.stylesheetUrlValue}"]`)) return

    const link = document.createElement("link")
    link.rel = "stylesheet"
    link.href = this.stylesheetUrlValue
    link.dataset.hitlStylesheet = this.stylesheetUrlValue
    document.head.appendChild(link)
  }

  async waitForChatStreamConnection() {
    await this.chatController()?.waitForStreamConnection?.()
  }

  chatController() {
    if (!window.Stimulus) return null

    const chatElement = this.element.closest(".shared-chat")
    if (!chatElement) return null

    return window.Stimulus.getControllerForElementAndIdentifier(chatElement, "chat")
  }

  setBusy(isBusy, form = null) {
    const submitButton = form?.querySelector(".hitl-widget__submit") || this.element.querySelector(".hitl-widget__submit")
    if (!submitButton) return

    submitButton.disabled = isBusy
  }

  csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
  }

  errorMarkup(message) {
    return `<p class="hitl-widget__error-banner">${this.escapeHtml(message)}</p>`
  }

  buildOptimisticMessage(form) {
    const lines = ["Clarification answers:"]
    const promptText = this.element.querySelector(".hitl-widget__intro")?.textContent?.trim()

    if (promptText) {
      lines.push(`Clarification context: ${promptText}`)
    }

    form.querySelectorAll("[data-question-anchor]").forEach((question, index) => {
      const prompt = question.querySelector(".hitl-widget__question-prompt")?.textContent?.trim()
      const customAnswer = question.querySelector(".hitl-widget__custom-textarea")?.value?.trim()
      const selectedOption = question.querySelector(".hitl-widget__choice-input:checked")?.value?.trim()
      const answer = customAnswer || selectedOption

      if (!prompt || !answer) return

      lines.push(`${index + 1}. ${prompt}`)
      lines.push(`Answer: ${answer}`)
    })

    return lines.length > 1 ? lines.join("\n") : ""
  }

  generateOptimisticId() {
    if (globalThis.crypto?.randomUUID) return globalThis.crypto.randomUUID()

    return `hitl-${Date.now()}-${Math.random().toString(36).slice(2, 10)}`
  }

  escapeHtml(value) {
    const div = document.createElement("div")
    div.textContent = value
    return div.innerHTML
  }
}
