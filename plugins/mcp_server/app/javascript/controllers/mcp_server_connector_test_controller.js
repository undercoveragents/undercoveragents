import { Controller } from "@hotwired/stimulus"
import { runTestConnection } from "utils/connection_test"

export default class extends Controller {
  static targets = ["testBtn", "testResult"]

  static values = {
    endpoint: String,
    payload: Object,
  }

  async test() {
    await runTestConnection({
      btn: this.testBtnTarget,
      result: this.testResultTarget,
      url: this.hasEndpointValue ? this.endpointValue : null,
      fetchOptions: {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content,
          Accept: "application/json",
        },
        body: JSON.stringify(this.payloadValue || {}),
      },
    })
  }
}
