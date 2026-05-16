import { Controller } from "@hotwired/stimulus"
import { handleConnectorChange } from "utils/connector"

// Controls the LLM configuration section in the SQL Query tool form.
// Toggles visibility of the custom LLM config panel based on radio selection,
// and handles connector → model Turbo Frame updates.
export default class extends Controller {
  static targets = ["customConfig"]
  static values = { modelOptionsUrl: String, frameId: String }

  connect() {
    this.toggleConfig()
  }

  toggleConfig() {
    const source = this.element.querySelector('input[name="sql_query[llm_config_source]"]:checked')?.value
    const show = source === "custom"
    this.customConfigTarget.classList.toggle("hidden", !show)

    // Toggle required attributes on custom config fields
    this.customConfigTarget.querySelectorAll("select[data-required], input[data-required]").forEach((el) => {
      el.required = show
    })
  }

  onSourceChange() {
    this.toggleConfig()
  }

  onConnectorChange(event) {
    handleConnectorChange(event, this.modelOptionsUrlValue, this.frameIdValue, { llm_settings: "true" })
  }
}
