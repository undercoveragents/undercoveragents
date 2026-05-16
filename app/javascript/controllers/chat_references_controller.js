import { Controller } from "@hotwired/stimulus"

const SEARCH_DEBOUNCE_MS = 120

export default class extends Controller {
  static targets = ["input", "payloadInput", "menu", "contextList", "searchInput", "results"]

  static values = {
    kinds: String,
    trigger: { type: String, default: "#" },
    url: String,
  }

  connect() {
    this.references = this.parsePayload()
    this.activeIndex = -1
    this.inlineRange = null
    this.abortController = null
    this.searchTimer = null
    this.menuMode = null
    this.submittedHandler = () => this.clear()
    this.pointerDownHandler = (event) => this.handleDocumentPointerDown(event)
    this.element.addEventListener("chat:submitted", this.submittedHandler)
    document.addEventListener("pointerdown", this.pointerDownHandler)
    this.renderContext()
  }

  disconnect() {
    this.element.removeEventListener("chat:submitted", this.submittedHandler)
    document.removeEventListener("pointerdown", this.pointerDownHandler)
    this.abortController?.abort()
    window.clearTimeout(this.searchTimer)
  }

  input() {
    this.pruneInlineReferences()
    const range = this.currentInlineRange()
    if (!range) {
      if (this.menuMode === "inline") this.closeMenu()
      return
    }

    this.inlineRange = range
    this.openMenu({ mode: "inline", query: range.query, focusSearch: !this.menuOpen() })
  }

  keydown(event) {
    if (!this.menuOpen()) return

    if (["ArrowDown", "ArrowUp", "Enter", "Escape"].includes(event.key)) {
      event.preventDefault()
      event.stopImmediatePropagation()
    }

    if (event.key === "ArrowDown") this.moveActive(1)
    if (event.key === "ArrowUp") this.moveActive(-1)
    if (event.key === "Enter") this.selectActive()
    if (event.key === "Escape") this.closeMenu()
  }

  openPicker(event) {
    event.preventDefault()
    this.inlineRange = null
    this.openMenu({ mode: "context", query: "", focusSearch: true })
  }

  searchInput(event) {
    this.queueSearch(event.currentTarget.value, this.menuMode || "context")
  }

  searchKeydown(event) {
    if (!this.menuOpen()) return

    if (["ArrowDown", "ArrowUp", "Enter", "Escape"].includes(event.key)) {
      event.preventDefault()
    }

    if (event.key === "ArrowDown") this.moveActive(1)
    if (event.key === "ArrowUp") this.moveActive(-1)
    if (event.key === "Enter") this.selectActive()
    if (event.key === "Escape") {
      this.closeMenu()
      this.inputTarget.focus({ preventScroll: true })
    }
  }

  select(event) {
    event.preventDefault()
    const reference = this.referenceFromElement(event.currentTarget)
    if (!reference) return

    this.addReference(reference, { source: this.menuMode || "context" })
    this.closeMenu()
    this.inputTarget.focus({ preventScroll: true })
  }

  remove(event) {
    event.preventDefault()
    const key = event.currentTarget.dataset.referenceKey
    const removed = this.references.find((reference) => this.referenceKey(reference) === key)
    this.references = this.references.filter((reference) => this.referenceKey(reference) !== key)
    this.removeInlineMention(removed)
    this.syncPayload()
    this.renderContext()
  }

  clear() {
    this.references = []
    this.inlineRange = null
    this.syncPayload()
    this.renderContext()
    this.closeMenu()
  }

  queueSearch(query, mode) {
    window.clearTimeout(this.searchTimer)
    this.searchTimer = window.setTimeout(() => this.performSearch(query, mode), SEARCH_DEBOUNCE_MS)
  }

  openMenu({ mode, query, focusSearch }) {
    this.menuMode = mode
    this.menuTarget.classList.remove("hidden")
    this.searchInputTarget.value = query
    if (focusSearch) this.focusSearchInput()
    this.queueSearch(query, mode)
  }

  async performSearch(query, mode) {
    if (!this.hasUrlValue) return

    this.menuMode = mode
    this.abortController?.abort()
    this.abortController = new AbortController()

    try {
      const response = await fetch(this.searchUrl(query), {
        credentials: "same-origin",
        headers: { Accept: "application/json" },
        signal: this.abortController.signal,
      })
      if (!response.ok) return

      const data = await response.json()
      this.renderMenu(data.groups || [])
    } catch (error) {
      if (error.name !== "AbortError") this.closeMenu()
    }
  }

  searchUrl(query) {
    const url = new URL(this.urlValue, window.location.origin)
    url.searchParams.set("q", query)
    url.searchParams.set("kinds", this.kindsValue || "")
    return url.toString()
  }

  renderMenu(groups) {
    this.resultsTarget.replaceChildren()
    this.activeIndex = -1
    const items = groups.flatMap((group) => group.items || [])

    if (items.length === 0) {
      this.resultsTarget.appendChild(this.emptyMenuElement())
      return
    }

    groups.forEach((group) => {
      if (!group.items?.length) return

      this.resultsTarget.appendChild(this.groupHeadingElement(group))
      group.items.forEach((item) => this.resultsTarget.appendChild(this.itemElement(item)))
    })

    this.moveActive(1)
  }

  groupHeadingElement(group) {
    const heading = document.createElement("div")
    heading.className = "shared-chat__reference-group"
    heading.textContent = group.label
    return heading
  }

  itemElement(item) {
    const button = document.createElement("button")
    button.type = "button"
    button.className = "shared-chat__reference-option"
    button.dataset.action = "click->chat-references#select"
    button.dataset.reference = JSON.stringify(item)
    button.setAttribute("role", "option")

    const icon = document.createElement("i")
    icon.className = item.icon || "fa-solid fa-hashtag"
    button.appendChild(icon)

    const copy = document.createElement("span")
    copy.className = "shared-chat__reference-option-copy"
    button.appendChild(copy)

    const label = document.createElement("strong")
    label.textContent = item.label
    copy.appendChild(label)

    if (item.subtitle) {
      const subtitle = document.createElement("small")
      subtitle.textContent = item.subtitle
      copy.appendChild(subtitle)
    }

    return button
  }

  emptyMenuElement() {
    const empty = document.createElement("div")
    empty.className = "shared-chat__reference-empty"
    empty.textContent = "No references found"
    return empty
  }

  moveActive(delta) {
    const options = this.optionElements()
    if (options.length === 0) return

    this.activeIndex = (this.activeIndex + delta + options.length) % options.length
    options.forEach((option, index) => {
      option.classList.toggle("is-active", index === this.activeIndex)
      option.setAttribute("aria-selected", index === this.activeIndex ? "true" : "false")

      if (index === this.activeIndex) {
        option.scrollIntoView({ block: "nearest" })
      }
    })
  }

  selectActive() {
    const option = this.optionElements()[this.activeIndex]
    option?.click()
  }

  optionElements() {
    return Array.from(this.resultsTarget.querySelectorAll(".shared-chat__reference-option"))
  }

  addReference(reference, { source }) {
    const selected = {
      id: reference.id,
      sgid: reference.sgid,
      kind: reference.kind,
      type: reference.type,
      label: reference.label,
      icon: reference.icon,
      display_mention: this.mentionFor(reference),
      display_tag: reference.display_tag,
      mention: source === "inline" ? this.uniqueMention(this.mentionFor(reference)) : null,
      source,
    }

    if (source === "inline") this.insertMention(selected.mention)

    this.references = this.references.filter((existing) => this.referenceKey(existing) !== this.referenceKey(selected))
    this.references.push(selected)
    this.syncPayload()
    this.renderContext()
  }

  insertMention(mention) {
    if (!this.inlineRange) return

    const value = this.inputTarget.value
    const before = value.slice(0, this.inlineRange.start)
    const after = value.slice(this.inlineRange.end)
    const nextValue = `${before}${mention} ${after}`
    const cursor = before.length + mention.length + 1
    this.inputTarget.value = nextValue
    this.inputTarget.setSelectionRange(cursor, cursor)
    this.inputTarget.dispatchEvent(new Event("input", { bubbles: true }))
  }

  uniqueMention(baseMention) {
    const mention = baseMention || this.triggerValue
    const existingMentions = new Set(this.references.map((reference) => reference.mention).filter(Boolean))
    if (!existingMentions.has(mention)) return mention

    let index = 2
    let candidate = `${mention}-${index}`
    while (existingMentions.has(candidate)) {
      index += 1
      candidate = `${mention}-${index}`
    }
    return candidate
  }

  mentionFor(reference) {
    return reference.mention || reference.display_tag || this.triggerValue
  }

  pruneInlineReferences() {
    const content = this.inputTarget.value
    const nextReferences = this.references.filter((reference) => {
      return reference.source === "context" || !reference.mention || content.includes(reference.mention)
    })

    if (nextReferences.length === this.references.length) return

    this.references = nextReferences
    this.syncPayload()
    this.renderContext()
  }

  currentInlineRange() {
    const cursor = this.inputTarget.selectionStart
    const beforeCursor = this.inputTarget.value.slice(0, cursor)
    const tokenStart = beforeCursor.lastIndexOf(this.triggerValue)
    if (tokenStart < 0) return null
    if (tokenStart > 0 && /\S/.test(beforeCursor[tokenStart - 1])) return null

    const query = beforeCursor.slice(tokenStart + this.triggerValue.length)
    if (/\s/.test(query)) return null

    return { start: tokenStart, end: cursor, query }
  }

  renderContext() {
    if (!this.hasContextListTarget) return

    this.contextListTarget.replaceChildren()
    this.contextListTarget.classList.toggle("hidden", this.references.length === 0)

    this.references.forEach((reference) => this.contextListTarget.appendChild(this.chipElement(reference)))
  }

  chipElement(reference) {
    const chip = document.createElement("span")
    chip.className = "shared-chat__reference-chip"

    const icon = document.createElement("i")
    icon.className = reference.icon || "fa-solid fa-hashtag"
    chip.appendChild(icon)

    chip.appendChild(this.chipLabelElement(reference))

    const remove = document.createElement("button")
    remove.type = "button"
    remove.title = "Remove reference"
    remove.dataset.action = "click->chat-references#remove"
    remove.dataset.referenceKey = this.referenceKey(reference)
    remove.innerHTML = '<i class="fa-solid fa-xmark"></i>'
    chip.appendChild(remove)

    return chip
  }

  chipLabelElement(reference) {
    const label = document.createElement("span")
    label.textContent = reference.label || reference.display_mention || reference.mention || "Reference"
    return label
  }

  removeInlineMention(reference) {
    if (!reference || reference.source !== "inline" || !reference.mention) return

    const value = this.inputTarget.value
    const start = value.indexOf(reference.mention)
    if (start < 0) return

    const mentionEnd = start + reference.mention.length
    const end = value[mentionEnd] === " " ? mentionEnd + 1 : mentionEnd
    const nextValue = `${value.slice(0, start)}${value.slice(end)}`
    this.inputTarget.value = nextValue
    this.inputTarget.setSelectionRange(start, start)
    this.inputTarget.dispatchEvent(new Event("input", { bubbles: true }))
  }

  syncPayload() {
    if (this.hasPayloadInputTarget) {
      this.payloadInputTarget.value = JSON.stringify(this.references)
    }
  }

  closeMenu() {
    this.menuTarget.classList.add("hidden")
    this.resultsTarget.replaceChildren()
    this.searchInputTarget.value = ""
    this.activeIndex = -1
    this.menuMode = null
  }

  menuOpen() {
    return !this.menuTarget.classList.contains("hidden")
  }

  focusSearchInput() {
    requestAnimationFrame(() => {
      if (!this.menuOpen()) return

      this.searchInputTarget.focus({ preventScroll: true })
      const length = this.searchInputTarget.value.length
      this.searchInputTarget.setSelectionRange(length, length)
    })
  }

  handleDocumentPointerDown(event) {
    if (!this.menuOpen()) return
    if (this.element.contains(event.target)) return

    this.closeMenu()
  }

  referenceFromElement(element) {
    try {
      return JSON.parse(element.dataset.reference || "null")
    } catch {
      return null
    }
  }

  referenceKey(reference) {
    return [reference.kind, reference.id, reference.mention || "context", reference.source].join(":")
  }

  parsePayload() {
    try {
      return JSON.parse(this.payloadInputTarget?.value || "[]")
    } catch {
      return []
    }
  }
}
