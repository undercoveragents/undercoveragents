import { Controller } from "@hotwired/stimulus"

// Shared right sidebar with activity bar + resizable content panels.
export default class extends Controller {
  static targets = ["content", "panel", "tabButton", "activityBar", "collapseButton"]
  static values = {
    activeTab: { type: String, default: "" },
    storageKey: { type: String, default: "admin-panel-sidebar" },
  }

  connect() {
    const storedState = this.#loadState()
    const restoredTab = this.#tabExists(storedState.activeTab) ? storedState.activeTab : ""
    const initialTab = this.#tabExists(this.activeTabValue) ? this.activeTabValue : ""
    const resolvedTab = restoredTab || initialTab
    this.pendingAssistantFocus = false
    this.savedWidth = this.#normalizedWidth(storedState.width)
    this.#watchContainerWidth()

    if (storedState.contentVisible && resolvedTab) {
      this.contentVisible = true
      this.activeTabValue = resolvedTab
      this.#activateTab(resolvedTab)
    } else if (initialTab) {
      this.contentVisible = true
      this.#activateTab(initialTab)
    } else {
      this.contentVisible = false
      this.activeTabValue = resolvedTab
      this.#hidePanels()
    }

    this.contentTarget.classList.toggle("ms-sidebar-content-collapsed", !this.contentVisible)
    this.#syncContentWidth()
    this.#updateCollapseIcon()
  }

  disconnect() {
    this.resizeObserver?.disconnect()
    this.resizeObserver = null
    this.#saveState()
  }

  switchTab(event) {
    const tab = event.currentTarget.dataset.sidebarTab
    if (!tab) return

    if (tab === this.activeTabValue && this.contentVisible) {
      this.#collapseContent()
    } else {
      this.activeTabValue = tab
      this.#expandContent()
      this.#activateTab(tab, { focusAssistant: true })
    }

    this.#saveState()
  }

  activateTabFromEvent(event) {
    const tab = event.detail?.tab
    if (!this.#tabExists(tab)) return

    this.activeTabValue = tab
    this.#expandContent()
    this.#activateTab(tab, { focusAssistant: true })
    this.#saveState()
  }

  handleFrameLoad(event) {
    if (event.target?.id !== "admin-agent-alpha-frame" || !this.pendingAssistantFocus) return

    this.#requestAssistantFocus()
  }

  syncFrameState(event) {
    const defaultTab = event.detail?.defaultTab?.trim() || ""
    const currentTab = this.#tabExists(this.activeTabValue) ? this.activeTabValue : ""
    const fallbackTab = this.#tabExists(defaultTab) ? defaultTab : this.#resolvedTab()
    const resolvedTab = currentTab || fallbackTab

    this.activeTabValue = resolvedTab

    if (this.contentVisible && resolvedTab) {
      this.#expandContent()
      this.#activateTab(resolvedTab)
    } else {
      this.#collapseContent()
    }

    this.#saveState()
  }

  closePanel() {
    this.#collapseContent()
    this.#saveState()
  }

  toggleContent() {
    if (this.contentVisible) {
      this.#collapseContent()
    } else {
      const tab = this.#resolvedTab()
      if (!tab) return

      this.activeTabValue = tab
      this.#expandContent()
      this.#activateTab(tab, { focusAssistant: true })
    }

    this.#saveState()
  }

  startResize(event) {
    event.preventDefault()

    const content = this.contentTarget
    const startX = event.clientX
    const startWidth = content.offsetWidth
    const resizer = event.currentTarget
    resizer.classList.add("active")

    const onMouseMove = (moveEvent) => {
      const deltaX = startX - moveEvent.clientX
      const newWidth = this.#clampContentWidth(startWidth + deltaX)
      this.savedWidth = newWidth
      this.#applyContentWidth(newWidth)
    }

    const onMouseUp = () => {
      resizer.classList.remove("active")
      document.removeEventListener("mousemove", onMouseMove)
      document.removeEventListener("mouseup", onMouseUp)
      this.#saveState()
    }

    document.addEventListener("mousemove", onMouseMove)
    document.addEventListener("mouseup", onMouseUp)
  }

  #activateTab(tab, { focusAssistant = false } = {}) {
    this.tabButtonTargets.forEach((button) => {
      button.classList.toggle("active", button.dataset.sidebarTab === tab)
    })

    this.panelTargets.forEach((panel) => {
      panel.classList.toggle("hidden", panel.dataset.sidebarTab !== tab)
    })

    if (tab !== "assistant") {
      this.pendingAssistantFocus = false
    }

    if (tab === "components") {
      this.#updateSingletonPaletteItems()
    }

    if (focusAssistant && tab === "assistant" && this.contentVisible) {
      this.#requestAssistantFocus()
    }
  }

  #hidePanels() {
    this.panelTargets.forEach((panel) => panel.classList.add("hidden"))
    this.tabButtonTargets.forEach((button) => button.classList.remove("active"))
  }

  #collapseContent() {
    this.contentVisible = false
    this.pendingAssistantFocus = false
    this.contentTarget.classList.add("ms-sidebar-content-collapsed")
    this.#syncContentWidth()
    this.#hidePanels()
    this.#updateCollapseIcon()
  }

  #expandContent() {
    this.contentVisible = true
    this.contentTarget.classList.remove("ms-sidebar-content-collapsed")
    this.#syncContentWidth()
    this.#updateCollapseIcon()
  }

  #updateCollapseIcon() {
    if (!this.hasCollapseButtonTarget) return

    const icon = this.collapseButtonTarget.querySelector("i")
    if (!icon) return

    icon.classList.toggle("fa-angles-right", this.contentVisible)
    icon.classList.toggle("fa-angles-left", !this.contentVisible)
  }

  #resolvedTab() {
    if (this.#tabExists(this.activeTabValue)) {
      return this.activeTabValue
    }

    return this.tabButtonTargets[0]?.dataset.sidebarTab || ""
  }

  #tabExists(tab) {
    if (!tab) return false

    return this.tabButtonTargets.some((button) => button.dataset.sidebarTab === tab)
  }

  #loadState() {
    try {
      return JSON.parse(window.localStorage.getItem(this.storageKeyValue) || "{}")
    } catch {
      return {}
    }
  }

  #saveState() {
    try {
      window.localStorage.setItem(this.storageKeyValue, JSON.stringify({
        activeTab: this.activeTabValue,
        contentVisible: this.contentVisible,
        width: this.#persistedWidth(),
      }))
    } catch {
      // Ignore storage failures in private browsing or restricted contexts.
    }
  }

  #persistedWidth() {
    return this.savedWidth
  }

  #syncContentWidth() {
    if (!this.hasContentTarget) return

    if (!this.contentVisible) {
      this.contentTarget.style.removeProperty("width")
      this.contentTarget.style.removeProperty("min-width")
      this.contentTarget.style.removeProperty("max-width")
      return
    }

    this.#applyContentWidth(this.savedWidth || this.#defaultContentWidth())
  }

  #normalizedWidth(width) {
    const parsedWidth = Number.parseInt(width, 10)
    return Number.isFinite(parsedWidth) && parsedWidth > 0 ? parsedWidth : null
  }

  #watchContainerWidth() {
    const container = this.element.parentElement
    if (!container || typeof ResizeObserver === "undefined") return

    this.resizeObserver = new ResizeObserver(() => {
      this.#syncContentWidth()
    })

    this.resizeObserver.observe(container)
  }

  #defaultContentWidth() {
    return 320
  }

  #maxContentWidth() {
    const containerWidth = this.element.parentElement?.clientWidth

    if (!Number.isFinite(containerWidth) || containerWidth <= 0) {
      return this.savedWidth || this.#defaultContentWidth()
    }

    return Math.max(0, Math.floor(containerWidth / 2))
  }

  #clampContentWidth(width) {
    const maxWidth = this.#maxContentWidth()
    const minWidth = Math.min(280, maxWidth)
    const normalizedWidth = this.#normalizedWidth(width) || this.#defaultContentWidth()

    return Math.min(Math.max(normalizedWidth, minWidth), maxWidth)
  }

  #applyContentWidth(width) {
    const maxWidth = this.#maxContentWidth()

    this.contentTarget.style.minWidth = "0px"
    this.contentTarget.style.maxWidth = `${maxWidth}px`
    this.contentTarget.style.width = `${this.#clampContentWidth(width)}px`
  }

  #updateSingletonPaletteItems() {
    const canvas = document.querySelector("[data-mission-target='canvas']")
    if (!canvas) return

    const flowDataInput = document.getElementById(canvas.dataset.flowDataInputId)
    if (!flowDataInput) return

    let existingTypes = []
    try {
      existingTypes = (JSON.parse(flowDataInput.value || "{}").nodes || []).map((node) => node.type)
    } catch {
      existingTypes = []
    }

    this.element.querySelectorAll(".ms-palette-item[data-singleton]").forEach((item) => {
      const type = item.dataset.nodeType
      const exists = existingTypes.includes(type)
      item.classList.toggle("ms-palette-item-disabled", exists)
      item.setAttribute("draggable", exists ? "false" : "true")
    })
  }

  #requestAssistantFocus() {
    if (!this.contentVisible || this.activeTabValue !== "assistant") return

    this.pendingAssistantFocus = true

    requestAnimationFrame(() => {
      if (this.#focusAssistantInputNow()) {
        this.pendingAssistantFocus = false
      }
    })
  }

  #focusAssistantInputNow() {
    const assistantPanel = this.panelTargets.find((panel) => panel.dataset.sidebarTab === "assistant")
    if (!assistantPanel || assistantPanel.classList.contains("hidden")) return false

    const chatElement = assistantPanel.querySelector(".shared-chat")
    if (!chatElement) return false

    const controller = window.Stimulus?.getControllerForElementAndIdentifier(chatElement, "chat")
    if (controller?.focusInput?.({ detail: { force: true } })) {
      return true
    }

    const textarea = chatElement.querySelector('[data-chat-target="input"]')
    if (!(textarea instanceof HTMLTextAreaElement) || textarea.readOnly || textarea.disabled) {
      return false
    }

    textarea.focus({ preventScroll: true })
    const caretPosition = textarea.value.length
    textarea.setSelectionRange(caretPosition, caretPosition)

    return true
  }
}
