import { Controller } from "@hotwired/stimulus"
import { escapeHtml } from "utils/html"
import Choices from "choices.js"

// A searchable dropdown for selecting an LLM model, powered by Choices.js.
// Renders each option with the model name, model_id, and provider badge.
// Reads `data-custom-properties` JSON from <option> tags for provider info.
export default class extends Controller {
  static targets = ["select"]

  connect() {
    // Parse custom properties from option data attributes before Choices takes over
    const optionData = {}
    this.selectTarget.querySelectorAll("option").forEach((opt) => {
      if (opt.value && opt.dataset.customProperties) {
        try {
          optionData[opt.value] = JSON.parse(opt.dataset.customProperties)
        } catch (_e) { /* ignore parse errors */ }
      }
    })
    this._optionData = optionData

    this.choices = new Choices(this.selectTarget, {
      searchEnabled: true,
      placeholder: true,
      searchPlaceholderValue: "Search models…",
      placeholderValue: "Select a model…",
      searchFields: ["label", "value"],
      itemSelectText: "",
      noResultsText: "No models found",
      noChoicesText: "No models available",
      shouldSort: false,
      allowHTML: true,
      searchResultLimit: 100,
      callbackOnCreateTemplates: (template) => ({
        choice: ({ classNames }, data) => {
          // Hide blank/placeholder option — shown natively as the closed-state placeholder
          if (!data.value) {
            return template(`<div style="display:none" aria-hidden="true"></div>`)
          }
          const provider = this._providerFor(data.value)
          const modelId = data.value || ""
          const name = data.label || ""

          return template(`
            <div class="${classNames.item} ${classNames.itemChoice} ${data.disabled ? classNames.itemDisabled : classNames.itemSelectable}"
                 data-select-text=""
                 data-choice
                 data-id="${data.id}"
                 data-value="${this._escapeAttr(modelId)}"
                 ${data.disabled ? 'data-choice-disabled aria-disabled="true"' : "data-choice-selectable"}
                 id="${data.elementId}"
                 ${data.groupId > 0 ? 'role="treeitem"' : 'role="option"'}>
              <div class="choices-model-option">
                <div style="flex:1;min-width:0;overflow:hidden">
                  <div class="choices-model-option__name">${escapeHtml(name)}</div>
                  <div class="choices-model-option__id">${escapeHtml(modelId)}</div>
                </div>
                <span class="choices-model-option__provider">${escapeHtml(provider)}</span>
              </div>
            </div>
          `)
        },
        item: ({ classNames }, data) => {
          // Placeholder item (no model selected) — render as plain muted text
          if (data.placeholder) {
            return template(`
              <div class="${classNames.item} ${classNames.placeholder}"
                   data-item
                   data-id="${data.id}"
                   data-value="">
                ${escapeHtml(data.label || "")}
              </div>
            `)
          }

          const provider = this._providerFor(data.value)
          const modelId = data.value || ""
          const name = data.label || ""

          return template(`
            <div class="${classNames.item} ${data.highlighted ? classNames.highlightedState : classNames.itemSelectable}"
                 data-item
                 data-id="${data.id}"
                 data-value="${this._escapeAttr(modelId)}"
                 ${data.active ? 'aria-selected="true"' : ""}
                 ${data.disabled ? 'aria-disabled="true"' : ""}>
              <div class="choices-model-option">
                <span class="choices-model-option__name">${escapeHtml(name)}</span>
                <span class="choices-model-option__id">${escapeHtml(modelId)}</span>
                <span class="choices-model-option__provider">${escapeHtml(provider)}</span>
              </div>
            </div>
          `)
        },
      }),
    })
  }

  disconnect() {
    if (this.choices) {
      this.choices.destroy()
      this.choices = null
    }
  }

  _providerFor(value) {
    return this._optionData[value]?.provider || ""
  }

  _escapeAttr(text) {
    return text
      .replace(/&/g, "&amp;")
      .replace(/"/g, "&quot;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
  }
}
