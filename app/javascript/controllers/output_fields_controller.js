import { Controller } from "@hotwired/stimulus"

// Manages output variable definitions for the code node
// in the mission designer properties panel.
export default class extends Controller {
  static targets = [
    "fieldList", "dialog", "dialogTitle",
    "fieldName", "fieldDescription",
  ]

  connect() {
    this._editingIndex = null
  }

  addField() {
    this._editingIndex = null
    this.#resetForm()
    this.dialogTitleTarget.textContent = "Add Output Variable"
    this.dialogTarget.showModal()
  }

  editField(event) {
    const index = parseInt(event.currentTarget.dataset.index, 10)
    const fields = this.#currentFields()
    const field = fields[index]
    if (!field) return

    this._editingIndex = index
    this.dialogTitleTarget.textContent = "Edit Output Variable"
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
    if (!name) return

    const field = {
      name,
      description: this.fieldDescriptionTarget.value.trim(),
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

  backdropClick(event) {
    if (event.target === this.dialogTarget) {
      this.closeDialog()
    }
  }

  // ── Private ──

  #currentFields() {
    const mc = this.#missionController()
    if (!mc?.selectedNodeId) return []

    const input = document.getElementById(mc.canvasTarget?.dataset.flowDataInputId)
    let flow = {}
    try { flow = JSON.parse(input?.value || "{}") } catch { /* ignore */ }

    const node = (flow.nodes || []).find((n) => n.id === mc.selectedNodeId)
    return node?.data?.output_variables ? [...node.data.output_variables] : []
  }

  #missionController() {
    const el = this.element.closest(".ms-designer")
    return el ? this.application.getControllerForElementAndIdentifier(el, "mission") : null
  }

  #syncFields(fields) {
    const mc = this.#missionController()
    if (!mc?.selectedNodeId) return

    mc.canvasTarget.dispatchEvent(new CustomEvent("ms:update-node", {
      detail: { nodeId: mc.selectedNodeId, data: { output_variables: fields } },
    }))
    this.#renderFieldList(fields)
  }

  #renderFieldList(fields) {
    if (!fields.length) {
      this.fieldListTarget.innerHTML = '<div class="ms-api-fields-empty">No output variables defined yet.</div>'
      return
    }

    this.fieldListTarget.innerHTML = fields.map((f, i) => `
      <div class="ms-api-field-row">
        <div class="ms-api-field-info">
          <span class="ms-api-field-name">${this.#esc(f.name)}</span>
        </div>
        ${f.description ? `<div class="ms-api-field-label">${this.#esc(f.description)}</div>` : ""}
        <div class="ms-api-field-actions">
          <button class="ms-api-field-action-btn" type="button"
            data-action="click->output-fields#editField" data-index="${i}" title="Edit">
            <i class="fa-solid fa-pen-to-square"></i>
          </button>
          <button class="ms-api-field-action-btn ms-api-field-action-btn-danger" type="button"
            data-action="click->output-fields#removeField" data-index="${i}" title="Remove">
            <i class="fa-solid fa-trash-can"></i>
          </button>
        </div>
      </div>
    `).join("")
  }

  #resetForm() {
    this.fieldNameTarget.value = ""
    this.fieldDescriptionTarget.value = ""
  }

  #populateForm(field) {
    this.fieldNameTarget.value = field.name || ""
    this.fieldDescriptionTarget.value = field.description || ""
  }

  #esc(str) {
    const div = document.createElement("div")
    div.textContent = str || ""
    return div.innerHTML
  }
}
