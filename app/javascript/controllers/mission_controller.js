import { Controller } from "@hotwired/stimulus"

// Bridges HTML palette + properties panel ↔ React mission canvas via DOM events
export default class extends Controller {
  static targets = [
    "paletteSearch", "paletteSections",
    "canvas",
    "nodePropertiesFrame",
    "propTemperatureValue",
    "propCases", "propAssignments", "propExtractions",
    "propHeaders", "propParams", "propFormUrlencodedBody", "propMultipartFormData",
    "propOutputVariables",
    "propFileVariables",
    "propToolIds",
    "importFile",
    "flowUpdates",
  ]

  connect() {
    this.selectedNodeId = null
    this.selectedNodeType = null
    this._canUndo = this.canvasTarget.dataset.canUndo === "true"
    this._canRedo = this.canvasTarget.dataset.canRedo === "true"
    this._nodeErrors = JSON.parse(this.canvasTarget.dataset.nodeErrors || "{}")

    this.#broadcastUndoRedoState()

    // Listen for React → Rails events
    this.canvasTarget.addEventListener("ms:node-selected", this.onNodeSelected)
    this.canvasTarget.addEventListener("ms:node-deselected", this.onNodeDeselected)
    this.canvasTarget.addEventListener("ms:flow-changed", this.onFlowChanged)
    this.canvasTarget.addEventListener("ms:node-action", this.onNodeAction)
    this.canvasTarget.addEventListener("ms:request-undo", this._boundRequestUndo = () => this.undo())
    this.canvasTarget.addEventListener("ms:request-redo", this._boundRequestRedo = () => this.redo())
    this.canvasTarget.addEventListener("ms:request-save", this._boundRequestSave = () => this.#saveNow())
    this._boundKeydown = this.#handleKeydown.bind(this)
    document.addEventListener("keydown", this._boundKeydown)
    this._closePropMenuOutside = (e) => {
      const menu = this.element.querySelector(".ms-prop-context-menu")
      if (!menu || !menu.contains(e.target)) {
        this.#closePropMenu()
      }
    }

    // Observe Turbo Stream flow updates from mission designer agent
    this.#startFlowUpdateObserver()
  }

  disconnect() {
    if (this.hasCanvasTarget) {
      this.canvasTarget.removeEventListener("ms:node-selected", this.onNodeSelected)
      this.canvasTarget.removeEventListener("ms:node-deselected", this.onNodeDeselected)
      this.canvasTarget.removeEventListener("ms:flow-changed", this.onFlowChanged)
      this.canvasTarget.removeEventListener("ms:node-action", this.onNodeAction)
      this.canvasTarget.removeEventListener("ms:request-undo", this._boundRequestUndo)
      this.canvasTarget.removeEventListener("ms:request-redo", this._boundRequestRedo)
      this.canvasTarget.removeEventListener("ms:request-save", this._boundRequestSave)
    }
    document.removeEventListener("keydown", this._boundKeydown)
    document.removeEventListener("click", this._closePropMenuOutside)
    clearTimeout(this._autosaveTimer)
    if (this._flowUpdateObserver) this._flowUpdateObserver.disconnect()
  }

  // ── Palette: drag start ──
  onPaletteDragStart(event) {
    const el = event.currentTarget
    const payload = { type: el.dataset.nodeType, data: JSON.parse(el.dataset.nodeData) }
    event.dataTransfer.setData("application/reactflow", JSON.stringify(payload))
    event.dataTransfer.effectAllowed = "move"
  }

  // ── Palette: drag end ──
  onPaletteDragEnd() {
    // no-op — palette lives in sidebar, stays open
  }

  // ── Palette: toggle section ──
  toggleSection(event) {
    const header = event.currentTarget
    const items = header.nextElementSibling
    const chevron = header.querySelector(".ms-palette-chevron")

    if (items) items.classList.toggle("hidden")
    if (chevron) {
      chevron.classList.toggle("fa-chevron-up")
      chevron.classList.toggle("fa-chevron-down")
    }
  }

  // ── Palette: search filter ──
  filterPalette() {
    const query = this.paletteSearchTarget.value.toLowerCase()
    this.paletteSectionsTarget.querySelectorAll(".ms-palette-item").forEach((item) => {
      const name = item.querySelector(".ms-palette-item-name")?.textContent.toLowerCase() || ""
      const desc = item.querySelector(".ms-palette-item-desc")?.textContent.toLowerCase() || ""
      item.style.display = (name.includes(query) || desc.includes(query)) ? "" : "none"
    })
    // Show/hide sections if all items hidden
    this.paletteSectionsTarget.querySelectorAll(".ms-palette-section").forEach((section) => {
      const visible = section.querySelectorAll(".ms-palette-item:not([style*='display: none'])")
      section.style.display = visible.length ? "" : "none"
    })
  }

  // ── Autosave: debounced PATCH on flow change (event from React) ──
  onFlowChanged = () => {
    const saveUrl = this.canvasTarget.dataset.saveUrl
    if (!saveUrl) return

    clearTimeout(this._autosaveTimer)
    this._autosaveTimer = setTimeout(async () => {
      await this.#performSave()
    }, 800)
  }

  // Immediate save — used after arrange to persist ELK positions before
  // the next AI tool call can overwrite them with stale server positions.
  #saveNow() {
    clearTimeout(this._autosaveTimer)
    this.#performSave()
  }

  async #performSave() {
    const saveUrl = this.canvasTarget.dataset.saveUrl
    if (!saveUrl) return

    const flowData = document.getElementById(this.canvasTarget.dataset.flowDataInputId)?.value
    if (!flowData) return
    const mergedFlowData = this.#mergeGlobalVariables(flowData)
    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content || ""
    try {
      const resp = await fetch(saveUrl, {
        method: "PATCH",
        headers: { "Content-Type": "application/json", "X-CSRF-Token": csrfToken, "Accept": "application/json" },
        body: JSON.stringify({ mission: { flow_data: mergedFlowData } }),
      })
      if (resp.ok) {
        const data = await resp.json()
        this.#updateUndoRedoState(data.can_undo, data.can_redo)
        if (data.node_errors !== undefined) this.#applyNodeErrors(data.node_errors)
        if (data.global_variables !== undefined) this.#syncGlobalVariablesInput(data.global_variables)
        document.dispatchEvent(new CustomEvent("ms:flow-saved"))
      } else {
        this.#showAutosaveError()
      }
    } catch {
      this.#showAutosaveError()
    }
  }

  // ── React → Rails: node selected ──
  onNodeSelected = (event) => {
    const { node } = event.detail

    // Flush any unsaved property values before replacing the panel
    this.#flushPendingInputs()

    this.selectedNodeId = node.id
    this.selectedNodeType = node.type

    // Load server-rendered properties via Turbo Frame
    if (this.hasNodePropertiesFrameTarget) {
      const baseUrl = this.nodePropertiesFrameTarget.dataset.nodePropertiesUrl
      if (baseUrl) {
        this.nodePropertiesFrameTarget.src = `${baseUrl}?node_id=${encodeURIComponent(node.id)}`
      }
    }

    // Activate inspector tab in the sidebar
    document.dispatchEvent(new CustomEvent("ms:activate-sidebar-tab", { detail: { tab: "inspector" } }))
  }

  // ── React → Rails: node deselected ──
  onNodeDeselected = () => {
    // Flush any unsaved property values before clearing the panel
    this.#flushPendingInputs()

    this.selectedNodeId = null
    this.selectedNodeType = null

    // Clear the Turbo Frame back to empty state
    if (this.hasNodePropertiesFrameTarget) {
      this.nodePropertiesFrameTarget.src = ""
      this.nodePropertiesFrameTarget.innerHTML = `
        <div class="ms-sidebar-inspector-empty">
          <div class="ms-sidebar-empty-state">
            <i class="fa-solid fa-mouse-pointer"></i>
            <p>Select a node to inspect its properties</p>
          </div>
        </div>
      `
    }
  }

  // ── Rails → React: update node property ──
  updateNodeProp(event) {
    const nodeId = this.#nodeIdForSource(event.currentTarget)
    if (!nodeId) return
    const key = event.currentTarget.dataset.propKey
    const value = this.#coercePropValue(event.currentTarget, key)
    if (key === "temperature" && value !== "" && this.hasPropTemperatureValueTarget) {
      this.propTemperatureValueTarget.textContent = value
    }
    this.#dispatchNodeUpdate({ [key]: value }, nodeId)
  }

  // ── Auto-resize description textarea in header ──
  autoResizeDescription(event) {
    this.#autoResizeTextarea(event.currentTarget)
  }

  // ── Update node variable name (sanitized) ──
  updateNodeName(event) {
    const nodeId = this.#nodeIdForSource(event.currentTarget)
    if (!nodeId) return
    const raw = event.currentTarget.value || ""
    const sanitized = raw.toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_|_$/g, "")
    event.currentTarget.value = sanitized
    this.#dispatchNodeUpdate({ name: sanitized }, nodeId)
  }

  // ── Rails → React: update node property from select (stores both id and name) ──
  updateNodePropSelect(event) {
    const nodeId = this.#nodeIdForSource(event.currentTarget)
    if (!nodeId) return
    const key = event.currentTarget.dataset.propKey
    const nameKey = event.currentTarget.dataset.nameKey
    const value = event.currentTarget.value
    const displayName = event.currentTarget.selectedOptions[0]?.text || ""
    const data = { [key]: value }
    if (nameKey) data[nameKey] = displayName
    this.#dispatchNodeUpdate(data, nodeId)
  }

  // ── Rails → React: update sub-mission selection and reload input variable fields ──
  updateSubMission(event) {
    const nodeId = this.#nodeIdForSource(event.currentTarget)
    if (!nodeId) return
    const select = event.currentTarget
    const missionId = select.value
    const missionName = select.selectedOptions[0]?.text || ""
    this.#dispatchNodeUpdate({ mission_id: missionId, mission_name: missionName, input_variables: {} }, nodeId)

    const container = this.element.querySelector("[data-mission-input-fields]")
    if (!container) return

    const url = select.dataset.ioFieldsUrl
    if (!url || !missionId) {
      container.innerHTML = ""
      return
    }

    fetch(`${url}?sub_mission_id=${encodeURIComponent(missionId)}`, {
      headers: { "Accept": "application/json" },
    })
      .then((r) => r.json())
      .then((data) => this.#renderSubMissionInputFields(container, data.input_fields || []))
      .catch(() => { container.innerHTML = "" })
  }

  // Sync sub-mission input variable value to node data
  syncSubMissionInput(event) {
    const nodeId = this.#nodeIdForSource(event.currentTarget)
    if (!nodeId) return
    const container = this.element.querySelector("[data-mission-input-fields]")
    if (!container) return

    const inputs = {}
    container.querySelectorAll("[data-sub-mission-var]").forEach((row) => {
      const key = row.dataset.subMissionVar
      const exprHidden = row.querySelector('[data-expression-editor-target="hidden"]')
      const value = exprHidden ? exprHidden.value?.trim() : row.querySelector(".ms-prop-input")?.value?.trim()
      if (key && value) inputs[key] = value
    })
    this.#dispatchNodeUpdate({ input_variables: inputs }, nodeId)
  }

  #renderSubMissionInputFields(container, fields) {
    if (!fields.length) {
      container.innerHTML = '<div class="ms-prop-hint"><i class="fa-solid fa-circle-info"></i> This mission has no input fields.</div>'
      return
    }

    const rows = fields.map((f) => {
      const required = f.required ? ' <span class="ms-prop-required">*</span>' : ""
      const typeLabel = f.field_type || "string"
      return `
        <div class="ms-prop-sub-mission-row" data-sub-mission-var="${this.#escapeAttr(f.variable_name)}">
          <label class="ms-prop-label ms-prop-label-sm">${this.#escapeHtml(f.variable_name)}${required}
            <span class="ms-prop-type-hint">${this.#escapeHtml(typeLabel)}</span>
          </label>
          <div class="ms-expr-wrap" data-controller="expression-editor" data-expression-editor-variables-value='[]' data-expression-editor-multiline-value="false">
            <div class="ms-expr-editor" contenteditable="true" data-expression-editor-target="editor" data-rows="1" data-placeholder="Value or {{variable}}"></div>
            <textarea class="hidden" data-expression-editor-target="hidden" data-action="blur->mission#syncSubMissionInput input->mission#syncSubMissionInput"></textarea>
            <div class="ms-expr-dropdown hidden" data-expression-editor-target="dropdown"></div>
          </div>
        </div>
      `
    }).join("")

    container.innerHTML = rows
  }

  #escapeHtml(str) {
    const div = document.createElement("div")
    div.textContent = str
    return div.innerHTML
  }

  #escapeAttr(str) {
    return str.replace(/&/g, "&amp;").replace(/"/g, "&quot;").replace(/'/g, "&#39;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
  }

  // ── Rails → React: update LLM connector and reload models via Turbo Frame ──
  updateLlmConnector(event) {
    const nodeId = this.#nodeIdForSource(event.currentTarget)
    if (!nodeId) return
    const select = event.currentTarget
    const connectorId = select.value
    const connectorName = select.selectedOptions[0]?.text || ""
    this.#dispatchNodeUpdate({ connector_id: connectorId, connector_name: connectorName, model: "", model_name: "" }, nodeId)

    // Reload model options via Turbo Frame
    const modelFrame = this.element.querySelector("turbo-frame#node-model-select")
    if (!modelFrame) return

    const url = modelFrame.dataset.nodeModelOptionsUrl
    if (!url) return

    const nextUrl = new URL(url, window.location.origin)
    if (connectorId) nextUrl.searchParams.set("connector_id", connectorId)
    modelFrame.src = nextUrl.pathname + nextUrl.search
  }

  // ── Rails → React: update node color ──
  updateNodeColor(event) {
    const nodeId = this.#nodeIdForSource(event.currentTarget)
    if (!nodeId) return
    const color = event.currentTarget.dataset.color
    const iconEl = this.element.querySelector(".ms-properties-icon")
    if (iconEl) iconEl.style.background = color
    this.#dispatchNodeUpdate({ color }, nodeId)
  }

  // ── Handle node menu actions dispatched from React canvas ──
  onNodeAction = (event) => {
    const { nodeId, action } = event.detail
    if (action === "delete") {
      this.#callNodeAction("delete_node", nodeId)
    } else if (action === "duplicate") {
      this.#callNodeAction("duplicate_node", nodeId)
    } else if (action === "disable" || action === "enable") {
      this.#toggleNodeDisabled(nodeId, action === "disable")
    }
  }

  // ── Keyboard shortcuts ──
  #handleKeydown(event) {
    // Skip shortcuts when user is typing in an input/textarea/select.
    // Use composedPath() to see through Shadow DOM boundaries.
    for (const el of event.composedPath()) {
      if (el === document || el === window) break
      const tag = el.tagName
      if (tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT" || el.isContentEditable) return
    }

    // Skip copy/paste shortcuts when user has selected text (e.g. in sidebar labels)
    const selection = window.getSelection()
    const hasTextSelection = selection && selection.toString().length > 0

    const mod = event.metaKey || event.ctrlKey

    // Ctrl+Z / Cmd+Z — Undo
    if (mod && !event.shiftKey && event.key === "z") {
      event.preventDefault()
      this.undo()
      return
    }

    // Ctrl+Shift+Z / Cmd+Shift+Z — Redo
    if (mod && event.shiftKey && event.key === "z") {
      event.preventDefault()
      this.redo()
      return
    }

    // Ctrl+A / Cmd+A — Select all nodes
    if (mod && event.key === "a" && !hasTextSelection) {
      event.preventDefault()
      this.canvasTarget.dispatchEvent(new CustomEvent("ms:select-all", { bubbles: true }))
      return
    }

    // Ctrl+D / Cmd+D — Duplicate selected node
    if (mod && event.key === "d") {
      event.preventDefault()
      if (this.selectedNodeId) this.duplicateNode()
      return
    }

    // Ctrl+C / Cmd+C — Copy selected nodes
    if (mod && event.key === "c" && !hasTextSelection) {
      event.preventDefault()
      this.canvasTarget.dispatchEvent(new CustomEvent("ms:copy-nodes", { bubbles: true }))
      return
    }

    // Ctrl+V / Cmd+V — Paste copied nodes
    if (mod && event.key === "v") {
      event.preventDefault()
      this.canvasTarget.dispatchEvent(new CustomEvent("ms:paste-nodes", { bubbles: true }))
      return
    }

    // ? — Show keyboard shortcut help
    if (event.key === "?" || (event.shiftKey && event.key === "/")) {
      event.preventDefault()
      this.#toggleShortcutHelp()
      return
    }

    // Escape — Close properties panel / shortcut help
    if (event.key === "Escape") {
      const helpModal = this.element.querySelector(".ms-shortcut-help")
      if (helpModal) {
        helpModal.remove()
        return
      }
      if (this.selectedNodeId) {
        this.onNodeDeselected()
      }
    }
  }

  #toggleShortcutHelp() {
    const existing = this.element.querySelector(".ms-shortcut-help")
    if (existing) {
      existing.remove()
      return
    }

    const isMac = navigator.platform.includes("Mac")
    const mod = isMac ? "⌘" : "Ctrl"

    const modal = document.createElement("div")
    modal.className = "ms-shortcut-help"
    modal.innerHTML = `
      <div class="ms-shortcut-help-content">
        <div class="ms-shortcut-help-header">
          <div class="ms-shortcut-help-title">
            <i class="fa-solid fa-keyboard"></i>
            Keyboard Shortcuts
          </div>
          <button class="ms-shortcut-help-close" type="button" title="Close">
            <i class="fa-solid fa-xmark"></i>
          </button>
        </div>
        <div class="ms-shortcut-group">
          <div class="ms-shortcut-group-title">General</div>
          <div class="ms-shortcut-row">
            <span class="ms-shortcut-label">Undo</span>
            <span class="ms-shortcut-keys"><span class="ms-shortcut-key">${mod}</span><span class="ms-shortcut-key">Z</span></span>
          </div>
          <div class="ms-shortcut-row">
            <span class="ms-shortcut-label">Redo</span>
            <span class="ms-shortcut-keys"><span class="ms-shortcut-key">${mod}</span><span class="ms-shortcut-key">⇧</span><span class="ms-shortcut-key">Z</span></span>
          </div>
          <div class="ms-shortcut-row">
            <span class="ms-shortcut-label">Select all</span>
            <span class="ms-shortcut-keys"><span class="ms-shortcut-key">${mod}</span><span class="ms-shortcut-key">A</span></span>
          </div>
          <div class="ms-shortcut-row">
            <span class="ms-shortcut-label">Duplicate selected</span>
            <span class="ms-shortcut-keys"><span class="ms-shortcut-key">${mod}</span><span class="ms-shortcut-key">D</span></span>
          </div>
        </div>
        <div class="ms-shortcut-group">
          <div class="ms-shortcut-group-title">Clipboard</div>
          <div class="ms-shortcut-row">
            <span class="ms-shortcut-label">Copy nodes</span>
            <span class="ms-shortcut-keys"><span class="ms-shortcut-key">${mod}</span><span class="ms-shortcut-key">C</span></span>
          </div>
          <div class="ms-shortcut-row">
            <span class="ms-shortcut-label">Paste nodes</span>
            <span class="ms-shortcut-keys"><span class="ms-shortcut-key">${mod}</span><span class="ms-shortcut-key">V</span></span>
          </div>
        </div>
        <div class="ms-shortcut-group">
          <div class="ms-shortcut-group-title">Navigation</div>
          <div class="ms-shortcut-row">
            <span class="ms-shortcut-label">Delete selected</span>
            <span class="ms-shortcut-keys"><span class="ms-shortcut-key">⌫</span></span>
          </div>
          <div class="ms-shortcut-row">
            <span class="ms-shortcut-label">Close panel / Deselect</span>
            <span class="ms-shortcut-keys"><span class="ms-shortcut-key">Esc</span></span>
          </div>
          <div class="ms-shortcut-row">
            <span class="ms-shortcut-label">Show this help</span>
            <span class="ms-shortcut-keys"><span class="ms-shortcut-key">?</span></span>
          </div>
        </div>
      </div>
    `
    this.element.appendChild(modal)

    // Close on backdrop click or close button
    modal.addEventListener("click", (e) => {
      if (e.target === modal || e.target.closest(".ms-shortcut-help-close")) {
        modal.remove()
      }
    })
  }

  // ── Undo / Redo ──
  async undo() {
    await this.#callFlowHistoryAction(this.canvasTarget.dataset.undoFlowUrl)
  }

  async redo() {
    await this.#callFlowHistoryAction(this.canvasTarget.dataset.redoFlowUrl)
  }

  // ── Zoom controls (kept for keyboard/event-based zoom) ──
  zoomIn() {
    this.canvasTarget.dispatchEvent(new CustomEvent("ms:zoom", { bubbles: true, detail: { action: "in" } }))
  }

  zoomOut() {
    this.canvasTarget.dispatchEvent(new CustomEvent("ms:zoom", { bubbles: true, detail: { action: "out" } }))
  }

  fitView() {
    this.canvasTarget.dispatchEvent(new CustomEvent("ms:zoom", { bubbles: true, detail: { action: "fit" } }))
  }

  // ── Export / Import workflow ──
  exportWorkflow() {
    const flowInput = document.getElementById("mission-flow-data")
    if (!flowInput) return
    const flowData = JSON.parse(flowInput.value || "{}")
    const gvInput = document.getElementById("mission-global-variables")
    if (gvInput) {
      try {
        flowData.global_variables = JSON.parse(gvInput.value || "[]")
      } catch { /* ignore */ }
    }
    const blob = new Blob([JSON.stringify(flowData, null, 2)], { type: "application/json" })
    const url = URL.createObjectURL(blob)
    const link = document.createElement("a")
    link.href = url
    link.download = `mission-workflow-${Date.now()}.json`
    link.click()
    URL.revokeObjectURL(url)
  }

  triggerImport() {
    if (this.hasImportFileTarget) this.importFileTarget.click()
  }

  importWorkflow(event) {
    const file = event.currentTarget.files[0]
    if (!file) return
    const reader = new FileReader()
    reader.onload = (e) => {
      try {
        const flowData = JSON.parse(e.target.result)
        if (!flowData.nodes || !flowData.edges) {
          alert("Invalid workflow file: missing nodes or edges") // eslint-disable-line no-alert
          return
        }
        if (flowData.global_variables) {
          this.#syncGlobalVariablesInput(flowData.global_variables)
        }
        this.canvasTarget.dispatchEvent(new CustomEvent("ms:set-flow-data", {
          detail: { nodes: flowData.nodes, edges: flowData.edges, skipAutosave: false },
        }))
      } catch {
        alert("Invalid JSON file") // eslint-disable-line no-alert
      }
    }
    reader.readAsText(file)
    event.currentTarget.value = ""
  }

  // ── Shortcut help modal ──
  showShortcutHelp() {
    this.#toggleShortcutHelp()
  }

  // ── Temperature slider: live display update ──
  updateTemperatureDisplay(event) {
    const value = parseFloat(event.currentTarget.value)
    if (this.hasPropTemperatureValueTarget) this.propTemperatureValueTarget.textContent = value
  }

  // ── Properties panel context menu: toggle ──
  togglePropMenu() {
    const dropdown = this.element.querySelector(".ms-prop-context-dropdown")
    if (!dropdown) return
    const isOpen = !dropdown.classList.contains("hidden")
    if (isOpen) {
      this.#closePropMenu()
    } else {
      dropdown.classList.remove("hidden")
      setTimeout(() => document.addEventListener("click", this._closePropMenuOutside, { once: true }), 0)
    }
  }

  // ── Rails → React: delete node (server-side) ──
  deleteNode() {
    if (!this.selectedNodeId) return
    this.#closePropMenu()
    this.#callNodeAction("delete_node", this.selectedNodeId)
  }

  // ── Rails → React: duplicate node (server-side) ──
  duplicateNode() {
    if (!this.selectedNodeId) return
    this.#closePropMenu()
    this.#callNodeAction("duplicate_node", this.selectedNodeId)
  }

  // ── Rails → React: auto-arrange nodes ──
  autoArrange() {
    this.canvasTarget.dispatchEvent(new CustomEvent("ms:auto-arrange"))
  }

  // ── Key-value editors: add case ──
  addCase() {
    if (!this.hasPropCasesTarget) return
    this.#appendKvRow(this.propCasesTarget, "Value", "Port name", "cases")
  }

  // ── Key-value editors: add assignment ──
  addAssignment() {
    if (!this.hasPropAssignmentsTarget) return
    this.#appendKvRow(this.propAssignmentsTarget, "Variable name", "Expression", "assignments", "expression")
  }

  // ── Key-value editors: add extraction (json_extract) ──
  addExtraction() {
    if (!this.hasPropExtractionsTarget) return
    this.#appendKvRow(this.propExtractionsTarget, "Variable name", "JSON path", "extractions")
  }

  // ── Key-value editors: generic add row ──
  addKvRow(event) {
    const listTarget = event.currentTarget.dataset.listTarget
    const listEl = this.#stimulusTargetElement(listTarget)
    if (!listEl) return

    this.#appendKvRow(
      listEl,
      event.currentTarget.dataset.keyPlaceholder || "Key",
      event.currentTarget.dataset.valuePlaceholder || "Value",
      listEl.dataset.kvType,
      event.currentTarget.dataset.valueMode || listEl.dataset.kvValueMode || "plain",
    )
  }

  // ── Output variable checklist ──
  toggleOutputVariable(event) {
    const nodeId = this.#nodeIdForSource(event.currentTarget)
    if (!nodeId || !this.hasPropOutputVariablesTarget) return
    const vars = []
    this.propOutputVariablesTarget.querySelectorAll("input[type=checkbox]:checked").forEach((cb) => {
      vars.push(cb.value)
    })
    this.#dispatchNodeUpdate({ selected_variables: vars }, nodeId)
  }

  // ── File variable checklist (multimodal attachments for LLM nodes) ──
  toggleFileVariable(event) {
    const nodeId = this.#nodeIdForSource(event.currentTarget)
    if (!nodeId || !this.hasPropFileVariablesTarget) return
    const vars = []
    this.propFileVariablesTarget.querySelectorAll("input[type=checkbox]:checked").forEach((cb) => {
      vars.push(cb.value)
    })
    this.#dispatchNodeUpdate({ file_variables: vars }, nodeId)
  }

  // ── Tool checklist (LLM node tool access) ──
  toggleToolSelection(event) {
    const nodeId = this.#nodeIdForSource(event.currentTarget)
    if (!nodeId || !this.hasPropToolIdsTarget) return
    const toolIds = []
    this.propToolIdsTarget.querySelectorAll("input[type=checkbox]:checked").forEach((cb) => {
      const toolId = Number.parseInt(cb.value, 10)
      if (Number.isInteger(toolId)) toolIds.push(toolId)
    })
    this.#dispatchNodeUpdate({ tool_ids: toolIds }, nodeId)
  }

  // ── Key-value editors: remove row ──
  removeKvRow(event) {
    const row = event.currentTarget.closest(".ms-prop-kv-row")
    const list = row.closest(".ms-prop-kv-list")
    row.remove()
    this.#syncKvList(list)
  }

  // ── Key-value editors: sync on input ──
  syncKv(event) {
    const list = event.currentTarget.closest(".ms-prop-kv-list")
    if (list) this.#syncKvList(list)
  }

  // ── Private helpers ──

  #syncKvList(listEl) {
    if (!listEl) return

    const nodeId = this.#nodeIdForSource(listEl)
    if (!nodeId) return

    const propKey = listEl.dataset.propKey || listEl.dataset.kvType
    const result = {}
    listEl.querySelectorAll(".ms-prop-kv-row").forEach((row) => {
      const key = row.querySelector(".ms-prop-kv-key")?.value?.trim()
      // Read from expression editor hidden textarea if present, else plain input
      const exprHidden = row.querySelector('[data-expression-editor-target="hidden"]')
      const value = exprHidden ? exprHidden.value?.trim() : row.querySelector(".ms-prop-kv-value")?.value?.trim()
      if (key) result[key] = value || ""
    })
    this.#dispatchNodeUpdate({ [propKey]: result }, nodeId)
  }

  #dispatchNodeUpdate(data, nodeId = this.selectedNodeId) {
    if (!nodeId) return
    this.canvasTarget.dispatchEvent(new CustomEvent("ms:update-node", {
      detail: { nodeId, data },
    }))
  }

  // Flush any unsaved input/textarea values and expression editors in the
  // properties panel before the DOM is replaced (node switch / deselect).
  #flushPendingInputs() {
    if (!this.hasNodePropertiesFrameTarget) return
    const frame = this.nodePropertiesFrameTarget
    const nodeId = this.#nodeIdForSource(frame.querySelector("[data-property-node-id]")) || this.selectedNodeId
    if (!nodeId) return

    // 1. Plain inputs/textareas with data-prop-key that save on blur
    const focused = document.activeElement
    if (focused && frame.contains(focused) && focused.dataset.propKey) {
      const key = focused.dataset.propKey
      const action = focused.dataset.action || ""
      if (action.includes("updateNodeName")) {
        // Variable name field — sanitize before saving
        const raw = focused.value || ""
        const sanitized = raw.toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_|_$/g, "")
        this.#dispatchNodeUpdate({ name: sanitized }, nodeId)
      } else {
        const value = this.#coercePropValue(focused, key)
        this.#dispatchNodeUpdate({ [key]: value }, nodeId)
      }
    }

    // 2. Expression editors — sync contenteditable → hidden textarea, then flush prop
    frame.querySelectorAll('[data-controller="expression-editor"]').forEach((wrap) => {
      const ctrl = this.application.getControllerForElementAndIdentifier(wrap, "expression-editor")
      if (ctrl) {
        ctrl._sync()
        const hidden = wrap.querySelector('[data-expression-editor-target="hidden"]')
        if (hidden && hidden.dataset.propKey) {
          this.#dispatchNodeUpdate({ [hidden.dataset.propKey]: hidden.value }, nodeId)
        }
      }
    })

    // 3. KV editors (headers, extractions, assignments, cases) — re-sync each list
    frame.querySelectorAll(".ms-prop-kv-list[data-kv-type]").forEach((list) => {
      this.#syncKvList(list)
    })

    // 4. Sub-mission input variable fields
    const subMissionContainer = frame.querySelector("[data-mission-input-fields]")
    if (subMissionContainer && subMissionContainer.querySelectorAll("[data-sub-mission-var]").length > 0) {
      const inputs = {}
      subMissionContainer.querySelectorAll("[data-sub-mission-var]").forEach((row) => {
        const key = row.dataset.subMissionVar
        const exprHidden = row.querySelector('[data-expression-editor-target="hidden"]')
        const value = exprHidden ? exprHidden.value?.trim() : ""
        if (key && value) inputs[key] = value
      })
      this.#dispatchNodeUpdate({ input_variables: inputs }, nodeId)
    }
  }

  // Handle prompt editor change event (dispatched by prompt-editor controller)
  onPromptEditorChange(event) {
    const nodeId = this.#nodeIdForSource(event.target)
    if (!nodeId) return
    const { systemPrompt, userMessages } = event.detail || {}
    const data = {}
    if (systemPrompt !== undefined) data.prompt = systemPrompt
    if (userMessages !== undefined) data.user_messages = userMessages
    this.#dispatchNodeUpdate(data, nodeId)
  }

  // Handle code editor change event (dispatched by code-editor controller)
  onCodeEditorChange(event) {
    const nodeId = this.#nodeIdForSource(event.target)
    if (!nodeId) return
    const { code } = event.detail || {}
    if (code !== undefined) this.#dispatchNodeUpdate({ code }, nodeId)
  }

  #autoResizeTextarea(textarea) {
    textarea.style.height = "auto"
    const minHeight = parseFloat(getComputedStyle(textarea).minHeight) || 0
    textarea.style.height = Math.max(textarea.scrollHeight, minHeight) + "px"
  }

  #toggleNodeDisabled(nodeId, disabled) {
    this.canvasTarget.dispatchEvent(new CustomEvent("ms:update-node", {
      detail: { nodeId, data: { disabled } },
    }))
  }

  #appendKvRow(listEl, keyPlaceholder, valuePlaceholder, kvType, valueMode = "plain") {
    listEl.dataset.kvType = kvType
    const row = document.createElement("div")
    row.className = "ms-prop-kv-row"
    const variables = this.#escapeAttr(listEl.dataset.kvVariables || "[]")

    if (valueMode === "expression") {
      row.innerHTML = `
        <input class="ms-prop-kv-key" type="text" placeholder="${keyPlaceholder}" data-action="blur->mission#syncKv">
        <span class="ms-prop-kv-sep">=</span>
        <div class="ms-expr-wrap" data-controller="expression-editor" data-expression-editor-variables-value='${variables}' data-expression-editor-multiline-value="false">
          <div class="ms-expr-editor" contenteditable="true" data-expression-editor-target="editor" data-rows="1" data-placeholder="${valuePlaceholder}"></div>
          <textarea class="hidden" data-expression-editor-target="hidden" data-action="blur->mission#syncKv input->mission#syncKv"></textarea>
          <div class="ms-expr-dropdown hidden" data-expression-editor-target="dropdown"></div>
        </div>
        <button class="ms-prop-kv-remove" type="button" data-action="click->mission#removeKvRow">
          <i class="fa-solid fa-xmark"></i>
        </button>
      `
    } else {
      row.innerHTML = `
        <input class="ms-prop-kv-key" type="text" placeholder="${keyPlaceholder}" data-action="blur->mission#syncKv">
        <span class="ms-prop-kv-sep">=</span>
        <input class="ms-prop-kv-value" type="text" placeholder="${valuePlaceholder}" data-action="blur->mission#syncKv">
        <button class="ms-prop-kv-remove" type="button" data-action="click->mission#removeKvRow">
          <i class="fa-solid fa-xmark"></i>
        </button>
      `
    }
    listEl.appendChild(row)
  }

  #stimulusTargetElement(targetName) {
    if (!targetName) return null

    const capitalized = targetName.charAt(0).toUpperCase() + targetName.slice(1)
    const hasTargetKey = `has${capitalized}Target`
    const targetKey = `${targetName}Target`
    return this[hasTargetKey] ? this[targetKey] : null
  }
  #coercePropValue(input, key) {
    const valueType = input.dataset.valueType
    if (input.type === "checkbox" || valueType === "boolean") return Boolean(input.checked)

    if (key === "temperature" || valueType === "float") {
      const parsed = Number.parseFloat(input.value)
      return Number.isFinite(parsed) ? parsed : ""
    }

    if (["max_iterations", "thinking_budget"].includes(key) || valueType === "integer") {
      const parsed = Number.parseInt(input.value, 10)
      return Number.isInteger(parsed) ? parsed : ""
    }

    return input.value
  }

  #nodeIdForSource(source) {
    if (!source) return this.selectedNodeId

    const scopedContainer = typeof source.closest === "function"
      ? source.closest("[data-property-node-id]")
      : null

    return scopedContainer?.dataset.propertyNodeId || this.selectedNodeId
  }
  async #callNodeAction(action, nodeId) {
    const canvas = this.canvasTarget
    const url = action === "delete_node" ? canvas.dataset.deleteNodeUrl : canvas.dataset.duplicateNodeUrl
    const flowData = document.getElementById(canvas.dataset.flowDataInputId)?.value || "{}"
    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content || ""
    try {
      const resp = await fetch(url, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": csrfToken,
          "Accept": "application/json",
        },
        body: JSON.stringify({ node_id: nodeId, flow_data: flowData }),
      })
      if (!resp.ok) return
      const { nodes, edges, node_errors } = await resp.json()
      // After duplicate: keep only the original node selected; new node starts unselected
      const processedNodes = action === "duplicate_node"
        ? nodes.map((n) => (n.id === nodeId ? n : { ...n, selected: false }))
        : nodes
      canvas.dispatchEvent(new CustomEvent("ms:set-flow-data", { detail: { nodes: processedNodes, edges } }))
      if (node_errors !== undefined) this.#applyNodeErrors(node_errors)
      if (action === "delete_node" && nodeId === this.selectedNodeId) {
        this.onNodeDeselected()
      }
    } catch {
      // network error \u2014 ignore
    }
  }

  #closePropMenu() {
    this.element.querySelector(".ms-prop-context-dropdown")?.classList.add("hidden")
  }

  #showAutosaveError() {
    document.dispatchEvent(new CustomEvent("toast:show", {
      detail: { type: "error", text: "Failed to save workflow. Please try again." },
    }))
  }

  #updateUndoRedoState(canUndo, canRedo) {
    this._canUndo = !!canUndo
    this._canRedo = !!canRedo
    this.#broadcastUndoRedoState()
  }

  #broadcastUndoRedoState() {
    this.canvasTarget.dispatchEvent(new CustomEvent("ms:undo-redo-state", {
      detail: { canUndo: this._canUndo, canRedo: this._canRedo },
    }))
  }

  async #callFlowHistoryAction(url) {
    if (!url) return
    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content || ""
    try {
      const resp = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-CSRF-Token": csrfToken, "Accept": "application/json" },
      })
      if (!resp.ok) return
      const { nodes, edges, can_undo, can_redo, node_errors, global_variables } = await resp.json()
      this.canvasTarget.dispatchEvent(new CustomEvent("ms:set-flow-data", { detail: { nodes, edges, skipAutosave: true } }))
      this.#updateUndoRedoState(can_undo, can_redo)
      if (node_errors !== undefined) this.#applyNodeErrors(node_errors)
      if (global_variables !== undefined) this.#syncGlobalVariablesInput(global_variables)
      this.#refreshPropertiesAfterHistoryChange(nodes)
    } catch {
      // network error — ignore
    }
  }



  // After an undo/redo the canvas nodes are replaced. If the properties panel is open,
  // re-fetch the server-rendered properties, or close the panel if the node no longer exists.
  #refreshPropertiesAfterHistoryChange(nodes) {
    if (!this.selectedNodeId) return
    const updated = nodes.find((n) => n.id === this.selectedNodeId)
    if (updated) {
      // Re-fetch the Turbo Frame to reflect updated node data
      if (this.hasNodePropertiesFrameTarget) {
        const baseUrl = this.nodePropertiesFrameTarget.dataset.nodePropertiesUrl
        if (baseUrl) {
          this.nodePropertiesFrameTarget.src = `${baseUrl}?node_id=${encodeURIComponent(this.selectedNodeId)}`
        }
      }
    } else {
      this.onNodeDeselected()
    }
  }

  #applyNodeErrors(errors) {
    const oldErrors = this._nodeErrors || {}
    this._nodeErrors = errors || {}
    this.canvasTarget.dataset.nodeErrors = JSON.stringify(this._nodeErrors)
    this.canvasTarget.dispatchEvent(new CustomEvent("ms:set-node-errors", { detail: this._nodeErrors }))

    // Refresh properties panel validation banner if selected node's error state changed
    if (this.selectedNodeId && this.hasNodePropertiesFrameTarget) {
      const oldNodeErrors = oldErrors[this.selectedNodeId]
      const newNodeErrors = this._nodeErrors[this.selectedNodeId]
      const oldStr = JSON.stringify(oldNodeErrors || [])
      const newStr = JSON.stringify(newNodeErrors || [])
      if (oldStr !== newStr) {
        const baseUrl = this.nodePropertiesFrameTarget.dataset.nodePropertiesUrl
        if (baseUrl) {
          this.nodePropertiesFrameTarget.src = `${baseUrl}?node_id=${encodeURIComponent(this.selectedNodeId)}`
        }
      }
    }
  }

  // ── Flow update observer (Turbo Stream broadcasts from mission designer agent) ──

  #startFlowUpdateObserver() {
    if (!this.hasFlowUpdatesTarget) return
    this._flowUpdateObserver = new MutationObserver((mutations) => {
      for (const mutation of mutations) {
        for (const node of mutation.addedNodes) {
          if (node.nodeType === Node.ELEMENT_NODE) this.#handleFlowUpdate(node)
        }
      }
    })
    this._flowUpdateObserver.observe(this.flowUpdatesTarget, { childList: true })
  }

  #handleFlowUpdate(el) {
    try {
      if (el.dataset.arrange === "true") {
        // Cancel pending refresh debounce and abort in-flight refresh AJAX
        clearTimeout(this._flowRefreshTimer)
        this._pendingRefreshAbort?.abort()

        // Fetch latest flow data, update React with preserved positions, then arrange.
        // We preserve client-side positions so new server nodes don't flash at raw
        // auto_x/auto_y coordinates before ELK repositions everything.
        const flowDataUrl = this.canvasTarget.dataset.flowDataUrl
        if (flowDataUrl) {
          fetch(flowDataUrl, {
            headers: { "Accept": "application/json", "X-Requested-With": "XMLHttpRequest" },
            credentials: "same-origin",
          })
            .then(r => r.json())
            .then(data => {
              // Update nodes/edges — skip camera follow (arrange will handle it),
              // preserve all client positions so nothing visually jumps, and skip
              // autosave since this is a server-driven update.
              this.canvasTarget.dispatchEvent(new CustomEvent("ms:set-flow-data", {
                detail: {
                  nodes: data.nodes || [],
                  edges: data.edges || [],
                  skipAutosave: true,
                  skipCameraFollow: true,
                  preservePositions: true,
                },
              }))
              this.#applyNodeErrors(data.node_errors || {})
              this.#updateUndoRedoState(data.can_undo === true, data.can_redo === true)
              if (data.global_variables !== undefined) this.#syncGlobalVariablesInput(data.global_variables)

              // Wait two frames for React to commit the node update AND measure
              // the new nodes (React Flow needs one frame to render, another to
              // run ResizeObserver and populate `measured` dimensions).
              requestAnimationFrame(() => {
                requestAnimationFrame(() => {
                  this.canvasTarget.dispatchEvent(new CustomEvent("ms:auto-arrange", {
                    bubbles: true, detail: { source: "ai" },
                  }))
                })
              })
            })
            .catch(() => { /* fetch failed — ignore */ })
        }
        el.remove()
        return
      }

      // Debounce refresh AJAX — rapid signals (add_node + manage_edges) collapse
      // into a single fetch of the latest server state.
      // Use 300ms debounce to group rapid AI tool calls (add + connect often
      // fire within ~100ms of each other).
      clearTimeout(this._flowRefreshTimer)
      this._pendingRefreshAbort?.abort()

      const controller = new AbortController()
      this._pendingRefreshAbort = controller

      this._flowRefreshTimer = setTimeout(() => {
        const flowDataUrl = this.canvasTarget.dataset.flowDataUrl
        if (!flowDataUrl) return

        fetch(flowDataUrl, {
          headers: { "Accept": "application/json", "X-Requested-With": "XMLHttpRequest" },
          credentials: "same-origin",
          signal: controller.signal,
        })
          .then(r => r.json())
          .then(data => {
            this.canvasTarget.dispatchEvent(new CustomEvent("ms:set-flow-data", {
              detail: { nodes: data.nodes || [], edges: data.edges || [], skipAutosave: true, preservePositions: true },
            }))
            this.#applyNodeErrors(data.node_errors || {})
            this.#updateUndoRedoState(data.can_undo === true, data.can_redo === true)
            if (data.global_variables !== undefined) this.#syncGlobalVariablesInput(data.global_variables)
          })
          .catch(() => { /* fetch failed or aborted — ignore */ })
      }, 300)

      el.remove()
    } catch {
      // malformed broadcast — ignore
    }
  }

  #mergeGlobalVariables(flowDataStr) {
    try {
      const flow = JSON.parse(flowDataStr)
      const gvInput = document.getElementById("mission-global-variables")
      if (gvInput) {
        flow.global_variables = JSON.parse(gvInput.value || "[]")
      }
      return JSON.stringify(flow)
    } catch {
      return flowDataStr
    }
  }

  #syncGlobalVariablesInput(vars) {
    const input = document.getElementById("mission-global-variables")
    if (input) input.value = JSON.stringify(vars || [])
    document.dispatchEvent(new CustomEvent("ms:global-variables-changed"))
  }
}
