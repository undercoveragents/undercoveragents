import { Controller } from "@hotwired/stimulus"
import { handleConnectorChange } from "utils/connector"

// Controls the embedding model selection in the RAG Query tool form.
// Handles connector → embedding model Turbo Frame updates.
export default class extends Controller {
  static values = { modelOptionsUrl: String, frameId: String }

  onConnectorChange(event) {
    handleConnectorChange(event, this.modelOptionsUrlValue, this.frameIdValue)
  }
}
