import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    frameId: { type: String, default: "rag-step-configurator" },
    url: String,
  }

  preview(event) {
    event?.preventDefault()

    const form = this.element.closest("form")
    const frame = document.getElementById(this.frameIdValue)
    if (!form || !frame || !this.hasUrlValue) return

    const scrollY = window.scrollY
    const activeFieldName = event?.target?.name
    const url = new URL(this.urlValue, window.location.origin)
    const params = new URLSearchParams(new FormData(form))
    params.delete("authenticity_token")
    params.delete("_method")
    params.delete("commit")
    url.search = params.toString()

    frame.addEventListener("turbo:frame-load", () => {
      requestAnimationFrame(() => {
        window.scrollTo(0, scrollY)
        this.restoreFocus(frame, activeFieldName)
      })
    }, { once: true })

    frame.src = url.toString()
  }

  restoreFocus(frame, fieldName) {
    if (!fieldName) return

    const field = Array.from(frame.querySelectorAll("[name]")).find((element) => element.name === fieldName)
    if (!field?.focus) return

    field.focus({ preventScroll: true })
  }
}
