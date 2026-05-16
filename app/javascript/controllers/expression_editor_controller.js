import { Controller } from "@hotwired/stimulus"

/**
 * Expression Editor — contenteditable input with @-mention variable insertion.
 *
 * Renders variable references as inline badges while storing the underlying
 * {{variable}} syntax in a hidden textarea. Typing "@" opens a filtered
 * dropdown of available upstream variables.
 *
 * Usage (via shared/_expression_editor partial):
 *   data-controller="expression-editor"
 *   data-expression-editor-variables-value='[{"name":"x","source":"node1"}]'
 *   data-expression-editor-multiline-value="true"
 */
export default class extends Controller {
  static values = {
    variables: { type: Array, default: [] },
    multiline: { type: Boolean, default: true },
  }

  static targets = ["editor", "hidden", "dropdown"]

  // ── Lifecycle ──

  connect() {
    this._connected = true
    this._activeIndex = -1
    this._mentionAnchor = null  // caret offset where "@" was typed
    this._query = ""
    this._skipNextInput = false
    this._blurTimer = null

    // Hydrate: convert {{var}} in hidden textarea → badges in editor
    this._deserialize(this.hiddenTarget.value)

    this.editorTarget.addEventListener("input", this._onInput)
    this.editorTarget.addEventListener("keydown", this._onKeydown)
    this.editorTarget.addEventListener("blur", this._onBlur)
    this.editorTarget.addEventListener("paste", this._onPaste)
    this.editorTarget.addEventListener("focus", this._onFocus)
    document.addEventListener("click", this._onDocumentClick)
  }

  disconnect() {
    this._connected = false
    clearTimeout(this._blurTimer)
    this.editorTarget.removeEventListener("input", this._onInput)
    this.editorTarget.removeEventListener("keydown", this._onKeydown)
    this.editorTarget.removeEventListener("blur", this._onBlur)
    this.editorTarget.removeEventListener("paste", this._onPaste)
    this.editorTarget.removeEventListener("focus", this._onFocus)
    document.removeEventListener("click", this._onDocumentClick)
  }

  // ── Event handlers (arrow functions for stable `this`) ──

  _onInput = () => {
    if (this._skipNextInput) { this._skipNextInput = false; return }

    if (this._mentionAnchor !== null) {
      this._updateQuery()
    }

    this._sync()
  }

  _onKeydown = (event) => {
    // ── Dropdown open: intercept navigation keys ──
    if (this._isDropdownOpen()) {
      if (event.key === "ArrowDown") {
        event.preventDefault()
        this._navigate(1)
        return
      }
      if (event.key === "ArrowUp") {
        event.preventDefault()
        this._navigate(-1)
        return
      }
      if (event.key === "Enter" || event.key === "Tab") {
        const items = this._visibleItems()
        if (items.length > 0 && this._activeIndex >= 0) {
          event.preventDefault()
          this._selectItem(items[this._activeIndex])
          return
        }
        // If no item selected, close dropdown and let Enter pass through
        this._closeDropdown()
      }
      if (event.key === "Escape") {
        event.preventDefault()
        this._closeDropdown()
        return
      }
    }

    // ── "@" trigger ──
    if (event.key === "@" && !event.ctrlKey && !event.metaKey) {
      // Will be handled after the character is inserted in _onInput,
      // so we record intent here.
      setTimeout(() => this._openMention(), 0)
      return
    }

    // ── Enter: block newlines in single-line mode ──
    if (event.key === "Enter" && !this.multilineValue) {
      event.preventDefault()
      return
    }

    // ── Backspace into badge ──
    if (event.key === "Backspace") {
      const sel = window.getSelection()
      if (!sel || sel.rangeCount === 0) return
      const range = sel.getRangeAt(0)
      if (range.collapsed && range.startOffset === 0 && range.startContainer === this.editorTarget) {
        // At the very start — nothing to do
        return
      }
      // Check if caret is right after a badge
      const node = range.startContainer
      if (node.nodeType === Node.TEXT_NODE && range.startOffset === 0) {
        const prev = node.previousSibling
        if (prev && prev.classList?.contains("ms-expr-badge")) {
          event.preventDefault()
          prev.remove()
          this._sync()
          return
        }
      }
      // Caret in editor root at offset N — check child before
      if (node === this.editorTarget && range.startOffset > 0) {
        const prev = this.editorTarget.childNodes[range.startOffset - 1]
        if (prev && prev.nodeType === Node.ELEMENT_NODE && prev.classList?.contains("ms-expr-badge")) {
          event.preventDefault()
          prev.remove()
          this._sync()
          return
        }
      }
    }
  }

  _onBlur = () => {
    // Delay to allow dropdown click to register
    clearTimeout(this._blurTimer)
    this._blurTimer = setTimeout(() => {
      if (!this._connected || !this.element.isConnected) return
      if (!this.element.contains(document.activeElement)) {
        this._closeDropdown()
        this._sync()
        // Dispatch blur on hidden textarea so mission#updateNodeProp fires
        this.hiddenTarget.dispatchEvent(new Event("blur", { bubbles: true }))
      }
    }, 150)
  }

  _onFocus = () => {
    // Empty editor placeholder management handled by CSS :empty
  }

  _onPaste = (event) => {
    event.preventDefault()
    const text = (event.clipboardData || window.clipboardData).getData("text/plain")
    document.execCommand("insertText", false, text)
  }

  _onDocumentClick = (event) => {
    if (!this.element.contains(event.target)) {
      this._closeDropdown()
    }
  }

  // ── Dropdown click handler (action in HTML) ──

  selectVariable(event) {
    event.preventDefault()
    event.stopPropagation()
    const item = event.currentTarget
    this._selectItem(item)
    // Refocus editor after selection
    this.editorTarget.focus()
  }

  // ── Mention workflow ──

  _openMention() {
    this._mentionAnchor = this._getCaretTextOffset()
    this._query = ""
    this._activeIndex = 0
    this._renderDropdown()
    this._positionDropdown()
  }

  _updateQuery() {
    const currentOffset = this._getCaretTextOffset()
    if (currentOffset === null || this._mentionAnchor === null || currentOffset < this._mentionAnchor) {
      this._closeDropdown()
      return
    }
    // Extract text between @ and caret
    const fullText = this._getEditorPlainText()
    this._query = fullText.substring(this._mentionAnchor, currentOffset).toLowerCase()
    this._activeIndex = 0
    this._renderDropdown()
  }

  _selectItem(item) {
    const varName = item.dataset.variable
    if (!varName) return

    // Remove the "@query" text from the editor
    this._removeMentionText()

    // Insert badge at caret
    this._insertBadge(varName)

    this._closeDropdown()
    this._sync()
  }

  _removeMentionText() {
    if (this._mentionAnchor === null) return

    // Walk through editor to find and remove "@query" text
    const editor = this.editorTarget
    let charCount = 0
    const removeStart = this._mentionAnchor - 1 // include the "@" character
    const removeEnd = this._getCaretTextOffset()

    const walker = document.createTreeWalker(editor, NodeFilter.SHOW_TEXT, null)
    let node
    while ((node = walker.nextNode())) {
      const nodeLen = node.textContent.length
      if (charCount + nodeLen > removeStart) {
        const startInNode = removeStart - charCount
        const endInNode = Math.min(removeEnd - charCount, nodeLen)
        node.textContent = node.textContent.substring(0, startInNode) + node.textContent.substring(endInNode)

        // Reposition caret at the removal point so _insertBadge works correctly
        const offset = Math.min(startInNode, node.textContent.length)
        const sel = window.getSelection()
        if (sel) {
          const range = document.createRange()
          range.setStart(node, offset)
          range.collapse(true)
          sel.removeAllRanges()
          sel.addRange(range)
        }
        break
      }
      charCount += nodeLen
    }
  }

  _insertBadge(varName) {
    const badge = this._createBadge(varName)

    const sel = window.getSelection()
    if (!sel || sel.rangeCount === 0) {
      this.editorTarget.appendChild(badge)
      return
    }

    const range = sel.getRangeAt(0)
    range.collapse(false)
    range.insertNode(badge)

    // Move caret after badge
    const afterRange = document.createRange()
    afterRange.setStartAfter(badge)
    afterRange.collapse(true)
    sel.removeAllRanges()
    sel.addRange(afterRange)
  }

  _createBadge(varName) {
    const badge = document.createElement("span")
    badge.className = "ms-expr-badge"
    badge.contentEditable = "false"
    badge.dataset.variable = varName
    badge.innerHTML = `<i class="fa-solid fa-cube"></i>${this._escapeHtml(varName)}`
    return badge
  }

  // ── Dropdown rendering ──

  _renderDropdown() {
    const dropdown = this.dropdownTarget
    const filtered = this._filteredVariables()

    if (filtered.length === 0 && this._query === "") {
      // Show "no variables" only when there are none at all
      dropdown.innerHTML = `<div class="ms-expr-dropdown-empty"><i class="fa-solid fa-circle-info"></i>No variables available</div>`
    } else if (filtered.length === 0) {
      dropdown.innerHTML = `<div class="ms-expr-dropdown-empty"><i class="fa-solid fa-circle-info"></i>No matching variables</div>`
    } else {
      dropdown.innerHTML = filtered.map((v, i) => {
        const active = i === this._activeIndex ? "active" : ""
        return `<button type="button" class="ms-expr-dropdown-item ${active}" data-variable="${this._escapeAttr(v.name)}" data-action="mousedown->expression-editor#selectVariable">${this._escapeHtml(v.name)}</button>`
      }).join("")
    }

    dropdown.classList.remove("hidden")
  }

  _positionDropdown() {
    const dropdown = this.dropdownTarget
    const editorRect = this.editorTarget.getBoundingClientRect()

    // Position below the editor, aligned left
    dropdown.style.top = `${this.editorTarget.offsetHeight + 4}px`
    dropdown.style.left = "0"

    // Check if dropdown goes below viewport
    requestAnimationFrame(() => {
      const dropRect = dropdown.getBoundingClientRect()
      if (dropRect.bottom > window.innerHeight - 8) {
        // Position above editor instead
        dropdown.style.top = "auto"
        dropdown.style.bottom = `${this.editorTarget.offsetHeight + 4}px`
      }
    })
  }

  _closeDropdown() {
    this._mentionAnchor = null
    this._query = ""
    this._activeIndex = -1
    if (this.hasDropdownTarget) {
      this.dropdownTarget.classList.add("hidden")
      this.dropdownTarget.innerHTML = ""
    }
  }

  _isDropdownOpen() {
    return this.hasDropdownTarget && !this.dropdownTarget.classList.contains("hidden")
  }

  _navigate(direction) {
    const items = this._visibleItems()
    if (items.length === 0) return
    this._activeIndex = (this._activeIndex + direction + items.length) % items.length
    items.forEach((item, i) => item.classList.toggle("active", i === this._activeIndex))
    items[this._activeIndex]?.scrollIntoView({ block: "nearest" })
  }

  _visibleItems() {
    return this.hasDropdownTarget
      ? [...this.dropdownTarget.querySelectorAll(".ms-expr-dropdown-item")]
      : []
  }

  _filteredVariables() {
    if (!this._query) return this.variablesValue
    const q = this._query.toLowerCase()
    return this.variablesValue.filter((v) =>
      v.name.toLowerCase().includes(q) ||
      (v.source && v.source.toLowerCase().includes(q))
    )
  }

  // ── Serialization: editor → hidden textarea ──

  _sync() {
    const value = this._serialize()
    if (this.hiddenTarget.value !== value) {
      this.hiddenTarget.value = value
      // Dispatch custom event for KV sync
      this.hiddenTarget.dispatchEvent(new Event("input", { bubbles: true }))
    }
  }

  _serialize() {
    const parts = []
    this._walkNodes(this.editorTarget, parts)
    return parts.join("").trim()
  }

  _walkNodes(parent, parts) {
    for (const node of parent.childNodes) {
      if (node.nodeType === Node.TEXT_NODE) {
        parts.push(node.textContent)
      } else if (node.nodeType === Node.ELEMENT_NODE) {
        if (node.classList?.contains("ms-expr-badge")) {
          parts.push(`{{${node.dataset.variable}}}`)
        } else if (node.tagName === "BR") {
          parts.push("\n")
        } else if (node.tagName === "DIV" || node.tagName === "P") {
          // ContentEditable wraps new lines in <div>
          if (parts.length > 0 && parts[parts.length - 1] !== "\n") {
            parts.push("\n")
          }
          this._walkNodes(node, parts)
        } else {
          this._walkNodes(node, parts)
        }
      }
    }
  }

  // ── Deserialization: hidden textarea → editor (on connect) ──

  _deserialize(text) {
    const editor = this.editorTarget
    editor.innerHTML = ""

    if (!text) return

    // Split on {{variable}} patterns
    const regex = /\{\{([\w.]+)\}\}/g
    let lastIndex = 0
    let match

    while ((match = regex.exec(text)) !== null) {
      // Text before the match
      if (match.index > lastIndex) {
        this._appendTextContent(editor, text.substring(lastIndex, match.index))
      }
      // Badge for the variable
      const badge = this._createBadge(match[1])
      editor.appendChild(badge)
      lastIndex = regex.lastIndex
    }

    // Remaining text after last match
    if (lastIndex < text.length) {
      this._appendTextContent(editor, text.substring(lastIndex))
    }
  }

  _appendTextContent(parent, text) {
    // Handle newlines by inserting <br> or splitting into lines
    const lines = text.split("\n")
    lines.forEach((line, i) => {
      if (line) parent.appendChild(document.createTextNode(line))
      if (i < lines.length - 1) parent.appendChild(document.createElement("br"))
    })
  }

  // ── Caret helpers ──

  _getCaretTextOffset() {
    const sel = window.getSelection()
    if (!sel || sel.rangeCount === 0) return null

    const range = sel.getRangeAt(0).cloneRange()
    range.collapse(true)

    // Count text characters from start of editor to caret
    const preRange = document.createRange()
    preRange.selectNodeContents(this.editorTarget)
    preRange.setEnd(range.startContainer, range.startOffset)

    // Use a temporary span to measure
    const tempDiv = document.createElement("div")
    tempDiv.appendChild(preRange.cloneContents())

    // Walk and count only text content (skip badges)
    let count = 0
    const walker = document.createTreeWalker(tempDiv, NodeFilter.SHOW_TEXT, null)
    let node
    while ((node = walker.nextNode())) {
      count += node.textContent.length
    }
    return count
  }

  _getEditorPlainText() {
    let text = ""
    const walker = document.createTreeWalker(this.editorTarget, NodeFilter.SHOW_TEXT, null)
    let node
    while ((node = walker.nextNode())) {
      // Skip text inside badges
      if (node.parentElement?.closest(".ms-expr-badge")) continue
      text += node.textContent
    }
    return text
  }

  // ── HTML escaping ──

  _escapeHtml(str) {
    const div = document.createElement("div")
    div.textContent = str
    return div.innerHTML
  }

  _escapeAttr(str) {
    return str.replace(/&/g, "&amp;").replace(/"/g, "&quot;").replace(/'/g, "&#39;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
  }
}
