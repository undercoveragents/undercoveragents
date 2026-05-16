import { Turbo } from "@hotwired/turbo-rails"

export class ChatTransport {
  constructor(chat, options) {
    this.chat = chat
    this.options = options
    this.refreshInFlight = false
    this.staleCheckTimer = null
  }

  async post(url, { body, allowStreamingMessages = false } = {}) {
    try {
      const response = await fetch(url, {
        method: "POST",
        body,
        credentials: "same-origin",
        headers: {
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content,
          Accept: "text/vnd.turbo-stream.html",
        },
      })

      await this.renderTurboResponse(response, { allowStreamingMessages })
      return response.ok
    } catch (_) {
      // Ignore and rely on stream catch-up when the request succeeds server-side.
      return false
    }
  }

  startPolling() {
    this.startFallbackPolling()
  }

  stopPolling() {
    this.stopFallbackPolling()
  }

  async refreshConversation({ force = false, allowStreamingMessages = false } = {}) {
    if (!this.chat.hasPollUrlValue || this.refreshInFlight) return
    if (!force && !this.chat.streamingValue) return

    this.refreshInFlight = true
    const requestedAt = Date.now()

    try {
      const response = await fetch(this.chat.pollUrlValue, {
        headers: { Accept: "text/vnd.turbo-stream.html" },
        credentials: "same-origin",
      })

      await this.renderTurboResponse(response, { allowStreamingMessages, requestedAt })
    } finally {
      this.refreshInFlight = false
    }
  }

  refreshIfStale() {
    if (!this.chat.streamingValue || this.refreshInFlight) return
    if (Date.now() - this.chat.lastUpdateAt < this.options.fallbackStaleThreshold) return

    this.refreshConversation()
  }

  async renderTurboResponse(response, { allowStreamingMessages = false, requestedAt = null } = {}) {
    if (!response || !response.ok) return

    const rawBody = await response.text()
    if (!rawBody) return

    const { body, replacesMessages } = this.prepareTurboResponse(rawBody, { allowStreamingMessages, requestedAt })
    if (!body) return

    if (replacesMessages) {
      this.chat.streamController()?.liveStream?.resetTransientState()
    }

    Turbo.renderStreamMessage(body)
    this.chat.streamController()?.bindPanel?.()
    this.chat.syncRenderedStatusTarget?.()
    this.chat.lastUpdateAt = Date.now()

    if (replacesMessages) {
      this.chat.scrollToBottom()
    }
  }

  prepareTurboResponse(body, { allowStreamingMessages = false, requestedAt = null } = {}) {
    const template = document.createElement("template")
    template.innerHTML = body

    const streams = Array.from(template.content.querySelectorAll("turbo-stream"))
    const responseStillStreaming = this.responseStillStreaming(streams)
    const messagesTargetId = this.messagesTargetId()
    const statusTargetId = `chat-${this.chat.chatIdValue}-status`
    const preservingLocalStream = this.shouldPreserveLocalStream()
    const staleRequest = Number.isFinite(requestedAt) && requestedAt < this.chat.lastUpdateAt

    if (staleRequest) {
      streams
        .filter((stream) => [messagesTargetId, statusTargetId].includes(stream.getAttribute("target")))
        .forEach((stream) => stream.remove())
    }

    // During active streaming, catch-up responses may update status but not the transcript.
    if (!allowStreamingMessages && ((this.chat.streamingValue && responseStillStreaming) || preservingLocalStream)) {
      streams
        .filter((stream) => stream.getAttribute("target") === messagesTargetId)
        .forEach((stream) => stream.remove())
    }

    if (preservingLocalStream) {
      streams
        .filter((stream) => stream.getAttribute("target") === statusTargetId)
        .filter((stream) => this.statusReplacementWouldStopStream(stream))
        .forEach((stream) => stream.remove())
    }

    const remainingStreams = Array.from(template.content.querySelectorAll("turbo-stream"))

    return {
      body: this.serializeFragment(template.content),
      replacesMessages: remainingStreams.some((stream) => stream.getAttribute("target") === messagesTargetId),
    }
  }

  messagesTargetId() {
    return `chat-${this.chat.chatIdValue}-messages`
  }

  responseStillStreaming(streams) {
    return streams.some((stream) => {
      if (stream.getAttribute("target") !== `chat-${this.chat.chatIdValue}-status`) return false

      const statusElement = stream.querySelector("template")?.content?.querySelector("[data-status]")
      return statusElement?.dataset.status === "streaming"
    })
  }

  shouldPreserveLocalStream() {
    return this.chat.streamingValue &&
      this.chat.localStreamActive &&
      !this.chat.recoveringExternalStream &&
      !this.localStreamIsStale()
  }

  localStreamIsStale() {
    return Date.now() - this.chat.lastUpdateAt >= this.options.fallbackStaleThreshold
  }

  statusReplacementWouldStopStream(stream) {
    const statusElement = stream.querySelector("template")?.content?.querySelector("[data-status]")
    return statusElement?.dataset.status !== "streaming"
  }

  serializeFragment(fragment) {
    return Array.from(fragment.childNodes)
      .map((node) => node.outerHTML || node.textContent || "")
      .join("")
  }

  startFallbackPolling() {
    if (!this.chat.hasPollUrlValue) return

    this.stopFallbackPolling()
    this.staleCheckTimer = setInterval(() => this.refreshIfStale(), this.options.fallbackStaleCheckInterval)
  }

  stopFallbackPolling() {
    if (this.staleCheckTimer) {
      clearInterval(this.staleCheckTimer)
      this.staleCheckTimer = null
    }
  }
}
