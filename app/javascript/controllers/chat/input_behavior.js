export class ChatInputBehavior {
  constructor(chat) {
    this.chat = chat
    this.historyIndex = -1
    this.draftMessage = ""
  }

  focusInput({ force = false } = {}) {
    if (!this.chat.hasInputTarget) return false

    const textarea = this.chat.inputTarget
    if (!textarea || textarea.readOnly || textarea.disabled) return false

    const activeElement = document.activeElement
    const otherChatOwnsFocus = activeElement instanceof HTMLElement &&
      activeElement !== textarea &&
      activeElement !== document.body &&
      activeElement !== document.documentElement &&
      activeElement.closest(".shared-chat") &&
      !this.chat.element.contains(activeElement)

    if (otherChatOwnsFocus && !force) return false

    textarea.focus({ preventScroll: true })

    const caretPosition = textarea.value.length
    textarea.setSelectionRange(caretPosition, caretPosition)

    return true
  }

  loadHistoryFromDom() {
    return Array.from(
      this.chat.messagesTarget.querySelectorAll(".shared-chat__message--user .shared-chat__message-content")
    ).map((el) => el.textContent.trim()).filter(Boolean)
  }

  rememberSubmittedMessage(content) {
    if (!content) return

    this.chat.messageHistory.push(content)
    this.historyIndex = -1
    this.draftMessage = ""
  }

  resizeInput() {
    const textarea = this.chat.inputTarget
    textarea.style.height = "auto"
    textarea.style.height = `${Math.min(textarea.scrollHeight, 200)}px`
  }

  hasHistoryNavigationModifier(event) {
    return event.altKey || event.ctrlKey || event.metaKey || event.shiftKey || event.isComposing
  }

  hasCollapsedSelection() {
    return this.chat.inputTarget.selectionStart === this.chat.inputTarget.selectionEnd
  }

  isSingleLineInput() {
    return !this.chat.inputTarget.value.includes("\n")
  }

  canRecallPreviousHistory(event) {
    if (this.chat.messageHistory.length === 0) return false
    if (this.hasHistoryNavigationModifier(event) || !this.hasCollapsedSelection()) return false
    if (this.isSingleLineInput()) return true

    return this.chat.inputTarget.selectionStart === 0
  }

  canRecallNextHistory(event) {
    if (this.historyIndex === -1) return false
    if (this.hasHistoryNavigationModifier(event) || !this.hasCollapsedSelection()) return false
    if (this.isSingleLineInput()) return true

    return this.chat.inputTarget.selectionStart === this.chat.inputTarget.value.length
  }

  handleKeydown(event) {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault()
      this.chat.submitMessage(event)
      return
    }

    if (event.key === "ArrowUp") {
      if (!this.canRecallPreviousHistory(event)) return

      event.preventDefault()
      const value = this.chat.inputTarget.value
      if (this.historyIndex === -1) {
        this.draftMessage = value
      }

      const nextIndex = this.historyIndex + 1
      if (nextIndex < this.chat.messageHistory.length) {
        this.historyIndex = nextIndex
        this.chat.inputTarget.value = this.chat.messageHistory[this.chat.messageHistory.length - 1 - this.historyIndex]
        this.resizeInput()
        this.chat.inputTarget.selectionStart = 0
        this.chat.inputTarget.selectionEnd = 0
      }
      return
    }

    if (event.key === "ArrowDown") {
      if (!this.canRecallNextHistory(event)) return

      event.preventDefault()
      const nextIndex = this.historyIndex - 1
      if (nextIndex < 0) {
        this.historyIndex = -1
        this.chat.inputTarget.value = this.draftMessage
      } else {
        this.historyIndex = nextIndex
        this.chat.inputTarget.value = this.chat.messageHistory[this.chat.messageHistory.length - 1 - this.historyIndex]
      }

      this.resizeInput()
      const len = this.chat.inputTarget.value.length
      this.chat.inputTarget.selectionStart = len
      this.chat.inputTarget.selectionEnd = len
    }
  }
}
