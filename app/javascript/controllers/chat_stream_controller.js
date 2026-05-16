import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable/src"
import { visit } from "@hotwired/turbo"
import { ChatLiveStream } from "controllers/chat/live_stream"

export default class extends Controller {
  static values = {
    channel: { type: String, default: "ChatStreamChannel" },
    contentFrameId: { type: String, default: "app-content-frame" },
    contextInputName: { type: String, default: "message[ui_context_token]" },
    contextTokenSelector: String,
    frameId: String,
    frameStorageKey: String,
    headerTitleSelector: String,
    streamToken: String,
  }

  initialize() {
    this.liveStream = this.liveStream || new ChatLiveStream(this)
    this.consumer ||= null
    this.subscription ||= null
    this.connected = false
    this.createReadyPromise()
  }

  connect() {
    this.restoreFrameLocation()
    this.bindPanel()
    this.persistCurrentChatLocation()
    this.syncHeaderTitle()
    this.syncContextToken()
    this.subscribe()
    this.liveStream.restoreStreamingContent()
  }

  disconnect() {
    this.subscription?.unsubscribe()
    this.subscription = null
    this.markDisconnected()
  }

  frameLoaded(event) {
    if (event.target?.id === this.contentFrameIdValue) {
      this.syncContextToken()
      return
    }

    if (!this.hasFrameIdValue || event.target?.id !== this.frameIdValue) return

    this.bindPanel()
    this.persistCurrentChatLocation(event.target)
    this.syncHeaderTitle(event.target)
    this.syncContextToken()
    this.liveStream.restoreStreamingContent()
  }

  syncContextToken() {
    this.bindPanel()

    const input = this.contextTokenInput()
    if (!input) return

    input.value = this.currentPageContextToken()
  }

  bindPanel() {
    const frame = this.hasFrameIdValue ? document.getElementById(this.frameIdValue) : null
    const panel = frame?.querySelector(".shared-chat") ||
      (this.element.classList.contains("shared-chat") ? this.element : this.element.querySelector(".shared-chat"))

    this.frame = frame || null
    this.panelElement = panel || null
    this.messagesElement = panel?.querySelector('[data-chat-target="messages"]') || null
  }

  subscribe() {
    if (this.subscription || !this.hasStreamTokenValue) return

    this.consumer ||= createConsumer()
    this.subscription = this.consumer.subscriptions.create(
      {
        channel: this.channelValue,
        stream_token: this.streamTokenValue,
      },
      {
        connected: () => this.markConnected(),
        disconnected: () => this.markDisconnected(),
        rejected: () => this.markDisconnected(),
        received: (payload) => this.received(payload),
      },
    )
  }

  async waitUntilConnected({ timeoutMs = 2000 } = {}) {
    this.subscribe()
    if (this.connected) return true

    return Promise.race([
      this.readyPromise.then(() => true),
      new Promise((resolve) => window.setTimeout(() => resolve(this.connected), timeoutMs)),
    ])
  }

  received(payload) {
    this.ensureBoundPanel()
    this.liveStream.handle(payload)
  }

  ensureBoundPanel() {
    if (this.panelElement?.isConnected && this.messagesElement?.isConnected) return

    this.bindPanel()
  }

  currentChatId() {
    this.ensureBoundPanel()

    return this.currentChatIdForFrame() ||
      this.panelElement?.querySelector('input[name="message[chat_id]"]')?.value ||
      this.panelElement?.dataset?.chatChatIdValue ||
      null
  }

  currentChatIdForFrame(frame = this.frame) {
    return frame?.querySelector('input[name="message[chat_id]"]')?.value || null
  }

  restoreFrameLocation() {
    if (!this.hasFrameIdValue) return

    const frame = document.getElementById(this.frameIdValue)
    if (!frame) return

    const storedLocation = this.loadFrameLocation()
    if (!storedLocation) return

    frame.setAttribute("src", storedLocation)
  }

  persistCurrentChatLocation(frame = this.frame) {
    if (!this.hasFrameStorageKeyValue || !this.currentChatIdForFrame(frame)) return

    const location = this.currentFrameLocation(frame)
    if (!location) return

    try {
      window.localStorage.setItem(this.frameStorageKeyValue, location)
    } catch {
      // Ignore storage failures in restricted browsing contexts.
    }
  }

  loadFrameLocation() {
    if (!this.hasFrameStorageKeyValue) return null

    try {
      return window.localStorage.getItem(this.frameStorageKeyValue)
    } catch {
      return null
    }
  }

  currentFrameLocation(frame = this.frame) {
    const state = this.frameStateElement(frame)

    return state?.dataset?.chatStreamFrameLocation ||
      frame?.dataset?.chatStreamFrameLocation ||
      null
  }

  currentHeaderTitle(frame = this.frame) {
    return this.frameStateElement(frame)?.dataset?.chatStreamHeaderTitle || frame?.dataset?.chatStreamHeaderTitle || null
  }

  currentHeaderTitleTarget(frame = this.frame) {
    return this.frameStateElement(frame)?.dataset?.chatStreamHeaderTargetId ||
      frame?.dataset?.chatStreamHeaderTargetId ||
      "agent-alpha-panel-title-value"
  }

  frameStateElement(frame = this.frame) {
    return frame?.querySelector("[data-chat-stream-frame-state]") || null
  }

  syncHeaderTitle(frame = this.frame) {
    if (!this.hasHeaderTitleSelectorValue) return

    const title = this.currentHeaderTitle(frame)
    if (!title) return

    const titleContainer = document.querySelector(this.headerTitleSelectorValue)
    if (!titleContainer) return

    let titleElement = titleContainer.firstElementChild
    if (!(titleElement instanceof HTMLSpanElement)) {
      titleElement = document.createElement("span")
      titleContainer.replaceChildren(titleElement)
    }

    titleElement.id = this.currentHeaderTitleTarget(frame)
    titleElement.textContent = title
  }

  contentFrame() {
    return document.getElementById(this.contentFrameIdValue)
  }

  currentContentFrameLocation() {
    const frame = this.contentFrame()
    return frame?.dataset?.appContentFrameLocation || window.location.pathname + window.location.search
  }

  currentPagePath() {
    const contextPath = this.hasContextTokenSelectorValue
      ? document.querySelector(this.contextTokenSelectorValue)?.dataset?.pagePath
      : null
    return contextPath || this.currentContentFrameLocation()
  }

  refreshContentFrame(path) {
    const frame = this.contentFrame()
    if (!frame) return false

    frame.setAttribute("src", path)
    return true
  }

  navigateContentFrame(path) {
    const frame = this.contentFrame()
    if (!frame) return false

    visit(path, { frame: frame.id, action: "advance" })
    return true
  }

  currentPageContextToken() {
    if (!this.hasContextTokenSelectorValue) return ""

    return document.querySelector(this.contextTokenSelectorValue)?.dataset.pageContextToken || ""
  }

  contextTokenInput() {
    return this.panelElement?.querySelector(`input[name="${this.contextInputNameValue}"]`) || null
  }

  chatController() {
    if (!this.panelElement || !window.Stimulus) return null

    return window.Stimulus.getControllerForElementAndIdentifier(this.panelElement, "chat")
  }

  scrollToBottom() {
    const apply = () => {
      if (!this.messagesElement?.isConnected) return

      this.messagesElement.scrollTop = this.messagesElement.scrollHeight

      if (this.panelElement) {
        this.panelElement.dataset.chatScrollTop = String(this.messagesElement.scrollTop)
      }
    }

    apply()

    requestAnimationFrame(() => {
      apply()
      requestAnimationFrame(apply)
    })

    window.setTimeout(apply, 120)
  }

  createReadyPromise() {
    this.readyPromise = new Promise((resolve) => {
      this.resolveReady = resolve
    })
  }

  markConnected() {
    this.connected = true
    this.resolveReady?.(true)
  }

  markDisconnected() {
    this.connected = false
    this.createReadyPromise()
  }
}
