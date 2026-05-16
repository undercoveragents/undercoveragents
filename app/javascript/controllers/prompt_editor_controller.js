import { Controller } from "@hotwired/stimulus"
import OverType, { toolbarButtons } from "overtype"

// Reusable prompt editor component with OverType markdown editing,
// variable insertion dropdown, and maximize dialog.
export default class extends Controller {
  static values = {
    compact: { type: Boolean, default: false },
    showVariables: { type: Boolean, default: false },
    showUserMessages: { type: Boolean, default: true },
    variables: { type: Array, default: [] },
  }

  static targets = [
    "systemEditor",
    "systemInput",
    "userMessagesContainer",
    "variablesDropdown",
    "maximizeDialog",
    "maximizeEditorWrap",
  ]

  connect() {
    this._editors = {}
    this._maximizeEditor = null
    this._userCounter = 0
    this._activeEditTarget = null
    this._lastFocusedEditorKey = "system"
    this._manualTheme = localStorage.getItem("editor-theme") || null

    this.element.promptEditor = this

    this._initSystemEditor()
    this._initExistingUserEditors()
    this._observeThemeChanges()
    this._rebuildVariableDropdowns()
    this._observeVisibility()
  }

  disconnect() {
    this._destroyAllEditors()
    if (this._maximizeEditor) {
      try { this._maximizeEditor.destroy() } catch { /* ignore */ }
      this._maximizeEditor = null
    }
    if (this._themeObserver) {
      this._themeObserver.disconnect()
      this._themeObserver = null
    }
    if (this._visibilityObserver) {
      this._visibilityObserver.disconnect()
      this._visibilityObserver = null
    }
    this.element.promptEditor = null
  }

  // ── Public API (for programmatic access from other controllers) ──

  getSystemPrompt() {
    const editor = this._editors.system
    return editor ? editor.getValue() : (this.systemEditorTarget.querySelector("textarea")?.value || "")
  }

  setSystemPrompt(value) {
    const editor = this._editors.system
    if (editor) {
      editor.setValue(value || "")
    } else {
      const ta = this.systemEditorTarget.querySelector("textarea")
      if (ta) ta.value = value || ""
    }
    this._syncSystemInput()
  }

  getUserMessages() {
    const messages = []
    this._eachUserEditor((editor, el) => {
      messages.push(editor ? editor.getValue() : (el.querySelector("textarea")?.value || ""))
    })
    return messages
  }

  setUserMessages(messages) {
    // Clear existing user messages
    if (this.hasUserMessagesContainerTarget) {
      this.userMessagesContainerTarget.innerHTML = ""
    }
    // Destroy user editors
    Object.keys(this._editors).forEach(key => {
      if (key.startsWith("user_")) {
        this._editors[key]?.destroy()
        delete this._editors[key]
      }
    })
    this._userCounter = 0
    // Add new ones
    if (messages && messages.length > 0) {
      messages.forEach(msg => this._addUserMessage(msg))
    }
  }

  setVariables(vars) {
    this.variablesValue = vars || []
  }

  // ── Actions ──

  toggleTheme() {
    const current = this._activeTheme()
    this._manualTheme = current === "cave" ? "light" : "dark"
    localStorage.setItem("editor-theme", this._manualTheme)
    this._applyTheme(this._manualTheme)
  }

  addUserMessage() {
    this._addUserMessage("")
    this._dispatchChange()
  }

  removeUserMessage(event) {
    const messageEl = event.currentTarget.closest("[data-user-message-id]")
    if (!messageEl) return
    const id = messageEl.dataset.userMessageId
    this._editors[`user_${id}`]?.destroy()
    delete this._editors[`user_${id}`]
    messageEl.remove()
    this._renumberUserMessages()
    this._dispatchChange()
  }

  insertVariable(event) {
    const varName = event.currentTarget.dataset.variable
    if (!varName) return

    // Determine target editor from the message block containing the dropdown
    const messageEl = event.currentTarget.closest("[data-message-role]")
    let editorKey = this._lastFocusedEditorKey || "system"
    if (messageEl) {
      const role = messageEl.dataset.messageRole
      const msgId = messageEl.dataset.userMessageId
      editorKey = role === "user" && msgId != null ? `user_${msgId}` : role
    }
    const editor = this._editors[editorKey] || this._editors.system
    if (editor) {
      const ta = this._getTextarea(editor)
      if (ta) {
        const insertion = `{{${varName}}}`
        const start = ta.selectionStart
        const end = ta.selectionEnd
        const text = ta.value
        ta.value = text.slice(0, start) + insertion + text.slice(end)
        ta.selectionStart = ta.selectionEnd = start + insertion.length
        ta.focus()
        ta.dispatchEvent(new Event("input", { bubbles: true }))
        this._syncAllInputs()
        this._dispatchChange()
      }
    }
    // Close the dropdown
    this._closeAllVariableDropdowns()
  }

  toggleVariablesDropdown(event) {
    event.stopPropagation()
    const btn = event.currentTarget
    const dropdown = btn.closest(".pe-var-dropdown-wrap")?.querySelector(".pe-var-dropdown")
    if (!dropdown) return
    const isOpen = !dropdown.classList.contains("hidden")
    this._closeAllVariableDropdowns()
    if (!isOpen) {
      // Position dropdown using fixed coordinates to escape overflow clipping
      const rect = btn.getBoundingClientRect()
      dropdown.style.position = "fixed"
      dropdown.style.top = `${rect.bottom + 4}px`
      dropdown.style.right = `${document.documentElement.clientWidth - rect.right}px`
      dropdown.style.left = "auto"
      dropdown.classList.remove("hidden")
      // Close on next click anywhere
      setTimeout(() => {
        document.addEventListener("click", this._boundCloseDropdowns ||= () => this._closeAllVariableDropdowns(), { once: true })
      }, 0)
    }
  }

  _closeAllVariableDropdowns() {
    this.element.querySelectorAll(".pe-var-dropdown").forEach(d => d.classList.add("hidden"))
  }

  // ── Maximize ──

  openMaximize(event) {
    const messageEl = event.currentTarget.closest("[data-message-role]")
    const role = messageEl?.dataset.messageRole || "system"
    const msgId = messageEl?.dataset.userMessageId
    this._activeEditTarget = { role, id: msgId }

    const content = this._getEditorContent(role, msgId)

    // Update dialog title
    const titleEl = this.maximizeDialogTarget.querySelector(".dialog-title")
    if (titleEl) {
      titleEl.textContent = role === "system" ? "System Prompt" : `User Message${msgId ? ` #${parseInt(msgId) + 1}` : ""}`
    }

    // Update variables bar in maximize dialog
    this._updateMaximizeVariablesBar()

    this.maximizeDialogTarget.showModal()

    // Init OverType inside maximize after dialog is open (needs visible DOM)
    requestAnimationFrame(() => this._initMaximizeEditor(content, this.showVariablesValue))
  }

  closeMaximize() {
    this._destroyMaximizeEditor()
    this.maximizeDialogTarget.close()
    this._activeEditTarget = null
  }

  saveMaximize() {
    if (!this._activeEditTarget) return
    const content = this._maximizeEditor ? this._maximizeEditor.getValue() : ""
    const { role, id } = this._activeEditTarget

    if (role === "system") {
      this.setSystemPrompt(content)
    } else {
      const editorKey = `user_${id}`
      const editor = this._editors[editorKey]
      if (editor) {
        editor.setValue(content)
      } else {
        const container = this.userMessagesContainerTarget?.querySelector(`[data-user-message-id="${id}"]`)
        const ta = container?.querySelector("textarea")
        if (ta) ta.value = content
      }
      this._syncUserInput(id)
    }

    this._dispatchChange()
    this.closeMaximize()
  }

  maximizeBackdropClick(event) {
    if (event.target === this.maximizeDialogTarget) {
      this.closeMaximize()
    }
  }

  insertVariableInMaximize(event) {
    const varName = event.currentTarget.dataset.variable
    if (!varName || !this._maximizeEditor) return
    const ta = this._getTextarea(this._maximizeEditor)
    if (!ta) return
    const insertion = `{{${varName}}}`
    const start = ta.selectionStart
    const end = ta.selectionEnd
    ta.value = ta.value.slice(0, start) + insertion + ta.value.slice(end)
    ta.selectionStart = ta.selectionEnd = start + insertion.length
    ta.focus()
    ta.dispatchEvent(new Event("input", { bubbles: true }))
  }

  // ── Editor focus tracking ──

  editorFocused(event) {
    const editorWrap = event.currentTarget.closest("[data-editor-key]")
    if (editorWrap) {
      this._lastFocusedEditorKey = editorWrap.dataset.editorKey
    }
  }

  // ── Private: Editor initialization ──

  _initSystemEditor() {
    if (!this.hasSystemEditorTarget) return
    try {
      const [editor] = new OverType(this.systemEditorTarget, this._editorOptions("system"))
      this._editors.system = editor
      // Trim leading/trailing whitespace from textContent extraction
      const val = editor.getValue()
      if (val !== val.trim()) editor.setValue(val.trim())
    } catch {
      // OverType failed — fall back to plain textarea (already in DOM)
    }
  }

  _initExistingUserEditors() {
    if (!this.hasUserMessagesContainerTarget) return
    const userEditors = this.userMessagesContainerTarget.querySelectorAll("[data-editor-key]")
    userEditors.forEach(el => {
      const key = el.dataset.editorKey
      const id = key.replace("user_", "")
      const counter = parseInt(id, 10)
      if (counter >= this._userCounter) this._userCounter = counter + 1
      try {
        const [editor] = new OverType(el, this._editorOptions(key))
        this._editors[key] = editor
        const val = editor.getValue()
        if (val !== val.trim()) editor.setValue(val.trim())
      } catch {
        // fall back to textarea
      }
    })
  }

  _currentTheme() {
    if (this._manualTheme) {
      return this._manualTheme === "dark" ? "cave" : "solar"
    }
    return document.documentElement.classList.contains("dark") ? "cave" : "solar"
  }

  _activeTheme() {
    return this._currentTheme()
  }

  _applyTheme(theme) {
    const mapped = theme === "dark" ? "cave" : theme === "light" ? "solar" : theme
    Object.values(this._editors).forEach(editor => {
      try { editor.setTheme(mapped) } catch { /* ignore */ }
    })
    if (this._maximizeEditor) {
      try { this._maximizeEditor.setTheme(mapped) } catch { /* ignore */ }
    }
  }

  _buildToolbarButtons(overrides = {}) {
    const buttons = [
      toolbarButtons.bold,
      toolbarButtons.italic,
      toolbarButtons.code,
      toolbarButtons.separator,
      toolbarButtons.bulletList,
      toolbarButtons.orderedList,
    ]
    if (overrides.showVarButton && this.showVariablesValue && this.variablesValue.length > 0) {
      buttons.push(toolbarButtons.separator)
      buttons.push({
        name: "insertVariable",
        icon: '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M8 3H7a2 2 0 0 0-2 2v5a2 2 0 0 1-2 2 2 2 0 0 1 2 2v5a2 2 0 0 0 2 2h1"/><path d="M16 3h1a2 2 0 0 1 2 2v5a2 2 0 0 0 2 2 2 2 0 0 0-2 2v5a2 2 0 0 1-2 2h-1"/></svg>',
        title: "Insert variable",
        action: ({ editor }) => {
          this._showToolbarVariableDropdown(editor)
        },
      })
    }
    return buttons
  }

  _showToolbarVariableDropdown(editor) {
    // Find the toolbar button and position dropdown via portal (document.body)
    const container = editor.container
    const btn = container?.querySelector('[data-button="insertVariable"]')
    if (!btn) return

    // Remove existing dropdown if any
    const existing = document.querySelector(".pe-toolbar-var-dropdown")
    if (existing) { existing.remove(); return }

    const dropdown = document.createElement("div")
    dropdown.className = "pe-toolbar-var-dropdown"
    this.variablesValue.forEach(v => {
      const name = typeof v === "string" ? v : v.name
      const item = document.createElement("button")
      item.type = "button"
      item.className = "pe-var-dropdown-item"
      item.textContent = `{{${name}}}`
      item.addEventListener("click", (e) => {
        e.preventDefault()
        e.stopPropagation()
        const ta = editor.textarea
        if (ta) {
          const insertion = `{{${name}}}`
          const start = ta.selectionStart
          const end = ta.selectionEnd
          ta.value = ta.value.slice(0, start) + insertion + ta.value.slice(end)
          ta.selectionStart = ta.selectionEnd = start + insertion.length
          ta.focus()
          ta.dispatchEvent(new Event("input", { bubbles: true }))
        }
        dropdown.remove()
      })
      dropdown.appendChild(item)
    })

    // Portal: append to nearest dialog (top-layer) or body, with fixed positioning
    const dialog = btn.closest("dialog[open]")
    const portalRoot = dialog || document.body
    const rect = btn.getBoundingClientRect()
    dropdown.style.top = `${rect.bottom + 4}px`
    dropdown.style.left = `${rect.left}px`
    portalRoot.appendChild(dropdown)

    const closeHandler = (e) => {
      if (!dropdown.contains(e.target) && !btn.contains(e.target)) {
        dropdown.remove()
        document.removeEventListener("click", closeHandler)
      }
    }
    setTimeout(() => document.addEventListener("click", closeHandler), 0)
  }

  _editorOptions(key, overrides = {}) {
    const isCompact = this.compactValue && !overrides.fullSize
    return {
      toolbar: !isCompact,
      toolbarButtons: isCompact ? [] : this._buildToolbarButtons(overrides),
      theme: this._currentTheme(),
      fontSize: isCompact ? "12px" : "13px",
      fontFamily: "ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace",
      lineHeight: 1.6,
      autoResize: true,
      minHeight: overrides.minHeight || (isCompact ? "60px" : "130px"),
      maxHeight: overrides.maxHeight || (isCompact ? "300px" : "600px"),
      placeholder: overrides.placeholder || "Enter your prompt…",
      spellcheck: true,
      onChange: overrides.onChange || (() => {
        this._syncInputForKey(key)
        this._dispatchChange()
      }),
    }
  }

  _observeThemeChanges() {
    this._themeObserver = new MutationObserver(() => {
      if (this._manualTheme) return
      const theme = this._currentTheme()
      Object.values(this._editors).forEach(editor => {
        try { editor.setTheme(theme) } catch { /* ignore */ }
      })
      if (this._maximizeEditor) {
        try { this._maximizeEditor.setTheme(theme) } catch { /* ignore */ }
      }
    })
    this._themeObserver.observe(document.documentElement, { attributes: true, attributeFilter: ["class"] })
  }

  _observeVisibility() {
    // When the editor container becomes visible (e.g. properties panel opens),
    // trigger auto-resize on all editors since scrollHeight is 0 while hidden.
    this._visibilityObserver = new IntersectionObserver((entries) => {
      entries.forEach(entry => {
        if (entry.isIntersecting) {
          Object.values(this._editors).forEach(editor => {
            try { editor._updateAutoHeight?.() } catch { /* ignore */ }
          })
        }
      })
    })
    this._visibilityObserver.observe(this.element)
  }

  _addUserMessage(content) {
    if (!this.hasUserMessagesContainerTarget) return
    const id = this._userCounter++
    const num = this.userMessagesContainerTarget.children.length + 1
    const isCompact = this.compactValue

    const messageEl = document.createElement("div")
    messageEl.className = "pe-message"
    messageEl.dataset.userMessageId = id
    messageEl.dataset.messageRole = "user"

    // Build actions HTML — always include variable wrapper if showVariables enabled
    let actionsHtml = ""
    if (this.showVariablesValue) actionsHtml += this._variableDropdownHtml()
    actionsHtml += `<button type="button" class="pe-action-btn" title="Maximize" data-action="click->prompt-editor#openMaximize"><i class="fa-solid fa-expand"></i></button>`
    actionsHtml = `<button type="button" class="pe-action-btn pe-action-btn-danger" title="Remove message" data-action="click->prompt-editor#removeUserMessage"><i class="fa-solid fa-trash-can"></i></button>` + actionsHtml

    messageEl.innerHTML =
      `<div class="pe-message-header">` +
        `<div class="pe-message-header-left">` +
          `<span class="pe-role-badge pe-role-user"><i class="fa-solid fa-user"></i> User</span>` +
          `<span class="pe-msg-counter">#${num}</span>` +
        `</div>` +
        `<div class="pe-message-header-actions">${actionsHtml}</div>` +
      `</div>` +
      `<div class="pe-editor-wrap${isCompact ? " pe-editor-wrap--compact" : ""}" data-editor-key="user_${id}" data-action="focus->prompt-editor#editorFocused">` +
        `<textarea class="pe-textarea${isCompact ? " pe-textarea--compact" : ""}" placeholder="Enter user message…"></textarea>` +
      `</div>` +
      `<input type="hidden" data-user-input-id="${id}">`

    this.userMessagesContainerTarget.appendChild(messageEl)

    // Initialize OverType on the new editor
    const editorWrap = messageEl.querySelector("[data-editor-key]")
    try {
      const [editor] = new OverType(editorWrap, this._editorOptions(`user_${id}`))
      this._editors[`user_${id}`] = editor
      if (content) editor.setValue(content)
    } catch {
      // textarea remains as fallback
      if (content) editorWrap.querySelector("textarea").value = content
    }
  }

  _variableDropdownHtml() {
    const vars = this.variablesValue || []
    const hidden = vars.length === 0 ? " hidden" : ""
    let items = ""
    vars.forEach(v => {
      const name = typeof v === "string" ? v : v.name
      items += `<button type="button" class="pe-var-dropdown-item" data-variable="${this._escapeHtml(name)}" data-action="click->prompt-editor#insertVariable">{{${this._escapeHtml(name)}}}</button>`
    })
    return (
      `<div class="pe-var-dropdown-wrap${hidden}">` +
        `<button type="button" class="pe-action-btn pe-action-btn-var" title="Insert variable" data-action="click->prompt-editor#toggleVariablesDropdown"><i class="fa-solid fa-code"></i></button>` +
        `<div class="pe-var-dropdown hidden">${items}</div>` +
      `</div>`
    )
  }

  _renumberUserMessages() {
    if (!this.hasUserMessagesContainerTarget) return
    const messages = this.userMessagesContainerTarget.querySelectorAll("[data-user-message-id]")
    messages.forEach((el, idx) => {
      const counter = el.querySelector(".pe-msg-counter")
      if (counter) counter.textContent = `#${idx + 1}`
    })
  }

  // ── Private: Value sync ──

  _syncSystemInput() {
    if (!this.hasSystemInputTarget) return
    const editor = this._editors.system
    const value = editor ? editor.getValue() : (this.systemEditorTarget?.querySelector("textarea")?.value || "")
    this.systemInputTarget.value = value
  }

  _syncUserInput(id) {
    const container = this.userMessagesContainerTarget?.querySelector(`[data-user-message-id="${id}"]`)
    const hiddenInput = container?.querySelector(`[data-user-input-id="${id}"]`)
    if (!hiddenInput) return
    const editor = this._editors[`user_${id}`]
    const value = editor ? editor.getValue() : (container.querySelector("textarea")?.value || "")
    hiddenInput.value = value
  }

  _syncInputForKey(key) {
    if (key === "system") {
      this._syncSystemInput()
    } else {
      const id = key.replace("user_", "")
      this._syncUserInput(id)
    }
  }

  _syncAllInputs() {
    this._syncSystemInput()
    if (this.hasUserMessagesContainerTarget) {
      this.userMessagesContainerTarget.querySelectorAll("[data-user-message-id]").forEach(el => {
        this._syncUserInput(el.dataset.userMessageId)
      })
    }
  }

  // ── Private: Content access ──

  _getEditorContent(role, id) {
    if (role === "system") {
      return this.getSystemPrompt()
    }
    const editor = this._editors[`user_${id}`]
    if (editor) return editor.getValue()
    const container = this.userMessagesContainerTarget?.querySelector(`[data-user-message-id="${id}"]`)
    return container?.querySelector("textarea")?.value || ""
  }

  _getTextarea(editor) {
    // OverType wraps a real textarea element — find it
    try {
      const container = editor.element || editor._el
      return container?.querySelector("textarea") || null
    } catch {
      return null
    }
  }

  // ── Private: Maximize editor ──

  _initMaximizeEditor(content, showVarButton = false) {
    this._destroyMaximizeEditor()
    if (!this.hasMaximizeEditorWrapTarget) return
    // Clear any leftover textarea content
    const ta = this.maximizeEditorWrapTarget.querySelector("textarea")
    if (ta) ta.value = content || ""
    try {
      const [editor] = new OverType(this.maximizeEditorWrapTarget, this._editorOptions("maximize", {
        fullSize: true,
        minHeight: "300px",
        maxHeight: "none",
        showVarButton,
        onChange: () => {},
      }))
      this._maximizeEditor = editor
      if (content) editor.setValue(content)
    } catch {
      // fallback — textarea is already populated
    }
  }

  _destroyMaximizeEditor() {
    if (this._maximizeEditor) {
      try { this._maximizeEditor.destroy() } catch { /* ignore */ }
      this._maximizeEditor = null
    }
  }

  // ── Private: Variables ──

  _updateMaximizeVariablesBar() {
    // No-op — variables are now in the maximize editor toolbar
  }

  _rebuildVariableDropdowns() {
    // Update all variable dropdown menus in all message headers
    this.element.querySelectorAll(".pe-var-dropdown").forEach(dropdown => {
      dropdown.innerHTML = ""
      this.variablesValue.forEach(v => {
        const name = typeof v === "string" ? v : v.name
        const isMaximize = !!dropdown.closest(".pe-maximize-dialog")
        const action = isMaximize ? "click->prompt-editor#insertVariableInMaximize" : "click->prompt-editor#insertVariable"
        const btn = document.createElement("button")
        btn.type = "button"
        btn.className = "pe-var-dropdown-item"
        btn.dataset.variable = name
        btn.dataset.action = action
        btn.textContent = `{{${name}}}`
        dropdown.appendChild(btn)
      })
    })
    // Show/hide variable buttons based on whether variables exist
    this.element.querySelectorAll(".pe-var-dropdown-wrap").forEach(wrap => {
      wrap.classList.toggle("hidden", this.variablesValue.length === 0)
    })
  }

  // ── Private: Cleanup ──

  _destroyAllEditors() {
    Object.values(this._editors).forEach(editor => {
      try { editor.destroy() } catch { /* ignore */ }
    })
    this._editors = {}
  }

  _eachUserEditor(callback) {
    if (!this.hasUserMessagesContainerTarget) return
    this.userMessagesContainerTarget.querySelectorAll("[data-user-message-id]").forEach(el => {
      const id = el.dataset.userMessageId
      const editor = this._editors[`user_${id}`]
      callback(editor, el, id)
    })
  }

  // ── Private: Events ──

  _dispatchChange() {
    this.dispatch("change", {
      detail: {
        systemPrompt: this.getSystemPrompt(),
        userMessages: this.getUserMessages(),
      },
    })
  }

  // ── Private: Utilities ──

  _escapeHtml(str) {
    const div = document.createElement("div")
    div.textContent = str || ""
    return div.innerHTML
  }

  // ── Stimulus: react to variables value change ──
  variablesValueChanged() {
    this._rebuildVariableDropdowns()
  }
}
