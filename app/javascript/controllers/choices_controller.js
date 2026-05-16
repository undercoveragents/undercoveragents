import { Controller } from "@hotwired/stimulus"
import Choices from "choices.js"

// Generic Stimulus wrapper for Choices.js.
// Attach `data-controller="choices"` to a wrapper element that contains a
// <select> with `data-choices-target="select"`.
//
// Configuration values (all optional):
//   search        – enable search box (default: true)
//   searchPlaceholder – placeholder text for the search input
//   placeholder   – placeholder text when nothing is selected
//   removeItems   – allow removing selected items (default: false)
//   shouldSort    – sort choices alphabetically (default: false)
//
// Example:
//   .form-group{ data: { controller: "choices", choices_search_value: "false" } }
//     = f.select :field, options, {}, class: "form-input form-select", data: { choices_target: "select" }
//
export default class extends Controller {
  static targets = ["select"]
  static values = {
    search: { type: Boolean, default: true },
    searchPlaceholder: { type: String, default: "Search…" },
    placeholder: { type: String, default: "Select…" },
    removeItems: { type: Boolean, default: false },
    shouldSort: { type: Boolean, default: false },
  }

  connect() {
    this.choices = new Choices(this.selectTarget, {
      searchEnabled: this.searchValue,
      placeholder: true,
      searchPlaceholderValue: this.searchPlaceholderValue,
      placeholderValue: this.placeholderValue,
      removeItems: this.removeItemsValue,
      removeItemButton: this.removeItemsValue,
      shouldSort: this.shouldSortValue,
      itemSelectText: "",
      noResultsText: "No results found",
      noChoicesText: "No choices available",
      allowHTML: false,
    })
  }

  disconnect() {
    if (this.choices) {
      this.choices.destroy()
      this.choices = null
    }
  }
}
