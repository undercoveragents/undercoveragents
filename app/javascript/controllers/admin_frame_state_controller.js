import { Controller } from "@hotwired/stimulus"

const SIDEBAR_SLOT_SELECTORS = {
  panels: "[data-admin-sidebar-slot='panels']",
  "tabs-before-chat": "[data-admin-sidebar-slot='tabs-before-chat']",
  "tabs-after-chat": "[data-admin-sidebar-slot='tabs-after-chat']",
}

const SIDEBAR_SEPARATOR_SELECTOR = "[data-admin-sidebar-slot-separator='page-tabs']"
const APPLIED_ATTRS_DATA_KEY = "adminFrameStateAppliedAttrs"

export default class extends Controller {
  connect() {
    this.sync()
  }

  sync() {
    const state = this.element.querySelector("[data-admin-frame-state]")

    this.#syncMainContent(state)
    this.#syncSidebar(state)
  }

  #syncMainContent(state) {
    const mainContent = this.element.closest(".main-content")
    if (!mainContent) return

    const appliedAttrs = this.#parseJson(mainContent.dataset[APPLIED_ATTRS_DATA_KEY], [])
    appliedAttrs.forEach((attr) => mainContent.removeAttribute(attr))

    const nextData = this.#parseJson(state?.dataset.adminFrameStateMainContentData, {})
    const nextAttrs = []

    Object.entries(nextData).forEach(([key, value]) => {
      const attr = this.#dataAttributeName(key)
      nextAttrs.push(attr)

      if (value === null || value === undefined || value === "") {
        mainContent.removeAttribute(attr)
      } else {
        mainContent.setAttribute(attr, String(value))
      }
    })

    if (nextAttrs.length > 0) {
      mainContent.dataset[APPLIED_ATTRS_DATA_KEY] = JSON.stringify(nextAttrs)
    } else {
      delete mainContent.dataset[APPLIED_ATTRS_DATA_KEY]
    }
  }

  #syncSidebar(state) {
    const sidebar = document.querySelector(".admin-panel-sidebar")
    if (!sidebar) return

    Object.entries(SIDEBAR_SLOT_SELECTORS).forEach(([slotName, selector]) => {
      const slot = sidebar.querySelector(selector)
      if (!slot) return

      const template = state?.querySelector(`template[data-admin-frame-state-slot='${slotName}']`)
      slot.innerHTML = template?.innerHTML || ""
    })

    const beforeChatSlot = sidebar.querySelector(SIDEBAR_SLOT_SELECTORS["tabs-before-chat"])
    const afterChatSlot = sidebar.querySelector(SIDEBAR_SLOT_SELECTORS["tabs-after-chat"])
    const beforeChatSeparator = sidebar.querySelector(SIDEBAR_SEPARATOR_SELECTOR)
    if (beforeChatSeparator) {
      beforeChatSeparator.classList.toggle(
        "hidden",
        !beforeChatSlot?.innerHTML.trim() && !afterChatSlot?.innerHTML.trim(),
      )
    }

    const defaultTab = state?.dataset.adminFrameStateDefaultSidebarTab?.trim() || ""

    requestAnimationFrame(() => {
      document.dispatchEvent(new CustomEvent("ms:sidebar-frame-state", {
        detail: { defaultTab },
      }))
    })
  }

  #dataAttributeName(key) {
    const normalizedKey = String(key)
      .replace(/([a-z\d])([A-Z])/g, "$1-$2")
      .replace(/_/g, "-")
      .toLowerCase()

    return `data-${normalizedKey}`
  }

  #parseJson(value, fallback) {
    if (!value) return fallback

    try {
      return JSON.parse(value)
    } catch {
      return fallback
    }
  }
}
