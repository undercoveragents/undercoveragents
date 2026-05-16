import { Controller } from "@hotwired/stimulus"
import { handleConnectorChange } from "utils/connector"

// Controls capability configuration panels in the agent form.
// Handles enable/disable toggle, LLM config source switching,
// and connector → model Turbo Frame updates.
export default class extends Controller {
  static targets = ["toggle", "body", "customConfig"]
  static values = { modelOptionsUrl: String, frameId: String, fieldPrefix: String }

  connect() {
    this.toggleCapability()
    this.toggleConfig()
  }

  toggleCapability() {
    if (!this.hasToggleTarget) return
    const enabled = this.toggleTarget.checked
    this.bodyTarget.classList.toggle("hidden", !enabled)
  }

  toggleConfig() {
    if (!this.hasCustomConfigTarget) return

    const source = this.element.querySelector(
      'input[type="radio"][name*="llm_config_source"]:checked'
    )?.value
    const show = source === "custom"
    this.customConfigTarget.classList.toggle("hidden", !show)

    // Toggle required attributes on custom config fields
    this.customConfigTarget
      .querySelectorAll("select[data-required], input[data-required]")
      .forEach((el) => {
        el.required = show
      })
  }

  onSourceChange() {
    this.toggleConfig()
  }

  onConnectorChange(event) {
    const extraParams = {}
    extraParams.frame_id = this.frameIdValue
    extraParams.llm_settings = "true"
    if (this.hasFieldPrefixValue && this.fieldPrefixValue) {
      extraParams.field_prefix = this.fieldPrefixValue
    }
    handleConnectorChange(event, this.modelOptionsUrlValue, this.frameIdValue, extraParams)
  }
}
