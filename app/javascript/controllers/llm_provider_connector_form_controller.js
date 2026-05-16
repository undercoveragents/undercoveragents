import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["advancedPanel", "advancedChevron"]

  toggleAdvanced() {
    this.advancedPanelTarget.classList.toggle("hidden")
    this.advancedChevronTarget.classList.toggle("rotate-180")
  }

  onProviderChange(event) {
    const frame = document.getElementById("llm_provider_fields")
    if (frame) {
      if (event.target.value) {
        frame.src = `/admin/connectors/provider_fields?provider=${encodeURIComponent(event.target.value)}`
      } else {
        frame.src = "/admin/connectors/provider_fields"
      }
    }
  }
}
