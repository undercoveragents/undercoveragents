import { Controller } from "@hotwired/stimulus"

/**
 * PlaygroundSidebarController
 *
 * Manages the chat sidebar in the playground:
 * - Highlights the active chat
 * - Handles new chat creation
 * - Handles chat deletion
 */
export default class extends Controller {
  static targets = ["chatList", "chatItem"]

  static values = {
    activeChatId: Number,
  }

  connect() {
    this.highlightActiveChat()
  }

  highlightActiveChat() {
    if (!this.hasChatItemTarget) return

    this.chatItemTargets.forEach((item) => {
      const chatId = parseInt(item.dataset.chatId)
      item.classList.toggle("active", chatId === this.activeChatIdValue)
    })
  }

  activeChatIdValueChanged() {
    this.highlightActiveChat()
  }
}
