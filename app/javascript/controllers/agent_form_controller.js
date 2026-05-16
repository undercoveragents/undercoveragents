import { Controller } from "@hotwired/stimulus"
import { handleConnectorChange } from "utils/connector"

// Filters the model select to only show models for the selected LLM connector's
// provider. Updates a Turbo Frame by navigating it to a server-rendered partial.
export default class extends Controller {
  static values = {
    modelOptionsUrl: String,
    frameId: { type: String, default: "agent_model_select" },
    llmSettings: { type: Boolean, default: false },
  }

  onConnectorChange(event) {
    const extraParams = {}

    if (this.llmSettingsValue) extraParams.llm_settings = "true"

    handleConnectorChange(event, this.modelOptionsUrlValue, this.frameIdValue, extraParams)
  }
}
