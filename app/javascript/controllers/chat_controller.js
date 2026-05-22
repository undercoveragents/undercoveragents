import { Controller } from "@hotwired/stimulus"
import { buildUserMessage } from "controllers/chat/dom_helpers"
import { ChatInputBehavior } from "controllers/chat/input_behavior"
import { PendingAttachments } from "controllers/chat/pending_attachments"
import { ChatTransport } from "controllers/chat/transport"

const MAX_FILE_SIZE = 20 * 1024 * 1024 // 20 MB
const MAX_FILES = 10
const FALLBACK_STALE_CHECK_INTERVAL = 1000
const FALLBACK_STALE_THRESHOLD = 4000

export default class extends Controller {
  static targets = [
    "messages",
    "input",
    "form",
    "submitButton",
    "cancelButton",
    "emptyState",
    "status",
    "dropZone",
    "fileInput",
    "attachmentPreview",
  ]

  static values = {
    streaming: { type: Boolean, default: false },
    chatId: Number,
    cancelUrl: String,
    pollUrl: String,
    attachmentAccept: String,
  }

  initialize() {
    this.messageHistory = this.messageHistory || []
    this.initializeHelpers()
    this.maxFileSize = MAX_FILE_SIZE
    this.maxFiles = MAX_FILES
    this.restoreInputFocusAfterStream = this.restoreInputFocusAfterStream || false
  }

  connect() {
    const reconnecting = this.element.dataset.chatControllerConnected === "true"

    this.initializeHelpers()

    this.beforeCacheScrollPersisted = false
    this.beforeRenderScrollPersisted = false
    this.beforeCacheHandler = this.beforeCacheHandler || (() => {
      this.stabilizePersistedMessages()
      this.persistScrollPosition()
      this.beforeCacheScrollPersisted = true
    })
    this.beforeRenderHandler = this.beforeRenderHandler || (() => {
      this.persistScrollPosition()
      this.beforeRenderScrollPersisted = true
    })
    document.addEventListener("turbo:before-cache", this.beforeCacheHandler)
    document.addEventListener("turbo:before-render", this.beforeRenderHandler)

    this.currentToolGroup = null
    this.currentToolCallsContainer = null
    this.activeToolCallCount = 0
    this.localStreamActive = this.localStreamActive || false
    this.recoveringExternalStream = this.recoveringExternalStream || false
    this.typewriterFrame = null
    this.typewriterStartAt = null
    this.typewriterDeadlineAt = null
    this.typewriterStartLength = 0
    this.pendingFiles = []
    this.dragCounter = 0
    this.lastUpdateAt = Date.now()
    this.messageHistory = this.inputBehavior.loadHistoryFromDom()

    if (reconnecting) {
      this.restorePreservedScrollPosition()
    } else {
      this.scrollToBottom()
    }

    this.element.dataset.chatControllerConnected = "true"
  }

  initializeHelpers() {
    this.inputBehavior = this.inputBehavior || new ChatInputBehavior(this)
    this.pendingAttachments = this.pendingAttachments || new PendingAttachments(this)
    this.transport = this.transport || new ChatTransport(this, {
      fallbackStaleCheckInterval: FALLBACK_STALE_CHECK_INTERVAL,
      fallbackStaleThreshold: FALLBACK_STALE_THRESHOLD,
    })
  }

  disconnect() {
    if (!this.beforeCacheScrollPersisted && !this.beforeRenderScrollPersisted) {
      this.persistScrollPosition()
    }

    document.removeEventListener("turbo:before-cache", this.beforeCacheHandler)
    document.removeEventListener("turbo:before-render", this.beforeRenderHandler)
    this.pendingAttachments?.revokeObjectURLs()
    this.transport?.stopPolling()
  }

  // ── Target Callbacks ──

  statusTargetConnected(element) {
    this.syncStatusTarget(element)
  }

  syncStatusTarget(element, { live = false } = {}) {
    const nextStatus = element.dataset.status || "idle"
    const nextPhase = element.dataset.phase || null
    const nextStreaming = nextStatus === "streaming"
    const wasStreaming = this.streamingValue

    if (!live && this.shouldPreserveLocalStreamingState(nextStatus, nextStreaming, wasStreaming)) {
      return
    }

    this.lastUpdateAt = Date.now()

    // A page that attaches to an already-running stream has lost prior transient chunks.
    if (nextStreaming && !wasStreaming && !this.localStreamActive && !live) {
      this.recoveringExternalStream = true
    }

    this.streamingValue = nextStreaming
  this.renderStatusTarget(element, nextStatus, nextPhase)

    // Preserved panels can keep stale button/input state even when the value did not change.
    this.applyStreamingUiState(nextStreaming)

    const liveStream = this.streamController()?.liveStream
    liveStream?.syncCurrentGroupState()
    liveStream?.syncThinkingState()
    liveStream?.syncWaitingPlaceholder()

    if (nextStatus === "cancelled" && this.isApplicationPanel()) {
      liveStream?.finalizeStream()
    }
  }

  renderStatusTarget(element, status, phase) {
    const showThinking = status === "streaming" && phase === "thinking"
    const showCancelled = status === "cancelled"

    element.classList.toggle("shared-chat__status-shell--visible", showThinking || showCancelled)

    if (showThinking) {
      element.innerHTML = `
        <div class="shared-chat__status-indicator shared-chat__status-indicator--streaming">
          <span class="shared-chat__status-label shared-chat__text-shimmer">Thinking…</span>
        </div>
      `
      return
    }

    if (showCancelled) {
      element.innerHTML = `
        <div class="shared-chat__status-indicator shared-chat__status-indicator--cancelled">
          <i class="fa-solid fa-ban" aria-hidden="true"></i>
          <span>Response cancelled</span>
        </div>
      `
      return
    }

    element.innerHTML = ""
  }

  syncRenderedStatusTarget() {
    if (!this.hasStatusTarget) return

    this.syncStatusTarget(this.statusTarget)
  }

  // ── Actions ──

  async submitMessage(event) {
    event.preventDefault()

    const content = this.inputTarget.value.trim()
    if ((!content && this.pendingFiles.length === 0) || this.streamingValue) return

    if (this.hasEmptyStateTarget) {
      this.emptyStateTarget.classList.add("hidden")
    }

    this.requestInputFocusAfterStream()
    this.localStreamActive = true
    this.recoveringExternalStream = false

    const references = this.currentReferencesForOptimisticMessage()
    this.addUserMessage(content, this.pendingFiles, { references })
    this.inputBehavior.rememberSubmittedMessage(content)
    this.inputTarget.value = ""
    this.inputTarget.style.height = "auto"

    const formData = new FormData(this.formTarget)
    formData.set("message[content]", content)
    this.pendingFiles.forEach((file) => {
      formData.append("message[attachments][]", file)
    })

    await this.streamController()?.waitUntilConnected?.()

    await this.transport.post(this.formTarget.action, { body: formData })

    this.pendingAttachments.clear()
    this.element.dispatchEvent(new CustomEvent("chat:submitted", { bubbles: true }))
    this.streamingValue = true
  }

  async cancelStream(event) {
    event.preventDefault()
    if (!this.chatIdValue || !this.streamingValue) return

    const url = this.cancelUrlValue || `/admin/playground/chats/${this.chatIdValue}/cancel`
    const cancelled = await this.transport.post(url)

    if (cancelled) {
      this.applyLocalCancelledState()
    }

    const statusElement = this.element.querySelector(`#chat-${this.chatIdValue}-status`)
    if (statusElement) {
      if (statusElement.dataset.status === "streaming") {
        statusElement.dataset.status = "cancelled"
        delete statusElement.dataset.phase
      }

      this.syncStatusTarget(statusElement, { live: true })
    }
  }

  submitHumanInTheLoopAnswers(event) {
    const content = event.detail?.content?.trim()
    const optimisticId = event.detail?.optimisticId
    if (!content) return

    if (this.hasEmptyStateTarget) {
      this.emptyStateTarget.classList.add("hidden")
    }

    this.requestInputFocusAfterStream()
    this.localStreamActive = true
    this.recoveringExternalStream = false
    this.addUserMessage(content, [], { optimisticId })
    this.streamingValue = true
  }

  rollbackHumanInTheLoopAnswers(event) {
    const optimisticId = event.detail?.optimisticId
    if (!optimisticId) return

    this.messagesTarget.querySelector(`[data-optimistic-id="${CSS.escape(optimisticId)}"]`)?.remove()
    this.localStreamActive = false
    this.streamingValue = false
  }

  resizeInput() {
    this.inputBehavior.resizeInput()
  }

  focusInput(event) {
    return this.inputBehavior.focusInput({ force: event?.detail?.force === true })
  }

  handleKeydown(event) {
    this.inputBehavior.handleKeydown(event)
  }

  // ── Drag & Drop (Chrome + Safari compatible) ──

  dragEnter(event) {
    event.preventDefault()
    event.stopPropagation()
    if (!this.hasDragFiles(event)) return

    this.dragCounter++
    if (this.dragCounter === 1) {
      this.dropZoneTarget.classList.add("drag-over")
    }
  }

  dragOver(event) {
    event.preventDefault()
    event.stopPropagation()
  }

  dragLeave(event) {
    event.preventDefault()
    event.stopPropagation()

    this.dragCounter--
    if (this.dragCounter <= 0) {
      this.dragCounter = 0
      this.dropZoneTarget.classList.remove("drag-over")
    }
  }

  drop(event) {
    event.preventDefault()
    event.stopPropagation()

    this.dragCounter = 0
    this.dropZoneTarget.classList.remove("drag-over")

    const files = Array.from(event.dataTransfer.files)
    if (files.length > 0) {
      this.pendingAttachments.add(files)
    }
  }

  // ── File Picker ──

  openFilePicker() {
    if (this.hasFileInputTarget) {
      this.fileInputTarget.click()
    }
  }

  filesSelected() {
    const files = Array.from(this.fileInputTarget.files)
    if (files.length > 0) {
      this.pendingAttachments.add(files)
    }
    this.fileInputTarget.value = ""
  }

  attachmentAllowed(file) {
    const accept = this.attachmentAcceptValue || this.fileInputTarget?.accept || ""
    const patterns = accept.split(",").map((pattern) => pattern.trim()).filter(Boolean)

    if (patterns.length === 0 || patterns.includes("*/*")) return true

    const contentType = file.type || ""
    const filename = (file.name || "").toLowerCase()

    return patterns.some((pattern) => {
      const normalizedPattern = pattern.toLowerCase()
      if (normalizedPattern.startsWith(".")) return filename.endsWith(normalizedPattern)
      if (normalizedPattern.endsWith("/*")) return contentType.startsWith(normalizedPattern.slice(0, -1))

      return contentType === normalizedPattern
    })
  }

  // ── Value Callbacks ──

  streamingValueChanged(value, previousValue) {
    this.applyStreamingUiState(value)
    const liveStream = this.streamController()?.liveStream

    if (value) {
      this.lastUpdateAt = Date.now()
      liveStream?.ensureStreamingMessage()
      liveStream?.syncWaitingPlaceholder()

      if (this.shouldUseFallbackPolling()) {
        this.transport.startPolling()
      }
    } else {
      this.transport.stopPolling()
    }

    const shouldRefreshRecoveredStream = !value && previousValue && this.recoveringExternalStream
    const shouldRefreshPersistedMessages = !value &&
      !this.isApplicationPanel() &&
      liveStream?.shouldRefreshPersistedMessages(previousValue)
    const shouldRefreshMissingStreamOutput = !value &&
      previousValue &&
      this.localStreamActive &&
      !this.recoveringExternalStream &&
      !liveStream?.currentStreamingMessageHasVisibleOutput()

    if (shouldRefreshRecoveredStream) {
      this.recoveringExternalStream = false
      this.localStreamActive = false
      liveStream?.resetTransientState()
      this.transport.refreshConversation({ force: true, allowStreamingMessages: true })
    } else {
      if (!value && previousValue && this.isApplicationPanel()) {
        liveStream?.finalizeStream()
      }

      if (shouldRefreshPersistedMessages || shouldRefreshMissingStreamOutput) {
        this.transport.refreshConversation({ force: true })
      }
    }

    liveStream?.syncCurrentGroupState()
    liveStream?.syncWaitingPlaceholder()

    if (!value && previousValue) {
      this.restoreInputFocusIfNeeded()
      this.localStreamActive = false
    }
  }

  applyStreamingUiState(streaming) {
    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.classList.toggle("hidden", streaming)
    }

    if (this.hasCancelButtonTarget) {
      this.cancelButtonTarget.classList.toggle("hidden", !streaming)
    }

    if (this.hasInputTarget) {
      this.inputTarget.readOnly = streaming
    }
  }

  applyLocalCancelledState() {
    const statusElement = this.element.querySelector(`#chat-${this.chatIdValue}-status`)
    if (statusElement) {
      statusElement.dataset.status = "cancelled"
      delete statusElement.dataset.phase
    }

    this.recoveringExternalStream = false
    this.localStreamActive = false
    this.streamingValue = false
    this.applyStreamingUiState(false)

    const liveStream = this.streamController()?.liveStream
    liveStream?.syncCurrentGroupState()
    liveStream?.syncThinkingState()
    liveStream?.syncWaitingPlaceholder()

    if (this.isApplicationPanel()) {
      liveStream?.finalizeStream()
    }
  }

  // ── Private: File Management ──

  addUserMessage(content, files = [], options = {}) {
    const messageEl = buildUserMessage({
      content,
      files,
      optimisticId: options.optimisticId,
      references: options.references || [],
    })
    this.messagesTarget.appendChild(messageEl)
    this.scrollToBottom()
  }

  // ── Private: Utilities ──

  hasDragFiles(event) {
    if (event.dataTransfer && event.dataTransfer.types) {
      return Array.from(event.dataTransfer.types).includes("Files")
    }
    return false
  }

  stabilizePersistedMessages() {
    if (!this.hasMessagesTarget) return

    this.messagesTarget.querySelectorAll(".shared-chat__message").forEach((message) => {
      message.classList.add("shared-chat__message--stable")
    })
  }

  persistScrollPosition() {
    if (!this.hasMessagesTarget) return

    this.element.dataset.chatScrollTop = String(this.messagesTarget.scrollTop)
  }

  restorePreservedScrollPosition() {
    if (!this.hasMessagesTarget) return

    const savedScrollTop = Number.parseFloat(this.element.dataset.chatScrollTop || "")
    if (!Number.isFinite(savedScrollTop)) return

    this.messagesTarget.scrollTop = savedScrollTop

    requestAnimationFrame(() => {
      if (this.hasMessagesTarget) {
        this.messagesTarget.scrollTop = savedScrollTop
      }
    })
  }

  isApplicationPanel() {
    return this.element.classList.contains("shared-chat--application")
  }

  shouldUseFallbackPolling() {
    return !this.isApplicationPanel() || this.recoveringExternalStream
  }

  shouldPreserveLocalStreamingState(nextStatus, nextStreaming, wasStreaming) {
    return wasStreaming &&
      this.localStreamActive &&
      !this.recoveringExternalStream &&
      !nextStreaming &&
      nextStatus === "idle" &&
      !this.localStreamIsStale()
  }

  localStreamIsStale() {
    return Date.now() - this.lastUpdateAt >= FALLBACK_STALE_THRESHOLD
  }

  recordStreamUpdate() {
    this.lastUpdateAt = Date.now()
  }

  currentReferencesForOptimisticMessage() {
    const input = this.element.querySelector('[data-chat-references-target="payloadInput"]')
    if (!input) return []

    try {
      const references = JSON.parse(input.value || "[]")
      return Array.isArray(references) ? references : []
    } catch {
      return []
    }
  }

  markStreamRestoredFromMemory() {
    this.localStreamActive = true
    this.recoveringExternalStream = false

    if (this.isApplicationPanel()) {
      this.transport.stopPolling()
    }
  }

  waitForStreamConnection() {
    return this.streamController()?.waitUntilConnected?.() || Promise.resolve(false)
  }

  streamController() {
    if (!window.Stimulus) return null

    const localController = window.Stimulus.getControllerForElementAndIdentifier(this.element, "chat-stream")
    if (localController) return localController

    const source = document.querySelector("#chat-stream-source")
    if (!source) return null

    return window.Stimulus.getControllerForElementAndIdentifier(source, "chat-stream")
  }

  scrollToBottom() {
    requestAnimationFrame(() => {
      if (this.hasMessagesTarget) {
        this.messagesTarget.scrollTop = this.messagesTarget.scrollHeight
      }
    })
  }

  requestInputFocusAfterStream() {
    this.restoreInputFocusAfterStream = this.hasInputTarget && this.element.contains(document.activeElement)
  }

  restoreInputFocusIfNeeded() {
    if (!this.restoreInputFocusAfterStream || !this.hasInputTarget) return

    this.restoreInputFocusAfterStream = false

    const activeElement = document.activeElement
    const activeChat = activeElement instanceof HTMLElement ? activeElement.closest(".shared-chat") : null

    if (activeChat && activeChat !== this.element) {
      return
    }

    if (activeElement instanceof HTMLElement &&
      activeElement !== document.body &&
      activeElement !== document.documentElement &&
      !activeChat) {
      return
    }

    requestAnimationFrame(() => {
      this.inputBehavior.focusInput({ force: true })
    })
  }
}
