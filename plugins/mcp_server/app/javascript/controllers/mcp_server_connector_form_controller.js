import { Controller } from "@hotwired/stimulus"
import { runTestConnection } from "utils/connection_test"

export default class extends Controller {
  static targets = [
    "testBtn",
    "testResult",
    "advancedPanel",
    "advancedChevron",
    "oauthPanel",
    "oauthChevron",
  ]

  static values = {
    testUrl: String,
  }

  toggleAdvanced() {
    this.advancedPanelTarget.classList.toggle("hidden")
    this.advancedChevronTarget.classList.toggle("rotate-180")
  }

  onTransportChange(event) {
    const frame = document.getElementById("mcp_transport_fields")
    if (frame) {
      frame.src = `/connectors/transport_fields?transport_type=${encodeURIComponent(event.target.value)}`
    }
  }

  toggleOAuth() {
    if (this.hasOauthPanelTarget) {
      this.oauthPanelTarget.classList.toggle("hidden")
    }
    if (this.hasOauthChevronTarget) {
      this.oauthChevronTarget.classList.toggle("rotate-180")
    }
  }

  async testConnection() {
    const form = this.element.querySelector("form")
    const formData = new FormData(form)
    formData.delete("_method")

    await runTestConnection({
      btn: this.testBtnTarget,
      result: this.testResultTarget,
      url: this.hasTestUrlValue ? this.testUrlValue : null,
      fetchOptions: {
        method: "POST",
        headers: {
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content,
          Accept: "application/json",
        },
        body: formData,
      },
      includeToolNames: true,
    })
  }
}
