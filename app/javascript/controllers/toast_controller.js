import { Controller } from "@hotwired/stimulus"

/**
 * Toast notification controller.
 *
 * Usage from HTML (flash messages rendered server-side):
 *   <div data-controller="toast"
 *        data-toast-messages-value='[{"type":"notice","text":"Saved!"}]'
 *        data-action="toast:show@document->toast#show">
 *   </div>
 *
 * Usage from JavaScript:
 *   document.dispatchEvent(new CustomEvent("toast:show", {
 *     detail: { type: "error", text: "Something went wrong" }
 *   }))
 *
 * Types: "notice" (green), "alert"/"error" (red)
 */
export default class extends Controller {
  static values = { messages: { type: Array, default: [] } }

  connect() {
    this.messagesValue.forEach((msg) => this.#showToast(msg.type, msg.text))
  }

  show(event) {
    const { type, text } = event.detail || {}
    if (text) this.#showToast(type || "notice", text)
  }

  // ── Private ──

  #showToast(type, text) {
    const isError = type === "alert" || type === "error"

    const toast = document.createElement("div")
    toast.className = `toast toast-${isError ? "alert" : "notice"}`

    const content = document.createElement("div")
    content.className = "toast-content"

    const icon = document.createElement("i")
    icon.className = `fa-solid ${isError ? "fa-circle-exclamation" : "fa-circle-check"}`

    const span = document.createElement("span")
    span.textContent = text

    content.appendChild(icon)
    content.appendChild(span)

    const closeBtn = document.createElement("button")
    closeBtn.className = "toast-close"
    closeBtn.type = "button"
    closeBtn.setAttribute("aria-label", "Dismiss")
    const closeIcon = document.createElement("i")
    closeIcon.className = "fa-solid fa-xmark"
    closeBtn.appendChild(closeIcon)
    closeBtn.addEventListener("click", () => this.#dismiss(toast))

    toast.appendChild(content)
    toast.appendChild(closeBtn)
    this.element.appendChild(toast)

    requestAnimationFrame(() => toast.classList.add("toast-enter"))

    const duration = isError ? 6000 : 4000
    setTimeout(() => this.#dismiss(toast), duration)
  }

  #dismiss(toast) {
    if (toast._dismissed) return
    toast._dismissed = true
    toast.classList.add("toast-exit")
    toast.addEventListener("animationend", () => toast.remove())
  }
}
