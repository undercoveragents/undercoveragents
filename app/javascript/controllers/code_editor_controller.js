import { Controller } from "@hotwired/stimulus"

const ACE_THEME_MAP = {
  "github-dark": "ace/theme/github_dark",
  "github-light": "ace/theme/github_light_default",
}

// Dynamically load ace.js from /ace/ once, returns a promise.
let acePromise = null
function loadAce() {
  if (window.ace) return Promise.resolve(window.ace)
  if (acePromise) return acePromise
  acePromise = new Promise((resolve, reject) => {
    const script = document.createElement("script")
    script.src = "/ace/ace.js"
    script.onload = () => {
      window.ace.config.set("basePath", "/ace")
      resolve(window.ace)
    }
    script.onerror = () => reject(new Error("Failed to load Ace editor"))
    document.head.appendChild(script)
  })
  return acePromise
}

// Code editor component using Ace Editor with
// maximize dialog and dark/light theme sync.
export default class extends Controller {
  static values = {
    inputVariables: { type: Array, default: [] },
    placeholder: { type: String, default: "# Write your Ruby code here…" },
  }

  static targets = [
    "editorWrap",
    "hiddenInput",
    "maximizeDialog",
    "maximizeEditorWrap",
    "themeToggle",
  ]

  connect() {
    this._editor = null
    this._maximizeEditor = null
    this._manualTheme = localStorage.getItem("editor-theme") ? (localStorage.getItem("editor-theme") === "dark" ? "github-dark" : "github-light") : null

    this.element.codeEditor = this

    this._initEditor()
    this._observeThemeChanges()
  }

  disconnect() {
    this._destroyEditor()
    this._destroyMaximizeEditor()
    if (this._themeObserver) {
      this._themeObserver.disconnect()
      this._themeObserver = null
    }
    this.element.codeEditor = null
    this._manualTheme = null
  }

  // ── Public API ──

  getValue() {
    return this._editor?.getValue() || ""
  }

  setValue(value) {
    if (this._editor) {
      this._editor.setValue(value || "", -1)
    }
    this._syncHiddenInput()
  }

  // ── Theme toggle ──

  toggleTheme() {
    const current = this._activeTheme()
    this._manualTheme = current === "github-dark" ? "github-light" : "github-dark"
    localStorage.setItem("editor-theme", this._manualTheme === "github-dark" ? "dark" : "light")
    this._applyTheme(this._manualTheme)
  }

  // ── Maximize ──

  openMaximize() {
    const content = this.getValue()
    this.maximizeDialogTarget.showModal()
    requestAnimationFrame(() => this._initMaximizeEditor(content))
  }

  closeMaximize() {
    this._destroyMaximizeEditor()
    this.maximizeDialogTarget.close()
  }

  saveMaximize() {
    const content = this._maximizeEditor?.getValue() || ""
    this.setValue(content)
    this._dispatchChange()
    this.closeMaximize()
  }

  maximizeBackdropClick(event) {
    if (event.target === this.maximizeDialogTarget) {
      this.closeMaximize()
    }
  }

  // ── Private: Editor initialization ──

  async _initEditor() {
    const host = this._editorWrapElement()
    if (!host) return
    await loadAce()
    if (!this.element.isConnected) return

    const initialValue = this.hasHiddenInputTarget ? this.hiddenInputTarget.value : ""
    this._editor = this._createAceEditor(host, initialValue)
  }

  _destroyEditor() {
    if (this._editor) {
      this._editor.destroy()
      this._editor = null
    }
  }

  async _initMaximizeEditor(content) {
    this._destroyMaximizeEditor()
    if (!this.hasMaximizeEditorWrapTarget) return
    await loadAce()
    if (!this.element.isConnected) return

    this._maximizeEditor = this._createAceEditor(this.maximizeEditorWrapTarget, content || "")
  }

  _destroyMaximizeEditor() {
    if (this._maximizeEditor) {
      this._maximizeEditor.destroy()
      this._maximizeEditor = null
    }
  }

  _createAceEditor(container, value) {
    const editor = window.ace.edit(container, {
      mode: "ace/mode/ruby",
      theme: ACE_THEME_MAP[this._activeTheme()],
      value: value,
      showLineNumbers: true,
      showGutter: true,
      wrap: false,
      tabSize: 2,
      useSoftTabs: true,
      fontSize: "0.75rem",
      showPrintMargin: false,
      highlightActiveLine: true,
    })

    editor.session.on("change", () => {
      this._syncHiddenInput()
      this._dispatchChange()
    })

    return editor
  }

  _currentTheme() {
    return document.documentElement.classList.contains("dark") ? "github-dark" : "github-light"
  }

  _activeTheme() {
    return this._manualTheme || this._currentTheme()
  }

  _applyTheme(theme) {
    const aceTheme = ACE_THEME_MAP[theme]
    if (this._editor) this._editor.setTheme(aceTheme)
    if (this._maximizeEditor) this._maximizeEditor.setTheme(aceTheme)
  }

  _observeThemeChanges() {
    this._themeObserver = new MutationObserver(() => {
      if (this._manualTheme) return
      const theme = this._currentTheme()
      this._applyTheme(theme)
    })
    this._themeObserver.observe(document.documentElement, { attributes: true, attributeFilter: ["class"] })
  }

  _editorWrapElement() {
    return this.element.querySelector('[data-code-editor-target="editorWrap"]')
  }

  _syncHiddenInput() {
    if (this.hasHiddenInputTarget) {
      this.hiddenInputTarget.value = this.getValue()
    }
  }

  _dispatchChange() {
    this.dispatch("change", {
      detail: { code: this.getValue() },
    })
  }
}
