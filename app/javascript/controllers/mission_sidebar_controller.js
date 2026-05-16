import { Controller } from "@hotwired/stimulus"

// VS Code-style sidebar with activity bar + resizable content panels
export default class extends Controller {
  static targets = ["content", "panel", "tabButton", "activityBar", "collapseButton"]
  static values = { activeTab: { type: String, default: "" } }

  connect() {
    if (this.activeTabValue) {
      this.contentVisible = true
      this.#activateTab(this.activeTabValue)
    } else {
      this.contentVisible = false
    }

    this.contentTarget.classList.toggle("ms-sidebar-content-collapsed", !this.contentVisible)
    this.#updateCollapseIcon()
  }

  // ── Switch tab — clicking the active tab toggles the content panel ──
  switchTab(event) {
    const tab = event.currentTarget.dataset.sidebarTab
    if (tab === this.activeTabValue && this.contentVisible) {
      this.#collapseContent()
    } else {
      this.activeTabValue = tab
      this.#expandContent()
      this.#activateTab(tab)
    }
  }

  // ── Programmatic tab activation (from custom event) ──
  activateTabFromEvent(event) {
    const tab = event.detail?.tab
    if (!tab) return
    this.activeTabValue = tab
    this.#expandContent()
    this.#activateTab(tab)
  }

  // ── Close panel (X button in panel header) ──
  closePanel() {
    this.#collapseContent()
  }

  // ── Toggle sidebar content panel visibility ──
  toggleContent() {
    if (this.contentVisible) {
      this.#collapseContent()
    } else {
      const tab = this.#resolvedTab()
      this.#expandContent()
      this.activeTabValue = tab
      this.#activateTab(tab)
    }
  }

  // ── Resize the sidebar content panel ──
  startResize(event) {
    event.preventDefault()
    const content = this.contentTarget
    const startX = event.clientX
    const startWidth = content.offsetWidth
    const resizer = event.currentTarget
    resizer.classList.add("active")

    const onMouseMove = (e) => {
      const dx = startX - e.clientX
      const newWidth = Math.min(Math.max(startWidth + dx, 280), 600)
      content.style.width = `${newWidth}px`
    }

    const onMouseUp = () => {
      resizer.classList.remove("active")
      document.removeEventListener("mousemove", onMouseMove)
      document.removeEventListener("mouseup", onMouseUp)
    }

    document.addEventListener("mousemove", onMouseMove)
    document.addEventListener("mouseup", onMouseUp)
  }

  // ── Private ──

  #activateTab(tab) {
    // Update tab button active states
    this.tabButtonTargets.forEach((btn) => {
      btn.classList.toggle("active", btn.dataset.sidebarTab === tab)
    })
    // Show the matching panel, hide others
    this.panelTargets.forEach((panel) => {
      const isMatch = panel.dataset.sidebarTab === tab
      panel.classList.toggle("hidden", !isMatch)
    })

    // Update singleton palette items when switching to components tab
    if (tab === "components") {
      this.#updateSingletonPaletteItems()
    }
  }

  #collapseContent() {
    this.contentVisible = false
    this.contentTarget.classList.add("ms-sidebar-content-collapsed")
    // Remove active from all tab buttons
    this.tabButtonTargets.forEach((btn) => btn.classList.remove("active"))
    this.#updateCollapseIcon()
  }

  #expandContent() {
    this.contentVisible = true
    this.contentTarget.classList.remove("ms-sidebar-content-collapsed")
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
    if (this.activeTabValue) return this.activeTabValue
    return this.tabButtonTargets[0]?.dataset.sidebarTab || ""
  }

  #updateSingletonPaletteItems() {
    const canvas = document.querySelector("[data-mission-target='canvas']")
    if (!canvas) return
    const flowDataInput = document.getElementById(canvas.dataset.flowDataInputId)
    if (!flowDataInput) return
    const flowData = flowDataInput.value || "{}"
    let existingTypes = []
    try { existingTypes = (JSON.parse(flowData).nodes || []).map((n) => n.type) } catch { /* ignore */ }
    this.element.querySelectorAll(".ms-palette-item[data-singleton]").forEach((item) => {
      const type = item.dataset.nodeType
      const exists = existingTypes.includes(type)
      item.classList.toggle("ms-palette-item-disabled", exists)
      item.setAttribute("draggable", exists ? "false" : "true")
    })
  }
}
