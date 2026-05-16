import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button", "dropdown", "icon", "selectedIcon", "selectedName"]

  toggle(event) {
    event?.stopPropagation()
    this.setOpen(!this.dropdownTarget.classList.contains("is-open"))
  }

  select(event) {
    this.updateSelection(event.params)
    this.closeAfterSelection()
  }

  close(event) {
    if (!this.element.contains(event.target)) {
      this.closeDropdown()
    }
  }

  closeDropdown() {
    this.setOpen(false)
  }

  closeAfterSelection() {
    clearTimeout(this.selectionCloseTimeout)
    this.selectionCloseTimeout = setTimeout(() => this.closeDropdown(), 150)
  }

  connect() {
    this.clickOutside = this.close.bind(this)
    document.addEventListener("click", this.clickOutside)
  }

  disconnect() {
    clearTimeout(this.selectionCloseTimeout)
    document.removeEventListener("click", this.clickOutside)
  }

  setOpen(open) {
    this.dropdownTarget.classList.toggle("is-open", open)
    this.iconTarget.classList.toggle("fa-chevron-up", open)

    if (this.hasButtonTarget) {
      this.buttonTarget.setAttribute("aria-expanded", String(open))
    }
  }

  updateSelection({ id = "", name, icon, checkClass }) {
    if (name && this.hasSelectedNameTarget) {
      this.selectedNameTarget.textContent = name
    }

    if (icon && this.hasSelectedIconTarget) {
      const baseClass = this.selectedIconTarget.dataset.operationSwitcherBaseClass || ""
      this.selectedIconTarget.className = [baseClass, icon].filter(Boolean).join(" ")
    }

    this.syncActiveItems(String(id), checkClass)
  }

  syncActiveItems(selectedId, checkClass) {
    this.element.querySelectorAll("[data-operation-switcher-id-param]").forEach((item) => {
      const active = String(item.dataset.operationSwitcherIdParam || "") === selectedId
      item.classList.toggle("active", active)
      item.querySelector(".sidebar-operation-check, .dash-op-check")?.remove()

      if (active) {
        const check = document.createElement("i")
        check.className = checkClass || "fa-solid fa-check"
        item.appendChild(check)
      }
    })
  }
}
