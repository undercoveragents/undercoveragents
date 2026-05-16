import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["newFields", "existingFields"]

  connect() {
    this.toggle()
  }

  toggle() {
    const mode = this.selectedMode()
    this.toggleSection(this.newFieldsTarget, mode === "new")
    this.toggleSection(this.existingFieldsTarget, mode === "existing")
  }

  selectedMode() {
    const checked = this.element.querySelector('input[name="target_mode"]:checked')
    return checked ? checked.value : "new"
  }

  toggleSection(target, visible) {
    if (!target) return
    target.classList.toggle("hidden", !visible)
  }
}
