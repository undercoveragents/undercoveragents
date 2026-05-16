import { Controller } from "@hotwired/stimulus"

// Manages the Global Variables editor in the Variables sidebar panel.
// Reads/writes to #mission-global-variables hidden input and triggers autosave.
export default class extends Controller {
  static targets = ["list", "empty"]
  static values = { variableTypes: { type: Array, default: ["string", "number", "boolean"] } }

  connect() {
    this.#render()
    document.addEventListener("ms:global-variables-changed", this._boundRefresh = () => this.#render())
  }

  disconnect() {
    document.removeEventListener("ms:global-variables-changed", this._boundRefresh)
  }

  // ── Actions ──

  add() {
    const vars = this.#read()
    let key = "new_variable"
    let i = 1
    while (vars.some((v) => v.key === key)) { key = `new_variable_${i++}` }
    vars.push({ key, value: "", type: "string" })
    this.#write(vars)
    this.#render()
    // Focus the new key input
    requestAnimationFrame(() => {
      const inputs = this.listTarget.querySelectorAll(".ms-gv-key")
      const last = inputs[inputs.length - 1]
      if (last) { last.focus(); last.select() }
    })
  }

  remove(event) {
    const idx = parseInt(event.currentTarget.dataset.idx, 10)
    const vars = this.#read()
    vars.splice(idx, 1)
    this.#write(vars)
    this.#render()
  }

  update(event) {
    const idx = parseInt(event.currentTarget.dataset.idx, 10)
    const field = event.currentTarget.dataset.field
    const vars = this.#read()
    if (!vars[idx]) return
    let val = event.currentTarget.value
    if (field === "key") val = val.replace(/[^a-zA-Z0-9_]/g, "_")
    vars[idx][field] = val
    this.#write(vars)
  }

  // ── Private ──

  #read() {
    const input = document.getElementById("mission-global-variables")
    if (!input) return []
    try { return JSON.parse(input.value || "[]") } catch { return [] }
  }

  #write(vars) {
    const input = document.getElementById("mission-global-variables")
    if (input) input.value = JSON.stringify(vars)
    // Trigger autosave via the canvas element
    const canvas = document.getElementById("mission-designer-root")
    if (canvas) canvas.dispatchEvent(new CustomEvent("ms:flow-changed", { bubbles: true }))
  }

  #render() {
    const vars = this.#read()
    this.#toggleEmpty(vars.length === 0)
    this.listTarget.innerHTML = ""
    vars.forEach((v, idx) => { this.listTarget.appendChild(this.#buildRow(v, idx)) })
  }

  #toggleEmpty(isEmpty) {
    if (this.hasEmptyTarget) {
      this.emptyTarget.classList.toggle("hidden", !isEmpty)
    }
  }

  #buildRow(variable, idx) {
    const row = document.createElement("div")
    row.className = "ms-gv-row"
    row.innerHTML = `
      <input class="ms-gv-key" type="text" value="${this.#escape(variable.key)}" placeholder="name"
             data-idx="${idx}" data-field="key"
             data-action="blur->global-variables#update">
      <select class="ms-gv-type" data-idx="${idx}" data-field="type"
              data-action="change->global-variables#update">
        ${this.variableTypesValue.map((t) => `<option value="${t}"${variable.type === t ? " selected" : ""}>${t}</option>`).join("")}
      </select>
      <input class="ms-gv-value" type="text" value="${this.#escape(variable.value)}" placeholder="value"
             data-idx="${idx}" data-field="value"
             data-action="blur->global-variables#update">
      <button class="ms-gv-remove" type="button" title="Remove" data-idx="${idx}"
              data-action="click->global-variables#remove">
        <i class="fa-solid fa-xmark"></i>
      </button>
    `
    return row
  }

  #escape(str) {
    const div = document.createElement("div")
    div.textContent = str || ""
    return div.innerHTML.replace(/"/g, "&quot;")
  }
}
