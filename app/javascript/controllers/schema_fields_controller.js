import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    autoSubmit: { type: Boolean, default: false },
    editable: { type: Boolean, default: true },
  }

  static targets = [
    "hiddenInput", "fieldList", "dialog", "dialogTitle",
    "fieldName", "fieldLabel", "fieldType", "fieldRequired",
    "configSection",
  ]

  connect() {
    this.editingIndex = null
    this.renderFieldList(this.currentFields())
  }

  disconnect() {
    this.removeConfirmModal(false)
  }

  addField() {
    this.editingIndex = null
    this.resetForm()
    this.dialogTitleTarget.textContent = "Add"
    this.dialogTarget.showModal()
  }

  editField(event) {
    const index = parseInt(event.currentTarget.dataset.index, 10)
    const field = this.currentFields()[index]
    if (!field) return

    this.editingIndex = index
    this.dialogTitleTarget.textContent = "Edit Parameter"
    this.populateForm(field)
    this.dialogTarget.showModal()
  }

  async removeField(event) {
    const index = parseInt(event.currentTarget.dataset.index, 10)
    const fields = this.currentFields()
    const field = fields[index]
    if (!field) return

    const confirmed = await this.confirmRemoval(field)
    if (!confirmed) return

    fields.splice(index, 1)
    this.syncFields(fields)
  }

  closeDialog() {
    this.dialogTarget.close()
    this.editingIndex = null
  }

  saveField() {
    const variableName = this.fieldNameTarget.value.trim()
    const label = this.fieldLabelTarget.value.trim()
    if (!variableName || !label) return

    const fieldType = this.fieldTypeTarget.value
    const field = {
      variable_name: variableName,
      label,
      field_type: fieldType,
      required: this.fieldRequiredTarget.checked,
      config: this.buildConfig(fieldType),
    }

    const fields = this.currentFields()
    if (this.editingIndex !== null) {
      fields[this.editingIndex] = field
    } else {
      fields.push(field)
    }

    this.syncFields(fields)
    this.closeDialog()
  }

  onTypeChange() {
    const type = this.fieldTypeTarget.value
    this.configSectionTarget.querySelectorAll(".ms-api-cfg").forEach((element) => {
      const types = (element.dataset.fieldTypes || "").split(" ")
      element.style.display = types.includes(type) ? "block" : "none"
    })
  }

  currentFields() {
    try {
      return JSON.parse(this.hiddenInputTarget.value || "[]")
    } catch {
      return []
    }
  }

  syncFields(fields) {
    this.hiddenInputTarget.value = JSON.stringify(fields)
    this.renderFieldList(fields)

    if (this.autoSubmitValue) {
      this.element.closest("form")?.requestSubmit()
    }
  }

  renderFieldList(fields) {
    if (!fields.length) {
      this.fieldListTarget.innerHTML = `
        <div class="text-center py-6">
          <i class="fa-solid fa-sliders text-2xl text-text-muted mb-2"></i>
          <p class="text-sm text-text-muted">No input parameters defined.</p>
        </div>
      `
      return
    }

    this.fieldListTarget.innerHTML = `
      <div class="space-y-2">
        ${fields.map((field, index) => this.renderFieldRow(field, index)).join("")}
      </div>
    `
  }

  resetForm() {
    this.fieldNameTarget.value = ""
    this.fieldLabelTarget.value = ""
    this.fieldRequiredTarget.checked = false
    this.fieldTypeTarget.value = "string"
    this.clearConfigInputs()
    this.onTypeChange()
  }

  populateForm(field) {
    this.fieldNameTarget.value = field.variable_name || ""
    this.fieldLabelTarget.value = field.label || ""
    this.fieldRequiredTarget.checked = !!field.required
    this.fieldTypeTarget.value = field.field_type || "string"
    this.clearConfigInputs()

    const config = field.config || {}
    this.configSectionTarget.querySelectorAll("[data-config-key]").forEach((element) => {
      const value = config[element.dataset.configKey]
      if (value === undefined || value === null) return

      if (element.dataset.configParse === "csv-array") {
        element.value = Array.isArray(value) ? value.join(", ") : value
      } else {
        element.value = String(value)
      }
    })

    this.onTypeChange()
  }

  clearConfigInputs() {
    this.configSectionTarget.querySelectorAll("[data-config-key]").forEach((element) => {
      element.value = ""
    })
  }

  buildConfig(fieldType) {
    const config = {}
    this.configSectionTarget.querySelectorAll("[data-config-key]").forEach((element) => {
      const parent = element.closest(".ms-api-cfg")
      if (!parent) return

      const types = (parent.dataset.fieldTypes || "").split(" ")
      if (!types.includes(fieldType)) return

      const raw = element.value.trim()
      if (raw === "") return

      config[element.dataset.configKey] = this.parseValue(element.dataset.configParse, raw)
    })
    return config
  }

  parseValue(parse, raw) {
    switch (parse) {
      case "integer": return parseInt(raw, 10)
      case "float": return parseFloat(raw)
      case "boolean": return raw === "true"
      case "csv-array": return raw.split(",").map((item) => item.trim().toLowerCase()).filter(Boolean)
      default: return raw
    }
  }

  confirmRemoval(field) {
    this.removeConfirmModal(false)

    return new Promise((resolve) => {
      this.confirmResolve = resolve
      const fieldName = field.label || field.variable_name || "this parameter"
      const message = `Are you sure you want to remove ${fieldName}?`

      this.confirmOverlay = document.createElement("div")
      this.confirmOverlay.className = "confirm-overlay"
      this.confirmOverlay.innerHTML = `
        <div class="confirm-modal" role="dialog" aria-modal="true" aria-labelledby="confirm-title">
          <div class="confirm-header">
            <div class="confirm-icon">
              <i class="fa-solid fa-triangle-exclamation"></i>
            </div>
            <h3 id="confirm-title" class="confirm-title">Remove Parameter</h3>
          </div>
          <p class="confirm-message">${this.escape(message)}</p>
          <div class="confirm-actions">
            <button type="button" class="btn btn-secondary" data-action="cancel">
              Cancel
            </button>
            <button type="button" class="btn btn-danger-outline" data-action="confirm">
              <i class="fa-solid fa-xmark mr-1"></i>
              Remove
            </button>
          </div>
        </div>
      `

      this.confirmOverlay.addEventListener("click", this.onConfirmOverlayClick)
      this.handleConfirmKeydown = (event) => {
        if (event.key === "Escape") this.cancelRemove()
      }
      document.addEventListener("keydown", this.handleConfirmKeydown)
      document.body.appendChild(this.confirmOverlay)

      requestAnimationFrame(() => {
        this.confirmOverlay?.querySelector('[data-action="cancel"]')?.focus()
      })
    })
  }

  onConfirmOverlayClick = (event) => {
    const action = event.target.closest("[data-action]")?.dataset?.action
    if (action === "confirm") {
      this.confirmRemove()
    } else if (action === "cancel" || event.target === this.confirmOverlay) {
      this.cancelRemove()
    }
  }

  confirmRemove() {
    this.removeConfirmModal(true)
  }

  cancelRemove() {
    this.removeConfirmModal(false)
  }

  removeConfirmModal(confirmed) {
    if (this.confirmOverlay) {
      document.removeEventListener("keydown", this.handleConfirmKeydown)
      this.confirmOverlay.removeEventListener("click", this.onConfirmOverlayClick)
      this.confirmOverlay.remove()
      this.confirmOverlay = null
    }

    if (this.confirmResolve) {
      const resolve = this.confirmResolve
      this.confirmResolve = null
      resolve(confirmed)
    }
  }

  escape(value) {
    const div = document.createElement("div")
    div.textContent = value || ""
    return div.innerHTML
  }

  renderFieldRow(field, index) {
    return `
      <div class="flex items-center gap-2 p-2 rounded-lg bg-surface-secondary">
        <div class="entity-card__icon">
          <i class="fa-solid fa-sliders"></i>
        </div>
        <div class="flex-1 min-w-0">
          <div class="flex flex-wrap items-center gap-2">
            <span class="text-sm font-medium text-text-primary leading-snug">${this.escape(field.variable_name)}</span>
            <span class="badge badge-secondary">${this.escape(this.fieldTypeLabel(field.field_type))}</span>
            ${field.required ? '<span class="badge badge-warning">Required</span>' : ""}
          </div>
          <div class="text-xs text-text-secondary mt-1">${this.escape(field.label)}</div>
        </div>
        ${this.renderFieldActions(index)}
      </div>
    `
  }

  renderFieldActions(index) {
    if (!this.editableValue) return ""

    return `
      <div class="ml-auto flex items-center gap-2">
        <button class="btn btn-ghost btn-xs" type="button" data-action="click->schema-fields#editField" data-index="${index}" title="Edit parameter">
          <i class="fa-solid fa-pen-to-square"></i>
        </button>
        <button class="btn btn-ghost btn-xs text-danger-400 hover:text-danger-600" type="button" data-action="click->schema-fields#removeField" data-index="${index}" title="Remove parameter">
          <i class="fa-solid fa-xmark"></i>
        </button>
      </div>
    `
  }

  fieldTypeLabel(fieldType) {
    const labels = {
      string: "String",
      string_array: "String[]",
      number: "Number",
      number_array: "Number[]",
      boolean: "Boolean",
      boolean_array: "Boolean[]",
      file: "File",
      file_array: "File[]",
      json: "JSON",
      date: "Date",
      date_array: "Date[]",
      datetime: "DateTime",
      datetime_array: "DateTime[]",
    }

    return labels[fieldType] || fieldType
  }
}
