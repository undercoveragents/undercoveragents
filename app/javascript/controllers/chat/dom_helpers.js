import { escapeHtml } from "utils/html"

export function fileIcon(file) {
  const type = file.type || ""
  if (type.startsWith("image/")) return "fa-file-image"
  if (type === "application/pdf") return "fa-file-pdf"
  if (type.startsWith("audio/")) return "fa-file-audio"
  if (type.startsWith("video/")) return "fa-file-video"
  if (type.startsWith("text/")) return "fa-file-lines"
  return "fa-file"
}

export function truncateFilename(name, maxLength) {
  if (name.length <= maxLength) return name

  const ext = name.lastIndexOf(".")
  if (ext > 0) {
    const extension = name.slice(ext)
    const base = name.slice(0, ext)
    const available = maxLength - extension.length - 1

    if (available > 3) {
      return base.slice(0, available) + "…" + extension
    }
  }

  return name.slice(0, maxLength - 1) + "…"
}

export function parseToolWidgetMessages(value) {
  if (!value) return []

  try {
    const parsed = JSON.parse(value)
    return Array.isArray(parsed) ? parsed : []
  } catch {
    return []
  }
}

export function countToolOutputs(messageEl) {
  return messageEl?.querySelectorAll(".shared-chat__tool-timeline-item").length || 0
}

export function subagentToolName(toolName) {
  return /^ask_agent_/i.test(toolName || "")
}

export function assistantMessageHasVisibleText(messageEl) {
  if (!messageEl?.matches(".shared-chat__message--assistant")) return false

  const contentEl = messageEl.querySelector(":scope > .shared-chat__assistant-panel > .shared-chat__assistant-content")
  const content = contentEl?.dataset?.markdownRenderContentValue?.trim() || contentEl?.textContent?.trim()
  const thinking = messageEl
    .querySelector(":scope > .shared-chat__assistant-panel > .shared-chat__thinking > .shared-chat__tree-children > .shared-chat__thinking-body")
    ?.textContent?.trim()
  return Boolean(content || thinking)
}

export function assistantMessageHasVisibleOutput(messageEl) {
  return assistantMessageHasVisibleText(messageEl) || countToolOutputs(messageEl) > 0
}

export function transientAssistantMessageIsEmpty(messageEl) {
  return !assistantMessageHasVisibleText(messageEl) && countToolOutputs(messageEl) === 0
}

export function ensureAssistantPanel(messageEl) {
  let panel = messageEl.querySelector(":scope > .shared-chat__assistant-panel")
  if (!panel) {
    panel = document.createElement("div")
    panel.className = "shared-chat__assistant-panel"
    messageEl.appendChild(panel)
  }

  return panel
}

export function ensureThinkingBlock(messageEl, { open = true, streaming = false } = {}) {
  const panel = ensureAssistantPanel(messageEl)
  let block = panel.querySelector(":scope > .shared-chat__thinking")
  if (!block) {
    block = document.createElement("details")
    block.className = "shared-chat__thinking"
    block.innerHTML = `
      <summary class="shared-chat__tree-summary shared-chat__tree-summary--thinking">
        <div class="shared-chat__tool-call-row shared-chat__tool-call-row--section">
          <div class="shared-chat__tool-call-main">
            <span class="shared-chat__tool-call-icon-wrap">
              <i class="shared-chat__tool-call-icon fa-solid fa-brain fa-fw" aria-hidden="true"></i>
            </span>
            <span class="shared-chat__tool-call-copy">
              <span class="shared-chat__tool-call-label shared-chat__section-label">
                <span class="shared-chat__tool-call-name shared-chat__tool-call-name--section">Thinking</span>
                <i class="fa-solid fa-chevron-right fa-fw shared-chat__tree-chevron" aria-hidden="true"></i>
              </span>
            </span>
          </div>
        </div>
      </summary>
      <div class="shared-chat__tree-children shared-chat__thinking-body"></div>
    `
    panel.prepend(block)
  }

  if (open) {
    block.setAttribute("open", "open")
  } else {
    block.removeAttribute("open")
  }

  block.classList.toggle("streaming", streaming)

  return block.querySelector(".shared-chat__thinking-body")
}

export function updateThinkingBody(body, content) {
  if (!body) return

  body.textContent = content
  body.scrollTop = body.scrollHeight
}

function applyToolWidgetDataset(element, widgetConfig = {}, status) {
  element.dataset.controller = "tool-widget"
  element.dataset.toolWidgetStatusValue = status
  element.dataset.toolWidgetRunningMessagesValue = JSON.stringify(widgetConfig.runningMessages || [])
  element.dataset.toolWidgetRunningModeValue = widgetConfig.runningMode || "random"
  element.dataset.toolWidgetRunningIntervalMsValue = String(widgetConfig.runningIntervalMs || 2200)
  element.dataset.toolWidgetCompleteMessagesValue = JSON.stringify(widgetConfig.completeMessages || [])
  element.dataset.toolWidgetGroupTitleValue = widgetConfig.groupTitle || ""
  element.dataset.toolWidgetInitialPhraseValue = widgetConfig.initialPhrase || ""
}

const SUBAGENT_BRANCH_ICON_CLASS = "fa-solid fa-user-secret"

function buildToolCallRowMarkup({
  label,
  iconClass,
  phrase = null,
  durationLabel = null,
  collapsible = false,
  section = false,
}) {
  const rowClass = ["shared-chat__tool-call-row", section ? "shared-chat__tool-call-row--section" : null]
    .filter(Boolean)
    .join(" ")
  const labelClass = ["shared-chat__tool-call-label", section ? "shared-chat__section-label" : null]
    .filter(Boolean)
    .join(" ")
  const nameClass = ["shared-chat__tool-call-name", section ? "shared-chat__tool-call-name--section" : null]
    .filter(Boolean)
    .join(" ")
  const metaMarkup = durationLabel
    ? `
      <div class="shared-chat__tool-call-meta">
        ${durationLabel ? `<span class="shared-chat__tool-call-duration">${escapeHtml(durationLabel)}</span>` : ""}
      </div>
    `
    : ""

  return `
    <div class="${rowClass}">
      <div class="shared-chat__tool-call-main">
        <span class="shared-chat__tool-call-icon-wrap">
          <i class="shared-chat__tool-call-icon fa-fw ${escapeHtml(iconClass)}" aria-hidden="true"></i>
        </span>
        <span class="shared-chat__tool-call-copy">
          <span class="${labelClass}">
            <span class="${nameClass}">${escapeHtml(label)}</span>
            ${collapsible ? '<i class="fa-solid fa-chevron-right fa-fw shared-chat__tree-chevron" aria-hidden="true"></i>' : ""}
          </span>
          ${phrase ? `<span class="shared-chat__tool-call-phrase" data-tool-widget-target="phrase">${escapeHtml(phrase)}</span>` : ""}
        </span>
      </div>
      ${metaMarkup}
    </div>
  `
}

function buildSubagentPlaceholderMarkup({ streaming = false } = {}) {
  const placeholderClass = ["shared-chat__subagent-empty", streaming ? "shared-chat__text-shimmer" : null]
    .filter(Boolean)
    .join(" ")

  return `
    <div class="shared-chat__subagent-chat">
      <div class="shared-chat__subagent-thread">
        <p class="${placeholderClass}">No visible transcript yet.</p>
      </div>
    </div>
  `
}

function buildSubagentBranchInnerMarkup({ toolDisplayName, status, summaryClass }) {
  return `
    <summary class="${summaryClass}">
      ${buildToolCallRowMarkup({
        label: toolDisplayName,
        iconClass: SUBAGENT_BRANCH_ICON_CLASS,
        status,
        collapsible: true,
        showState: false,
        section: true,
      })}
      <span class="sr-only">${status === "running" ? "In progress" : "Completed"}</span>
    </summary>
    <div class="shared-chat__tree-children">
      ${buildSubagentPlaceholderMarkup({ streaming: status === "running" })}
    </div>
  `
}

export function buildToolTimelineItem({
  toolCallId,
  toolDisplayName,
  toolIcon,
  toolName,
  widgetConfig = {},
  status = "running",
}) {
  const item = document.createElement("li")
  const isBranch = subagentToolName(toolName)
  item.className = [
    "shared-chat__tool-timeline-item",
    `is-${status}`,
    isBranch ? "shared-chat__tool-timeline-item--branch" : null,
  ].filter(Boolean).join(" ")
  item.dataset.toolCallId = toolCallId
  item.dataset.toolStatus = status
  if (toolName) item.dataset.toolName = toolName
  applyToolWidgetDataset(item, widgetConfig, status)

  if (isBranch) {
    item.innerHTML = `
      <details class="shared-chat__tool-timeline-branch" data-tool-name="${escapeHtml(toolName || "")}" ${status === "running" ? "open" : ""}>
        ${buildSubagentBranchInnerMarkup({
          toolDisplayName,
          status,
          summaryClass: "shared-chat__tree-summary shared-chat__tree-summary--timeline",
        })}
      </details>
    `
    return item
  }

  item.innerHTML = `
    ${buildToolCallRowMarkup({
      label: toolDisplayName,
      iconClass: toolIcon || "fa-solid fa-wrench",
      phrase: widgetConfig.initialPhrase || "",
    })}
    <span class="sr-only">${status === "running" ? "In progress" : "Completed"}</span>
  `
  return item
}

export function promoteTimelineItemToSubagentBranch(item, { toolDisplayName, toolName, status } = {}) {
  if (!item) return null

  const resolvedStatus = status ||
    item.dataset.toolStatus ||
    (item.classList.contains("is-running") ? "running" : "complete")
  const resolvedToolName = toolName || item.dataset.toolName || ""
  const resolvedDisplayName = toolDisplayName ||
    item.querySelector(".shared-chat__tool-call-name")?.textContent?.trim() ||
    "Subagent"

  item.classList.add("shared-chat__tool-timeline-item--branch")
  item.classList.remove("is-running", "is-complete")
  item.classList.add(`is-${resolvedStatus}`)
  item.dataset.toolStatus = resolvedStatus
  if (resolvedToolName) item.dataset.toolName = resolvedToolName

  item.innerHTML = `
    <details class="shared-chat__tool-timeline-branch" data-tool-name="${escapeHtml(resolvedToolName)}" ${resolvedStatus === "running" ? "open" : ""}>
      ${buildSubagentBranchInnerMarkup({
        toolDisplayName: resolvedDisplayName,
        status: resolvedStatus,
        summaryClass: "shared-chat__tree-summary shared-chat__tree-summary--timeline",
      })}
    </details>
  `

  return item.querySelector(".shared-chat__tool-timeline-branch")
}

export function buildToolGroup({ groupTitle }) {
  const group = document.createElement("div")
  group.className = "shared-chat__tool-group streaming"
  group.dataset.groupTitle = groupTitle
  group.dataset.activeToolCalls = "0"
  group.innerHTML = `
    <ol class="shared-chat__tool-timeline"></ol>
  `
  return group
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
}

function referenceTitle(reference) {
  return [
    reference.type,
    reference.label,
    reference.id ? `id: ${reference.id}` : null,
    reference.slug ? `slug: ${reference.slug}` : null,
  ].filter(Boolean).join(" · ")
}

function inlineReferences(content, references) {
  return references
    .filter((reference) => reference.mention && content.includes(reference.mention))
    .sort((left, right) => right.mention.length - left.mention.length)
}

function contextReferences(content, references) {
  return references.filter((reference) => !reference.mention || !content.includes(reference.mention))
}

function referenceBadgeText(reference) {
  return reference.label || reference.display_mention || reference.mention || reference.display_tag || "Reference"
}

function referenceBadgeMarkup(reference, { context = false } = {}) {
  const classes = ["shared-chat__inline-reference", context ? "shared-chat__inline-reference--context" : null]
    .filter(Boolean)
    .join(" ")
  return `<code class="${classes}" title="${escapeHtml(referenceTitle(reference))}">${escapeHtml(referenceBadgeText(reference))}</code>`
}

function renderUserContent(content, references) {
  const inline = inlineReferences(content, references)
  if (inline.length === 0) return escapeHtml(content)

  const byMention = new Map(inline.map((reference) => [reference.mention, reference]))
  const pattern = new RegExp(`(${Array.from(byMention.keys()).map(escapeRegExp).join("|")})`, "g")
  return content.split(pattern).map((part) => {
    const reference = byMention.get(part)
    return reference ? referenceBadgeMarkup(reference) : escapeHtml(part)
  }).join("")
}

export function buildUserMessage({ content, files = [], optimisticId, references = [] }) {
  const messageEl = document.createElement("div")
  messageEl.className = "shared-chat__message shared-chat__message--user"

  if (optimisticId) {
    messageEl.dataset.optimisticId = optimisticId
  }

  let html = '<div class="shared-chat__bubble shared-chat__bubble--user">'

  if (files.length > 0) {
    html += '<div class="shared-chat__attachments">'
    files.forEach((file) => {
      if (file.type.startsWith("image/")) {
        html += `<div class="shared-chat__attachment-thumb">
          <img src="${URL.createObjectURL(file)}" class="shared-chat__attachment-image" alt="${escapeHtml(file.name)}">
        </div>`
      } else {
        html += `<div class="shared-chat__attachment-file">
          <i class="fa-solid ${fileIcon(file)}"></i>
          <span class="shared-chat__attachment-name">${escapeHtml(truncateFilename(file.name, 30))}</span>
        </div>`
      }
    })
    html += "</div>"
  }

  const context = contextReferences(content, references)
  if (context.length > 0) {
    html += '<div class="shared-chat__message-references">'
    context.forEach((reference) => {
      html += `<div class="shared-chat__message-reference">
        ${referenceBadgeMarkup(reference, { context: true })}
      </div>`
    })
    html += "</div>"
  }

  if (content) {
    html += `<div class="shared-chat__message-content">${renderUserContent(content, references)}</div>`
  }

  html += "</div>"
  messageEl.innerHTML = html
  return messageEl
}

export function ensureAssistantBubble(messageEl) {
  const panel = ensureAssistantPanel(messageEl)

  let content = panel.querySelector(":scope > .shared-chat__assistant-content")
  if (!content) {
    content = document.createElement("div")
    content.className = "shared-chat__assistant-content shared-chat__message-content markdown-body"
    panel.appendChild(content)
  }

  const markdownValue = content.dataset.markdownRenderContentValue || content.textContent || ""
  content.classList.add("markdown-body")
  content.dataset.markdownRenderContentValue = markdownValue
  return content
}

export function buildWaitingPlaceholder() {
  const placeholder = document.createElement("div")
  placeholder.className = "shared-chat__bubble shared-chat__bubble--placeholder"
  placeholder.setAttribute("aria-label", "Waiting for response")
  placeholder.innerHTML = `
    <span class="shared-chat__placeholder-copy shared-chat__text-shimmer">Waiting for response</span>
  `
  return placeholder
}
