import { Controller } from "@hotwired/stimulus"

// A simple "+ Add" button that opens a searchable dropdown list.
// Clicking an item populates a hidden form field and submits the form.
//
// Targets:
//   dropdown   – the .inline-dropdown container
//   search     – the search <input> inside the dropdown
//   item       – each clickable <button> row (needs data-add-select-dropdown-label for filtering)
//   form       – the hidden form used for submission
//   valueField – the hidden input whose value is set before submit
//
export default class extends Controller {
  static targets = ["dropdown", "search", "item", "form", "valueField"]

  connect() {
    this._clickOutside = (e) => {
      if (!this.element.contains(e.target)) this.close()
    }
  }

  toggle(event) {
    event.stopPropagation()
    const isOpen = this.dropdownTarget.classList.contains("is-open")
    if (isOpen) {
      this.close()
    } else {
      this.openDropdown()
    }
  }

  openDropdown() {
    this.dropdownTarget.classList.add("is-open")
    document.addEventListener("mousedown", this._clickOutside)
    if (this.hasSearchTarget) {
      this.searchTarget.value = ""
      this.filter()
      requestAnimationFrame(() => this.searchTarget.focus())
    }
  }

  close() {
    this.dropdownTarget.classList.remove("is-open")
    document.removeEventListener("mousedown", this._clickOutside)
  }

  filter() {
    const query = (this.hasSearchTarget ? this.searchTarget.value : "").toLowerCase().trim()
    this.itemTargets.forEach((item) => {
      const label = (item.dataset.addSelectDropdownLabel || item.textContent).toLowerCase()
      item.style.display = label.includes(query) ? "" : "none"
    })
  }

  select({ params: { value } }) {
    this.valueFieldTarget.value = value
    this.formTarget.requestSubmit()
  }

  disconnect() {
    document.removeEventListener("mousedown", this._clickOutside)
  }
}
