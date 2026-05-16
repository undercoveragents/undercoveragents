import { visit } from "@hotwired/turbo"
import { getMarkdown } from "stream-markdown-parser"
import {
  assistantMessageHasVisibleText,
  assistantMessageHasVisibleOutput,
  buildWaitingPlaceholder,
  buildToolGroup,
  buildToolTimelineItem,
  countToolOutputs,
  ensureAssistantBubble,
  ensureAssistantPanel,
  ensureThinkingBlock,
  parseToolWidgetMessages,
  promoteTimelineItemToSubagentBranch,
  transientAssistantMessageIsEmpty,
  updateThinkingBody,
} from "controllers/chat/dom_helpers"
import { overrideFenceRenderer } from "utils/markdown"
import { prettifyDownloadLinks } from "utils/download_links"

export class ChatLiveStream {
  constructor(owner) {
    this.owner = owner
    this.state = {
      activeChatId: null,
      content: "",
      thinking: "",
    }
    this.hadToolOutputs = false
    this.childStreams = new Map()
    this.currentToolGroup = null
    this.currentToolCallsContainer = null
    this.activeToolCallCount = 0
  }

  get panelElement() {
    return this.owner.panelElement
  }

  get messagesElement() {
    return this.owner.messagesElement
  }

  handle(payload) {
    if (this.shouldIgnoreCancelledPayload(payload)) {
      return
    }

    this.chatController()?.recordStreamUpdate?.()

    switch (payload?.type) {
      case "chunk":
        this.onChunk(payload)
        break
      case "status":
        this.onStatus(payload)
        break
      case "tool_event":
        this.onToolEvent(payload)
        break
      case "error":
        this.onError(payload)
        break
      case "navigate":
        this.onNavigate(payload)
        break
      case "refresh":
        this.onRefresh(payload)
        break
      case "chat_title":
        this.onChatTitle(payload)
        break
      default:
        break
    }
  }

  onChatTitle(payload) {
    if (!payload?.target) return

    const titleElement = document.getElementById(payload.target)
    if (!titleElement) return

    titleElement.textContent = payload.title || ""
  }

  shouldIgnoreCancelledPayload(payload) {
    if (!payload || !["chunk", "status", "tool_event", "error"].includes(payload.type)) {
      return false
    }

    const currentChatId = this.currentChatId()
    const rootChatId = payload.parent_chat_id == null ? payload.chat_id : payload.parent_chat_id
    if (!currentChatId || String(rootChatId) !== currentChatId) return false

    const statusElement = this.panelElement?.querySelector(`#chat-${currentChatId}-status`)
    if (!statusElement || statusElement.dataset.status !== "cancelled") return false

    const chatController = this.chatController()
    return !chatController?.localStreamActive && !chatController?.recoveringExternalStream
  }

  onChunk(payload) {
    if (!payload.chat_id || !payload.content) return

    if (this.isChildPayload(payload)) {
      this.onChildChunk(payload)
      return
    }

    this.ensureActive(payload.chat_id)
    if (!this.matches(this.state.activeChatId)) return

    if (payload.kind === "thinking") {
      this.onThinkingChunk(payload)
      return
    }

    this.state.content += payload.content
    this.renderContent()
  }

  onThinkingChunk(payload) {
    if (this.currentStreamingMessageHasOnlyToolCalls()) {
      this.startNewStreamingMessage()
    }

    const messageElement = this.ensureStreamingMessage()
    if (!messageElement) return

    messageElement.querySelector(".shared-chat__bubble--placeholder")?.remove()
    this.state.thinking += payload.content
    this.renderThinking(messageElement, { open: true, streaming: true })
    this.scrollToBottom()
  }

  onStatus(payload) {
    if (!payload.chat_id) return

    if (this.isChildPayload(payload)) {
      this.onChildStatus(payload)
      return
    }

    this.ensureActive(payload.chat_id)
    if (!this.matches(this.state.activeChatId)) return

    this.applyStatus(payload.status, payload.phase)
    this.syncThinkingState(payload.phase)

    if (payload.status === "idle" || payload.status === "cancelled") {
      this.finalizeStream()
    }
  }

  onToolEvent(payload) {
    if (!payload.chat_id || !payload.display_name) return

    if (this.isChildPayload(payload)) {
      this.onChildToolEvent(payload)
      return
    }

    this.ensureActive(payload.chat_id)
    if (!this.matches(this.state.activeChatId)) return

    if (payload.event === "start") {
      this.handleToolStart(payload)
    } else if (payload.event === "complete") {
      this.handleToolComplete(payload)
    }
  }

  onError(payload) {
    if (!payload.message) return

    if (this.isChildPayload(payload)) {
      this.onChildError(payload)
      return
    }

    this.ensureActive(payload.chat_id || this.state.activeChatId)
    if (!this.matches(this.state.activeChatId)) return

    const separator = this.state.content ? "\n\n" : ""
    this.collapseThinking()
    this.state.content += `${separator}Error: ${payload.message}`
    this.renderContent()
    this.finalizeStream()
  }

  onNavigate(payload) {
    if (!payload?.path) return

    const chatId = payload.chat_id == null ? null : String(payload.chat_id)
    if (chatId) {
      const currentChatId = this.currentChatId()
      const activeChatId = this.state.activeChatId
      const matchesCurrent = chatId === currentChatId || chatId === activeChatId

      if (!matchesCurrent && !this.isChildPayload(payload)) return
    }

    if (this.owner.navigateContentFrame?.(payload.path)) return

    visit(payload.path)
  }

  onRefresh(payload) {
    if (!payload?.path) return

    if (!this.currentLocationMatches(payload.current_path || payload.path)) return

    this.owner.refreshContentFrame(payload.path)
  }

  onChildChunk(payload) {
    const childState = this.trackChildStream(payload)
    if (!childState) return

    if (payload.kind === "thinking") {
      if (this.childMessageHasOnlyToolCalls(childState)) {
        this.startNewChildMessage(childState)
      }

      childState.thinking += payload.content
      this.renderChildThinking(childState, { open: true, streaming: true })
      return
    }

    if (this.childMessageHasOnlyToolCalls(childState)) {
      this.startNewChildMessage(childState)
    }

    childState.content += payload.content
    this.renderChildContent(childState)
  }

  onChildStatus(payload) {
    const childState = this.trackChildStream(payload)
    if (!childState) return

    childState.status = payload.status || childState.status
    childState.phase = payload.phase || null

    this.syncChildThinkingState(childState)

    if (payload.status === "idle" || payload.status === "cancelled") {
      this.finalizeChildStream(childState)
    }
  }

  onChildError(payload) {
    const childState = this.trackChildStream(payload)
    if (!childState) return

    const separator = childState.content ? "\n\n" : ""
    childState.content += `${separator}Error: ${payload.message}`
    this.collapseThinking(this.childMessageElement(childState))
    this.renderChildContent(childState)
    this.finalizeChildStream(childState)
  }

  onChildToolEvent(payload) {
    const childState = this.trackChildStream(payload)
    if (!childState) return

    if (payload.event === "start") {
      this.handleChildToolStart(childState, payload)
      return
    }

    if (payload.event === "complete") {
      this.handleChildToolComplete(childState, payload)
    }
  }

  ensureActive(chatId) {
    const normalized = chatId == null ? null : String(chatId)
    if (this.state.activeChatId === normalized) return

    this.state.activeChatId = normalized
    this.state.content = ""
    this.state.thinking = ""
    this.hadToolOutputs = false
    this.currentToolGroup = null
    this.currentToolCallsContainer = null
    this.activeToolCallCount = 0
  }

  applyStatus(status, phase) {
    const statusElement = this.panelElement?.querySelector(`#chat-${this.state.activeChatId}-status`)
    if (!statusElement) return

    if (status) statusElement.dataset.status = status

    if (phase) {
      statusElement.dataset.phase = phase
    } else {
      delete statusElement.dataset.phase
    }

    this.chatController()?.syncStatusTarget?.(statusElement, { live: true })
  }

  renderContent() {
    if (!this.state.content) return

    if (this.currentStreamingMessageHasOnlyToolCalls()) {
      this.startNewStreamingMessage()
    }

    const messageElement = this.ensureStreamingMessage()
    if (!messageElement) return

    messageElement.querySelector(".shared-chat__bubble--placeholder")?.remove()

    const bubble = ensureAssistantBubble(messageElement)
    bubble.dataset.markdownRenderContentValue = this.state.content
    bubble.innerHTML = this.markdown().render(this.state.content)
    prettifyDownloadLinks(bubble)
    this.scrollToBottom()
  }

  renderThinking(messageElement = this.ensureStreamingMessage(), { open = this.currentStatusPhase() === "thinking", streaming = false } = {}) {
    if (!messageElement || !this.state.thinking) return

    const body = ensureThinkingBlock(messageElement, { open, streaming })
    updateThinkingBody(body, this.state.thinking)
  }

  handleToolStart(payload) {
    this.hadToolOutputs = true

    if (this.activeToolCallCount === 0 && this.currentStreamingMessageHasContent()) {
      this.startNewStreamingMessage()
    }

    const existing = payload.tool_call_id ? this.messagesElement?.querySelector(
      `[data-tool-call-id="${CSS.escape(payload.tool_call_id)}"]`,
    ) : null
    if (existing) {
      this.promoteGenericSubagentItem(existing, {
        status: "running",
        toolDisplayName: payload.display_name,
        toolName: payload.tool_name,
      })
      this.restoreChildStreams()
      return
    }

    const messageElement = this.ensureStreamingMessage()
    if (!messageElement) return

    const recoveredItem = this.recoveredChildBranchFor(payload)
    if (recoveredItem) {
      this.promoteRecoveredChildBranch(recoveredItem, payload, "running")
      return
    }

    const widgetConfig = this.widgetConfigFor(payload)
    this.activeToolCallCount += 1

    const group = this.ensureGroup(widgetConfig.groupTitle || "")
    const item = buildToolTimelineItem({
      toolCallId: payload.tool_call_id || "",
      toolDisplayName: payload.display_name,
      toolIcon: payload.icon || "fa-solid fa-wrench",
      toolName: payload.tool_name,
      widgetConfig,
      status: "running",
    })
    this.incrementGroupActiveCount(group)
    group.querySelector(".shared-chat__tool-timeline")?.appendChild(item)
    this.restoreChildStreams()
    this.scrollToBottom()
  }

  handleToolComplete(payload) {
    this.hadToolOutputs = true

    const timelineItem = this.messagesElement?.querySelector(
      `.shared-chat__tool-timeline-item[data-tool-call-id="${CSS.escape(payload.tool_call_id || "")}"]`,
    )

    if (timelineItem) {
      this.renderTimelineItemState(timelineItem, "complete")
      timelineItem.dataset.toolWidgetStatusValue = "complete"
      timelineItem.dataset.toolWidgetInitialPhraseValue = ""
      this.syncSubagentPlaceholder(timelineItem.querySelector(".shared-chat__tool-timeline-branch"), false)

      const group = timelineItem.closest(".shared-chat__tool-group")
      if (group) {
        this.decrementGroupActiveCount(group)
      }

      this.activeToolCallCount = Math.max(0, this.activeToolCallCount - 1)
      this.scrollToBottom()
      return
    }

    const recoveredItem = this.recoveredChildBranchFor(payload)
    if (recoveredItem) {
      this.promoteRecoveredChildBranch(recoveredItem, payload, "complete")
      return
    }

    const messageElement = this.ensureStreamingMessage()
    if (!messageElement) return

    const widgetConfig = this.widgetConfigFor(payload)
    const group = this.ensureGroup(widgetConfig.groupTitle || "")
    const item = buildToolTimelineItem({
      toolCallId: payload.tool_call_id || "",
      toolDisplayName: payload.display_name,
      toolIcon: payload.icon || "fa-solid fa-wrench",
      toolName: payload.tool_name,
      widgetConfig: { ...widgetConfig, initialPhrase: widgetConfig.completeMessages?.[0] || "" },
      status: "complete",
    })
    group.querySelector(".shared-chat__tool-timeline")?.appendChild(item)
    this.syncSubagentPlaceholder(item.querySelector(".shared-chat__tool-timeline-branch"), false)

    this.activeToolCallCount = Math.max(0, this.activeToolCallCount - 1)
    this.scrollToBottom()
  }

  ensureStreamingMessage() {
    if (!this.messagesElement?.isConnected) return null

    const existing = this.messagesElement.querySelector("#streaming-message")
    if (existing) return existing

    const messageElement = document.createElement("article")
    messageElement.id = "streaming-message"
    messageElement.className = "shared-chat__message shared-chat__message--assistant"
    this.messagesElement.appendChild(messageElement)
    return messageElement
  }

  ensureToolCallsContainer(messageElement) {
    if (this.currentToolCallsContainer?.isConnected) {
      return this.currentToolCallsContainer
    }

    const panel = ensureAssistantPanel(messageElement)
    messageElement.querySelector(".shared-chat__bubble--placeholder")?.remove()
    let container = panel.querySelector(":scope > .shared-chat__tool-calls")

    if (!container) {
      container = document.createElement("div")
      container.className = "shared-chat__tool-calls"
      panel.appendChild(container)
    }

    this.currentToolCallsContainer = container
    return container
  }

  startNewStreamingMessage() {
    const messageElement = this.messagesElement?.querySelector("#streaming-message")
    if (messageElement) {
      messageElement.removeAttribute("id")
      messageElement.classList.add("shared-chat__message--stable")
    }

    if (this.currentToolGroup?.isConnected) {
      this.currentToolGroup.classList.remove("streaming")
    }

    this.state.content = ""
    this.state.thinking = ""
    this.currentToolGroup = null
    this.currentToolCallsContainer = null
    this.activeToolCallCount = 0
  }

  isChildPayload(payload) {
    const chatId = payload?.chat_id == null ? null : String(payload.chat_id)
    if (!chatId) return false
    if (chatId === this.currentChatId()) return false

    const parentChatId = payload.parent_chat_id == null ? null : String(payload.parent_chat_id)
    if (this.childStreams.has(chatId)) return true
    if (!parentChatId) return false

    return parentChatId === this.currentChatId()
  }

  trackChildStream(payload) {
    const chatId = String(payload.chat_id)
    const parentChatId = payload.parent_chat_id == null ? null : String(payload.parent_chat_id)
    let childState = this.childStreams.get(chatId)

    if (!childState) {
      childState = {
        chatId,
        parentChatId,
        agentName: payload.agent_name || "",
        branchToolCallId: null,
        content: "",
        thinking: "",
        status: null,
        phase: null,
        currentToolGroup: null,
        currentToolCallsContainer: null,
        activeToolCallCount: 0,
        markdown: null,
      }
      this.childStreams.set(chatId, childState)
    }

    if (parentChatId) childState.parentChatId = parentChatId
    if (payload.agent_name) childState.agentName = payload.agent_name

    this.findChildBranchElement(childState)
    return childState
  }

  findChildBranchElement(childState) {
    if (!this.messagesElement?.isConnected) return null

    const existingBranch = childState.branchToolCallId
      ? this.branchElementByToolCallId(childState.branchToolCallId)
      : null
    if (existingBranch) {
      existingBranch.dataset.childChatId = childState.chatId
      return existingBranch
    }

    const branch = this.assignChildBranch(childState)
    if (!branch) return this.createRecoveredChildBranch(childState)

    childState.branchToolCallId = this.branchToolCallId(branch)
    branch.dataset.childChatId = childState.chatId
    return branch
  }

  assignChildBranch(childState) {
    const candidates = Array.from(this.messagesElement.querySelectorAll(
      "details.shared-chat__tool-call--branch, .shared-chat__tool-timeline-branch",
    ))
    const expectedToolName = this.subagentToolNameFor(childState.agentName)
    const unassignedMatchingBranch = (branch) => {
      const toolCallId = this.branchToolCallId(branch)
      if (!toolCallId) return false
      if (this.childStateForToolCallId(toolCallId, childState.chatId)) return false

      const branchToolName = this.branchToolName(branch)
      if (expectedToolName && branchToolName) {
        return branchToolName === expectedToolName
      }

      if (childState.agentName && this.branchLabel(branch) !== childState.agentName) return false
      return true
    }

    return candidates.find((branch) => this.branchRunning(branch) && unassignedMatchingBranch(branch)) ||
      candidates.find(unassignedMatchingBranch) ||
      this.promoteMatchingGenericSubagentItem(childState) ||
      null
  }

  promoteMatchingGenericSubagentItem(childState) {
    const item = this.matchingGenericSubagentItem(childState)
    if (!item) return null

    const branch = this.promoteGenericSubagentItem(item, {
      toolDisplayName: childState.agentName,
      toolName: this.subagentToolNameFor(childState.agentName),
    })
    if (!branch) return null

    childState.branchToolCallId = this.branchToolCallId(branch)
    branch.dataset.childChatId = childState.chatId
    return branch
  }

  matchingGenericSubagentItem(childState) {
    const expectedToolName = this.subagentToolNameFor(childState.agentName)
    const candidates = Array.from(this.messagesElement?.querySelectorAll(
      ".shared-chat__tool-timeline-item:not(.shared-chat__tool-timeline-item--branch)",
    ) || [])
    const matches = (item) => {
      const toolCallId = item.dataset.toolCallId
      if (!toolCallId) return false
      if (this.childStateForToolCallId(toolCallId, childState.chatId)) return false

      const itemToolName = item.dataset.toolName || ""
      if (expectedToolName && itemToolName) return itemToolName === expectedToolName
      if (itemToolName && !this.subagentToolName(itemToolName)) return false
      if (childState.agentName && this.branchLabel(item) !== childState.agentName) return false

      return true
    }

    return candidates.find((item) => item.classList.contains("is-running") && matches(item)) ||
      candidates.find(matches) ||
      null
  }

  promoteGenericSubagentItem(item, options = {}) {
    const toolName = options.toolName || item?.dataset.toolName
    if (!this.subagentToolName(toolName)) return null

    return promoteTimelineItemToSubagentBranch(item, options)
  }

  branchElementByToolCallId(toolCallId) {
    if (!toolCallId || !this.messagesElement?.isConnected) return null

    return this.messagesElement.querySelector(
      `.shared-chat__tool-timeline-item[data-tool-call-id="${CSS.escape(toolCallId)}"] .shared-chat__tool-timeline-branch`,
    )
  }

  branchToolCallId(branch) {
    if (!branch) return null

    return branch.dataset.toolCallId || branch.closest("[data-tool-call-id]")?.dataset.toolCallId || null
  }

  branchToolName(branch) {
    if (!branch) return null

    return branch.dataset.toolName || branch.closest("[data-tool-name]")?.dataset.toolName || null
  }

  childStateForToolCallId(toolCallId, exceptChatId = null) {
    for (const childState of this.childStreams.values()) {
      if (childState.branchToolCallId !== toolCallId) continue
      if (exceptChatId && childState.chatId === exceptChatId) continue
      return childState
    }

    return null
  }

  branchLabel(branch) {
    return branch?.querySelector(".shared-chat__tool-call-name")?.textContent?.trim() || ""
  }

  subagentToolNameFor(agentName) {
    const normalizedName = (agentName || "")
      .normalize("NFKD")
      .replace(/[^\x00-\x7F]/g, "")
      .replace(/[^a-zA-Z0-9_-]/g, "_")
      .replace(/_+/g, "_")
      .replace(/^_+|_+$/g, "")
      .toLowerCase()

    return normalizedName ? `ask_agent_${normalizedName}` : null
  }

  branchRunning(branch) {
    if (!branch) return false
    if (branch.classList.contains("streaming")) return true

    return branch.closest(".shared-chat__tool-timeline-item")?.classList.contains("is-running") || false
  }

  createRecoveredChildBranch(childState) {
    if (!childState.agentName) return null

    const messageElement = this.ensureStreamingMessage()
    if (!messageElement) return null

    const syntheticToolCallId = `child-chat-${childState.chatId}`
    const existing = this.branchElementByToolCallId(syntheticToolCallId)
    if (existing) return existing

    const group = this.ensureGroup("")
    const item = buildToolTimelineItem({
      toolCallId: syntheticToolCallId,
      toolDisplayName: childState.agentName,
      toolIcon: "fa-solid fa-user-secret",
      toolName: this.subagentToolNameFor(childState.agentName),
      widgetConfig: {},
      status: "running",
    })

    item.dataset.syntheticChildBranch = "true"
    item.dataset.childChatId = childState.chatId
    group.querySelector(".shared-chat__tool-timeline")?.appendChild(item)
    this.incrementGroupActiveCount(group)

    const branch = item.querySelector(".shared-chat__tool-timeline-branch")
    if (!branch) return null

    childState.branchToolCallId = syntheticToolCallId
    branch.dataset.childChatId = childState.chatId
    return branch
  }

  recoveredChildBranchFor(payload) {
    if (!payload.tool_name || !this.subagentToolName(payload.tool_name)) return null

    return Array.from(this.messagesElement?.querySelectorAll(
      ".shared-chat__tool-timeline-item[data-synthetic-child-branch='true']",
    ) || []).find((item) => item.dataset.toolName === payload.tool_name) || null
  }

  promoteRecoveredChildBranch(item, payload, status) {
    const previousToolCallId = item.dataset.toolCallId
    const childState = this.childStateForToolCallId(previousToolCallId)
    if (childState) childState.branchToolCallId = payload.tool_call_id || previousToolCallId

    if (payload.tool_call_id) item.dataset.toolCallId = payload.tool_call_id
    if (payload.tool_name) item.dataset.toolName = payload.tool_name
    delete item.dataset.syntheticChildBranch

    const branch = item.querySelector(".shared-chat__tool-timeline-branch")
    if (branch && payload.tool_name) branch.dataset.toolName = payload.tool_name

    const label = item.querySelector(".shared-chat__tool-call-name")
    if (label && payload.display_name) label.textContent = payload.display_name

    this.renderTimelineItemState(item, status)
    item.dataset.toolWidgetStatusValue = status
    item.dataset.toolWidgetInitialPhraseValue = status === "complete" ? "" : this.widgetConfigFor(payload).initialPhrase

    if (status === "complete") {
      this.syncSubagentPlaceholder(branch, false)
      const group = item.closest(".shared-chat__tool-group")
      if (group) this.decrementGroupActiveCount(group)
      this.activeToolCallCount = Math.max(0, this.activeToolCallCount - 1)
    }

    this.scrollToBottom()
  }

  subagentToolName(toolName) {
    return /^ask_agent_/i.test(toolName || "")
  }

  ensureChildThread(childState) {
    return this.findChildBranchElement(childState)?.querySelector(".shared-chat__subagent-thread") || null
  }

  childMessageElement(childState) {
    if (childState.currentMessageElement?.isConnected) {
      return childState.currentMessageElement
    }

    const messageElement = this.ensureChildThread(childState)?.querySelector(
      `:scope > .shared-chat__message[data-child-chat-id="${CSS.escape(childState.chatId)}"][data-child-streaming="true"]`,
    ) || null

    childState.currentMessageElement = messageElement
    return messageElement
  }

  childHasVisibleMessages(childState) {
    return Boolean(this.ensureChildThread(childState)?.querySelector(":scope > .shared-chat__message"))
  }

  ensureChildAssistantMessage(childState) {
    const thread = this.ensureChildThread(childState)
    if (!thread) return null

    const existing = this.childMessageElement(childState)
    if (existing) return existing

    thread.querySelector(":scope > .shared-chat__subagent-empty")?.remove()

    const messageElement = document.createElement("article")
    messageElement.className = "shared-chat__message shared-chat__message--assistant"
    messageElement.dataset.childChatId = childState.chatId
    messageElement.dataset.childStreaming = "true"
    thread.appendChild(messageElement)
    childState.currentMessageElement = messageElement
    return messageElement
  }

  ensureChildToolCallsContainer(childState, messageElement = this.ensureChildAssistantMessage(childState)) {
    if (childState.currentToolCallsContainer?.isConnected) {
      return childState.currentToolCallsContainer
    }

    const panel = ensureAssistantPanel(messageElement)
    let container = panel.querySelector(":scope > .shared-chat__tool-calls")

    if (!container) {
      container = document.createElement("div")
      container.className = "shared-chat__tool-calls"
      panel.appendChild(container)
    }

    childState.currentToolCallsContainer = container
    return container
  }

  handleChildToolStart(childState, payload) {
    this.hadToolOutputs = true

    if (childState.activeToolCallCount === 0 && this.currentChildMessageHasContent(childState)) {
      this.startNewChildMessage(childState)
    }

    const messageElement = this.ensureChildAssistantMessage(childState)
    if (!messageElement) return

    const existing = messageElement.querySelector(
      `[data-tool-call-id="${CSS.escape(payload.tool_call_id || "")}"]`,
    )
    if (existing) return

    const widgetConfig = this.widgetConfigFor(payload)
    childState.activeToolCallCount += 1

    const group = this.ensureChildGroup(childState, widgetConfig.groupTitle || "")
    const item = buildToolTimelineItem({
      toolCallId: payload.tool_call_id || "",
      toolDisplayName: payload.display_name,
      toolIcon: payload.icon || "fa-solid fa-wrench",
      toolName: payload.tool_name,
      widgetConfig,
      status: "running",
    })
    this.incrementChildGroupActiveCount(group)
    group.querySelector(".shared-chat__tool-timeline")?.appendChild(item)
    this.scrollToBottom()
  }

  handleChildToolComplete(childState, payload) {
    this.hadToolOutputs = true

    const timelineItem = this.messagesElement?.querySelector(
      `.shared-chat__subagent-thread .shared-chat__tool-timeline-item[data-tool-call-id="${CSS.escape(payload.tool_call_id || "")}"]`,
    )

    if (timelineItem) {
      this.renderTimelineItemState(timelineItem, "complete")
      timelineItem.dataset.toolWidgetStatusValue = "complete"
      timelineItem.dataset.toolWidgetInitialPhraseValue = ""
      this.syncSubagentPlaceholder(timelineItem.querySelector(".shared-chat__tool-timeline-branch"), false)

      const group = timelineItem.closest(".shared-chat__tool-group")
      if (group) {
        this.decrementChildGroupActiveCount(group)
      }

      childState.activeToolCallCount = Math.max(0, childState.activeToolCallCount - 1)
      this.scrollToBottom()
      return
    }

    const messageElement = this.ensureChildAssistantMessage(childState)
    if (!messageElement) return

    const widgetConfig = this.widgetConfigFor(payload)
    const group = this.ensureChildGroup(childState, widgetConfig.groupTitle || "")
    const item = buildToolTimelineItem({
      toolCallId: payload.tool_call_id || "",
      toolDisplayName: payload.display_name,
      toolIcon: payload.icon || "fa-solid fa-wrench",
      toolName: payload.tool_name,
      widgetConfig: { ...widgetConfig, initialPhrase: widgetConfig.completeMessages?.[0] || "" },
      status: "complete",
    })
    group.querySelector(".shared-chat__tool-timeline")?.appendChild(item)
    this.syncSubagentPlaceholder(item.querySelector(".shared-chat__tool-timeline-branch"), false)

    childState.activeToolCallCount = Math.max(0, childState.activeToolCallCount - 1)
    this.scrollToBottom()
  }

  ensureChildGroup(childState, groupTitle) {
    if (childState.currentToolGroup?.isConnected && childState.currentToolGroup.dataset.groupTitle === groupTitle) {
      this.syncCurrentGroupState(childState.currentToolGroup)
      return childState.currentToolGroup
    }

    const container = this.ensureChildToolCallsContainer(childState)
    const lastChild = container.lastElementChild
    if (lastChild?.classList.contains("shared-chat__tool-group") && lastChild.dataset.groupTitle === groupTitle) {
      childState.currentToolGroup = lastChild
      this.syncCurrentGroupState(lastChild)
      return lastChild
    }

    const group = buildToolGroup({ groupTitle })
    container.appendChild(group)
    childState.currentToolGroup = group
    this.syncCurrentGroupState(group)
    return group
  }

  incrementChildGroupActiveCount(group) {
    const currentCount = Number.parseInt(group.dataset.activeToolCalls || "0", 10)
    group.dataset.activeToolCalls = String(currentCount + 1)
    this.syncCurrentGroupState(group)
  }

  decrementChildGroupActiveCount(group) {
    const remainingCount = Math.max(0, Number.parseInt(group.dataset.activeToolCalls || "0", 10) - 1)
    group.dataset.activeToolCalls = String(remainingCount)
    this.syncCurrentGroupState(group)
  }

  ensureChildPlaceholder(childState, { streaming = false } = {}) {
    const thread = this.ensureChildThread(childState)
    if (!thread || this.childHasVisibleMessages(childState)) return

    let placeholder = thread.querySelector(":scope > .shared-chat__subagent-empty")
    if (!placeholder) {
      placeholder = document.createElement("p")
      placeholder.className = "shared-chat__subagent-empty"
      placeholder.textContent = "No visible transcript yet."
      thread.appendChild(placeholder)
    }

    placeholder.classList.toggle("shared-chat__text-shimmer", streaming)
  }

  renderChildContent(childState) {
    if (!childState.content) return

    const messageElement = this.ensureChildAssistantMessage(childState)
    if (!messageElement) return

    const bubble = ensureAssistantBubble(messageElement)
    const markdown = childState.markdown ||= this.markdown()
    bubble.dataset.markdownRenderContentValue = childState.content
    bubble.innerHTML = markdown.render(childState.content)
    prettifyDownloadLinks(bubble)
    this.scrollToBottom()
  }

  renderChildThinking(childState, { open = childState.phase === "thinking", streaming = false } = {}) {
    if (!childState.thinking) return

    const messageElement = this.ensureChildAssistantMessage(childState)
    if (!messageElement) return

    const body = ensureThinkingBlock(messageElement, { open, streaming })
    updateThinkingBody(body, childState.thinking)
    this.scrollToBottom()
  }

  syncChildThinkingState(childState) {
    if (childState.phase === "thinking") {
      this.renderChildThinking(childState, { open: true, streaming: true })
      return
    }

    if (childState.thinking) {
      this.renderChildThinking(childState, { open: false, streaming: false })
      return
    }

    this.ensureChildPlaceholder(childState, { streaming: childState.status === "streaming" })
  }

  finalizeChildStream(childState) {
    const messageElement = this.childMessageElement(childState)
    this.collapseThinking(messageElement)
    this.finalizeRunningTimelineItems(this.ensureChildThread(childState))

    if (messageElement) {
      delete messageElement.dataset.childStreaming

      if (transientAssistantMessageIsEmpty(messageElement)) {
        messageElement.remove()
      } else {
        messageElement.classList.add("shared-chat__message--stable")
      }
    }

  childState.status = null
    childState.phase = null
    childState.currentToolGroup = null
    childState.currentToolCallsContainer = null
    childState.currentMessageElement = null
    childState.activeToolCallCount = 0
    this.ensureChildPlaceholder(childState, { streaming: false })
    this.syncSubagentPlaceholder(this.findChildBranchElement(childState), false)
    this.scrollToBottom()
  }

  childMessageHasOnlyToolCalls(childState) {
    const messageElement = this.childMessageElement(childState)
    if (!messageElement) return false

    return countToolOutputs(messageElement) > 0 && !this.currentChildMessageHasContent(childState)
  }

  currentChildMessageHasContent(childState) {
    const messageElement = this.childMessageElement(childState)

    return Boolean(
      childState.content.trim() ||
      childState.thinking.trim() ||
      assistantMessageHasVisibleText(messageElement),
    )
  }

  startNewChildMessage(childState) {
    const messageElement = this.childMessageElement(childState)
    if (messageElement) {
      delete messageElement.dataset.childStreaming
      messageElement.classList.add("shared-chat__message--stable")
    }

    if (childState.currentToolGroup?.isConnected) {
      childState.currentToolGroup.classList.remove("streaming")
    }

    childState.content = ""
    childState.thinking = ""
    childState.currentMessageElement = null
    childState.currentToolGroup = null
    childState.currentToolCallsContainer = null
    childState.activeToolCallCount = 0
    childState.markdown = null
  }

  syncSubagentPlaceholder(branch, streaming) {
    branch?.querySelector(".shared-chat__subagent-empty")?.classList.toggle("shared-chat__text-shimmer", streaming)
  }

  currentStreamingMessageHasOnlyToolCalls() {
    const messageElement = this.messagesElement?.querySelector("#streaming-message")
    if (!messageElement) return false

    return countToolOutputs(messageElement) > 0 && !this.currentStreamingMessageHasContent()
  }

  currentStreamingMessageHasContent() {
    const messageElement = this.messagesElement?.querySelector("#streaming-message")

    return Boolean(this.state.content.trim() || this.state.thinking.trim() || assistantMessageHasVisibleText(messageElement))
  }

  currentStreamingMessageHasVisibleOutput() {
    return assistantMessageHasVisibleOutput(this.messagesElement?.querySelector("#streaming-message"))
  }

  shouldRefreshPersistedMessages(previousValue) {
    return Boolean(
      previousValue && (
        this.hadToolOutputs ||
        countToolOutputs(this.messagesElement?.querySelector("#streaming-message")) > 0
      )
    )
  }

  widgetConfigFor(payload) {
    const widgetPayload = payload.widget_payload || {}

    return {
      completeMessages: parseToolWidgetMessages(widgetPayload.tool_widget_complete_messages_value),
      groupTitle: widgetPayload.tool_widget_group_title_value || "",
      initialPhrase: widgetPayload.tool_widget_initial_phrase_value || "",
      runningIntervalMs: Number.parseInt(widgetPayload.tool_widget_running_interval_ms_value || "2200", 10),
      runningMessages: parseToolWidgetMessages(widgetPayload.tool_widget_running_messages_value),
      runningMode: widgetPayload.tool_widget_running_mode_value || "random",
    }
  }

  finalizeStream() {
    const messageElement = this.messagesElement?.querySelector("#streaming-message")
    this.collapseThinking(messageElement)
    this.collapseStreamingBranches()
    this.removeWaitingPlaceholder(messageElement)
    this.finalizeRunningTimelineItems(this.messagesElement)
    this.childStreams.forEach((childState) => {
      if (childState.parentChatId !== this.currentChatId()) return

      this.finalizeChildStream(childState)
    })
    this.messagesElement?.querySelectorAll(".shared-chat__tool-group.streaming")?.forEach((group) => {
      group.classList.remove("streaming")
    })

    if (messageElement) {
      if (transientAssistantMessageIsEmpty(messageElement)) {
        messageElement.remove()
      } else {
        messageElement.removeAttribute("id")
        messageElement.classList.add("shared-chat__message--stable")
      }
    }

    this.state.activeChatId = null
    this.state.content = ""
    this.state.thinking = ""
    this.currentToolGroup = null
    this.currentToolCallsContainer = null
    this.activeToolCallCount = 0

    this.scrollToBottom()
  }

  resetTransientState() {
    this.hadToolOutputs = false
    this.finalizeStream()
  }

  restoreStreamingContent() {
    const restoresParentStream = (this.state.content || this.state.thinking) && this.matches(this.state.activeChatId)
    const restoresChildStream = this.hasRestorableChildStream()

    if (restoresParentStream || restoresChildStream) {
      this.chatController()?.markStreamRestoredFromMemory?.()
    }

    if (this.state.content || this.state.thinking) {
      if (!this.matches(this.state.activeChatId)) return

      this.renderThinking(undefined, {
        open: this.currentStatusPhase() === "thinking",
        streaming: this.currentStatusPhase() === "thinking",
      })
      this.renderContent()
    }

    this.restoreChildStreams()
  }

  hasRestorableChildStream() {
    for (const childState of this.childStreams.values()) {
      if (childState.parentChatId !== this.currentChatId()) continue
      if (childState.content || childState.thinking || childState.status === "streaming") return true
    }

    return false
  }

  restoreChildStreams() {
    if (!this.messagesElement?.isConnected) return

    this.childStreams.forEach((childState) => {
      if (childState.parentChatId !== this.currentChatId()) return

      this.findChildBranchElement(childState)

      if (childState.thinking) {
        this.renderChildThinking(childState, {
          open: childState.phase === "thinking",
          streaming: childState.phase === "thinking",
        })
      }

      if (childState.content) {
        this.renderChildContent(childState)
      } else {
        this.ensureChildPlaceholder(childState, { streaming: childState.status === "streaming" })
      }
    })
  }

  syncThinkingState(phase) {
    const currentPhase = phase === undefined ? this.currentStatusPhase() : phase

    if (currentPhase === "thinking") {
      this.renderThinking(undefined, { open: true, streaming: true })
      return
    }

    if (this.state.thinking) {
      this.renderThinking(undefined, { open: false, streaming: false })
    }
  }

  syncWaitingPlaceholder() {
    if (this.shouldShowWaitingPlaceholder()) {
      this.ensureWaitingPlaceholder()
      return
    }

    this.removeWaitingPlaceholder()
  }

  shouldShowWaitingPlaceholder() {
    const chatId = this.state.activeChatId || this.currentChatId()
    const statusElement = this.panelElement?.querySelector(`#chat-${chatId}-status`)

    return statusElement?.dataset.status === "streaming" &&
      this.currentStatusPhase() !== "thinking" &&
      !this.currentStreamingMessageHasVisibleOutput()
  }

  ensureWaitingPlaceholder() {
    const messageElement = this.ensureStreamingMessage()
    if (!messageElement || messageElement.querySelector(".shared-chat__bubble--placeholder")) return

    messageElement.appendChild(buildWaitingPlaceholder())
    this.scrollToBottom()
  }

  removeWaitingPlaceholder(messageElement = this.messagesElement?.querySelector("#streaming-message")) {
    messageElement?.querySelector(".shared-chat__bubble--placeholder")?.remove()
  }

  finalizeRunningTimelineItems(scope = this.messagesElement) {
    if (!scope?.querySelectorAll) return

    scope.querySelectorAll(".shared-chat__tool-timeline-item.is-running").forEach((item) => {
      this.renderTimelineItemState(item, "complete")
      item.dataset.toolWidgetStatusValue = "complete"
      item.dataset.toolWidgetInitialPhraseValue = ""
      this.syncSubagentPlaceholder(item.querySelector(".shared-chat__tool-timeline-branch"), false)
    })

    scope.querySelectorAll(".shared-chat__tool-group").forEach((group) => {
      group.dataset.activeToolCalls = "0"
      this.syncCurrentGroupState(group)
    })
  }

  collapseThinking(messageElement = this.messagesElement?.querySelector("#streaming-message")) {
    const thinking = messageElement?.querySelector(".shared-chat__thinking")
    if (!thinking) return

    thinking.removeAttribute("open")
    thinking.classList.remove("streaming")
  }

  collapseStreamingBranches() {
    this.messagesElement
      ?.querySelectorAll(".shared-chat__tool-timeline-item.is-running details[open]")
      ?.forEach((element) => element.removeAttribute("open"))
  }

  currentGroupForStream() {
    if (this.currentToolGroup?.isConnected) {
      return this.currentToolGroup
    }

    const messageElement = this.messagesElement?.querySelector("#streaming-message")
    if (messageElement?.isConnected) {
      const messageGroup = messageElement.querySelector(".shared-chat__tool-group")
      if (messageGroup) {
        this.currentToolGroup = messageGroup
        return messageGroup
      }
    }

    const lastMessage = this.messagesElement?.lastElementChild
    if (!lastMessage?.classList.contains("shared-chat__message--assistant")) return null

    const trailingGroup = lastMessage.querySelector(".shared-chat__tool-group")
    if (!trailingGroup) return null

    this.currentToolGroup = trailingGroup
    return trailingGroup
  }

  ensureGroup(groupTitle) {
    const existingGroup = this.appendablePersistedGroup(groupTitle)
    if (existingGroup) {
      this.currentToolGroup = existingGroup
      this.syncCurrentGroupState(existingGroup)
      return existingGroup
    }

    const container = this.ensureToolCallsContainer(this.ensureStreamingMessage())
    const lastChild = container.lastElementChild
    if (lastChild?.classList.contains("shared-chat__tool-group") && lastChild.dataset.groupTitle === groupTitle) {
      this.currentToolGroup = lastChild
      this.syncCurrentGroupState(lastChild)
      return lastChild
    }

    const group = buildToolGroup({ groupTitle })
    container.appendChild(group)
    this.currentToolGroup = group
    this.syncCurrentGroupState(group)
    return group
  }

  appendablePersistedGroup(groupTitle) {
    const messageElement = this.messagesElement?.querySelector("#streaming-message")
    if (messageElement?.isConnected) {
      const currentGroup = messageElement.querySelector(".shared-chat__tool-group")
      if (currentGroup?.dataset.groupTitle === groupTitle) return currentGroup
    }

    const lastMessage = this.messagesElement?.lastElementChild
    if (!lastMessage?.classList.contains("shared-chat__message--assistant")) return null
    if (assistantMessageHasVisibleText(lastMessage)) return null

    const group = lastMessage.querySelector(".shared-chat__tool-group")
    if (!group || group.dataset.groupTitle !== groupTitle) return null

    this.currentToolCallsContainer = lastMessage.querySelector(".shared-chat__tool-calls")
    return group
  }

  incrementGroupActiveCount(group) {
    const currentCount = Number.parseInt(group.dataset.activeToolCalls || "0", 10)
    group.dataset.activeToolCalls = String(currentCount + 1)
    this.syncCurrentGroupState(group)
  }

  decrementGroupActiveCount(group) {
    const remainingCount = Math.max(0, Number.parseInt(group.dataset.activeToolCalls || "0", 10) - 1)
    group.dataset.activeToolCalls = String(remainingCount)
    this.syncCurrentGroupState(group)
  }

  syncCurrentGroupState(group = this.currentGroupForStream()) {
    if (!group?.isConnected) return

    group.classList.toggle("streaming", this.shouldKeepGroupStreaming(group))
  }

  shouldKeepGroupStreaming(group) {
    const activeToolCalls = Number.parseInt(group.dataset.activeToolCalls || "0", 10)
    if (activeToolCalls > 0) return true

    const statusElement = this.panelElement?.querySelector(`#chat-${this.state.activeChatId}-status`)
    if (statusElement?.dataset.status !== "streaming") return false

    const messageElement = this.messagesElement?.querySelector("#streaming-message")
    if (!messageElement?.isConnected) return false

    return messageElement.contains(group) && !this.currentStreamingMessageHasContent()
  }

  renderTimelineItemState(item, status) {
    item.dataset.toolStatus = status
    item.classList.remove("is-running", "is-complete")
    item.classList.add(`is-${status}`)
    if (status !== "running") {
      item.querySelector("details[open]")?.removeAttribute("open")
    }

    const srLabel = item.querySelector(".sr-only")
    if (srLabel) {
      srLabel.textContent = status === "running" ? "In progress" : "Completed"
    }
  }

  currentStatusPhase() {
    const chatId = this.state.activeChatId || this.currentChatId()

    return this.panelElement?.querySelector(`#chat-${chatId}-status`)?.dataset.phase || null
  }

  matches(chatId) {
    if (!chatId) return false
    return this.currentChatId() === String(chatId)
  }

  currentChatId() {
    return this.owner.currentChatId()
  }

  currentLocationMatches(path) {
    const target = this.normalizedLocation(path)
    const current = this.normalizedLocation(this.owner.currentPagePath?.() || window.location.href)

    return target === current
  }

  normalizedLocation(value) {
    try {
      const url = new URL(value, window.location.origin)
      return `${url.pathname}${url.search}`
    } catch {
      return value
    }
  }

  chatController() {
    return this.owner.chatController()
  }

  markdown() {
    const md = getMarkdown()
    overrideFenceRenderer(md)
    return md
  }

  scrollToBottom() {
    this.owner.scrollToBottom()
  }
}
