import { Controller } from "@hotwired/stimulus"

// Manages the Input field editor dialog and field list
// within the mission designer properties panel.
export default class extends Controller {
  static targets = [
    "fieldList", "dialog", "dialogTitle",
    "fieldName", "fieldLabel", "fieldType", "fieldRequired",
    "configSection",
  ]

  connect() {
    this._editingIndex = null
  }

  addField() {
    this._editingIndex = null
    this.#resetForm()
    this.dialogTitleTarget.textContent = "Add Field"
    this.dialogTarget.showModal()
  }

  editField(event) {
    const index = parseInt(event.currentTarget.dataset.index, 10)
    const field = this.#currentFields()[index]
    if (!field) return

    this._editingIndex = index
    this.dialogTitleTarget.textContent = "Edit Field"
    this.#populateForm(field)
    this.dialogTarget.showModal()
  }

  removeField(event) {
    const index = parseInt(event.currentTarget.dataset.index, 10)
    const fields = this.#currentFields()
    fields.splice(index, 1)
    this.#syncFields(fields)
  }

  closeDialog() {
    this.dialogTarget.close()
    this._editingIndex = null
  }

  saveField() {
    const name = this.fieldNameTarget.value.trim()
    const label = this.fieldLabelTarget.value.trim()
    if (!name || !label) return

    const fieldType = this.fieldTypeTarget.value
    const field = {
      variable_name: name,
      label,
      field_type: fieldType,
      required: this.fieldRequiredTarget.checked,
      config: this.#buildConfig(fieldType),
    }

    const fields = this.#currentFields()
    if (this._editingIndex !== null) {
      fields[this._editingIndex] = field
    } else {
      fields.push(field)
    }

    this.#syncFields(fields)
    this.closeDialog()
  }

  onTypeChange() {
    const type = this.fieldTypeTarget.value
    this.configSectionTarget.querySelectorAll(".ms-api-cfg").forEach((el) => {
      const types = (el.dataset.fieldTypes || "").split(" ")
      el.style.display = types.includes(type) ? "block" : "none"
    })
  }

  // Called by mission controller when node is selected
  populateFields(fields) {
    this.#renderFieldList(fields || [])
  }

  // ── Private ──

  #currentFields() {
    const mc = this.#missionController()
    if (!mc?.selectedNodeId) return []

    const input = document.getElementById(mc.canvasTarget?.dataset.flowDataInputId)
    let flow = {}
    try { flow = JSON.parse(input?.value || "{}") } catch { /* ignore */ }

    const node = (flow.nodes || []).find((n) => n.id === mc.selectedNodeId)
    return node?.data?.fields ? [...node.data.fields] : []
  }

  #missionController() {
    const el = this.element.closest(".ms-designer")
    return el ? this.application.getControllerForElementAndIdentifier(el, "mission") : null
  }

  #syncFields(fields) {
    const mc = this.#missionController()
    if (!mc?.selectedNodeId) return

    mc.canvasTarget.dispatchEvent(new CustomEvent("ms:update-node", {
      detail: { nodeId: mc.selectedNodeId, data: { fields } },
    }))
    this.#renderFieldList(fields)
  }

  #renderFieldList(fields) {
    if (!fields.length) {
      this.fieldListTarget.innerHTML = '<div class="ms-api-fields-empty">No fields defined yet.</div>'
      return
    }

    this.fieldListTarget.innerHTML = fields.map((f, i) => `
      <div class="ms-api-field-row">
        <div class="ms-api-field-info">
          <span class="ms-api-field-name">${this.#esc(f.variable_name)}</span>
          <span class="ms-api-field-type-badge">${this.#esc(f.field_type)}</span>
          ${f.required ? '<span class="ms-api-field-required-badge">Required</span>' : ""}
        </div>
        <div class="ms-api-field-label">${this.#esc(f.label)}</div>
        <div class="ms-api-field-actions">
          <button class="ms-api-field-action-btn" type="button"
            data-action="click->input-fields#editField" data-index="${i}" title="Edit">
            <i class="fa-solid fa-pen-to-square"></i>
          </button>
          <button class="ms-api-field-action-btn ms-api-field-action-btn-danger" type="button"
            data-action="click->input-fields#removeField" data-index="${i}" title="Remove">
            <i class="fa-solid fa-trash-can"></i>
          </button>
        </div>
      </div>
    `).join("")
  }

  #resetForm() {
    this.fieldNameTarget.value = ""
    this.fieldLabelTarget.value = ""
    this.fieldRequiredTarget.checked = false
    this.#setFieldType("string")
    this.#clearConfigInputs()
    this.onTypeChange()
  }

  #populateForm(field) {
    this.fieldNameTarget.value = field.variable_name || ""
    this.fieldLabelTarget.value = field.label || ""
    this.fieldRequiredTarget.checked = !!field.required
    this.#setFieldType(field.field_type || "string")
    this.#clearConfigInputs()

    const cfg = field.config || {}
    this.configSectionTarget.querySelectorAll("[data-config-key]").forEach((el) => {
      const val = cfg[el.dataset.configKey]
      if (val === undefined || val === null) return

      if (el.dataset.configParse === "csv-array") {
        el.value = Array.isArray(val) ? val.join(", ") : val
      } else {
        el.value = String(val)
      }
    })
    this.onTypeChange()
  }

  #setFieldType(value) {
    this.fieldTypeTarget.value = value
  }

  #clearConfigInputs() {
    this.configSectionTarget.querySelectorAll("[data-config-key]").forEach((el) => {
      el.value = ""
    })
  }

  #buildConfig(fieldType) {
    const cfg = {}
    this.configSectionTarget.querySelectorAll("[data-config-key]").forEach((el) => {
      const parent = el.closest(".ms-api-cfg")
      if (!parent) return
      const types = (parent.dataset.fieldTypes || "").split(" ")
      if (!types.includes(fieldType)) return

      const raw = el.value.trim()
      if (raw === "") return

      cfg[el.dataset.configKey] = this.#parseValue(el.dataset.configParse, raw)
    })
    return cfg
  }

  #parseValue(parse, raw) {
    switch (parse) {
      case "integer": return parseInt(raw, 10)
      case "float": return parseFloat(raw)
      case "boolean": return raw === "true"
      case "csv-array": return raw.split(",").map((s) => s.trim().toLowerCase()).filter(Boolean)
      default: return raw
    }
  }

  #esc(str) {
    const d = document.createElement("div")
    d.textContent = str || ""
    return d.innerHTML
  }
}
