import { Controller } from "@hotwired/stimulus"

// Copies text to clipboard when triggered
export default class extends Controller {
  static values = {
    text: String,
  }

  async copy() {
    try {
      await navigator.clipboard.writeText(this.textValue)

      // Visual feedback
      const icon = this.element.querySelector("i")
      if (icon) {
        const originalClass = icon.className
        icon.className = "fa-solid fa-check text-success-500"
        setTimeout(() => {
          icon.className = originalClass
        }, 1500)
      }
    } catch {
      // Fallback for older browsers
      const textarea = document.createElement("textarea")
      textarea.value = this.textValue
      textarea.style.position = "fixed"
      textarea.style.opacity = "0"
      document.body.appendChild(textarea)
      textarea.select()
      document.execCommand("copy")
      document.body.removeChild(textarea)
    }
  }
}
