import { Controller } from "@hotwired/stimulus"

// Controls the test suite form evaluation-model picker.
export default class extends Controller {
  static values = { modelOptionsUrl: String }

  onEvaluationConnectorChange(event) {
    const frame = document.getElementById("evaluation_model_select")
    if (!frame) return

    const url = new URL(this.modelOptionsUrlValue, window.location.origin)
    if (event.target.value) url.searchParams.set("connector_id", event.target.value)
    url.searchParams.set("frame_id", "evaluation_model_select")
    url.searchParams.set("field_prefix", "test_suite")
    url.searchParams.set("field_name", "evaluation_model_id")
    url.searchParams.set("required", "false")

    frame.src = url.pathname + url.search
  }
}
