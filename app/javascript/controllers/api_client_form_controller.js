import { Controller } from "@hotwired/stimulus"

// Toggles mission select visibility based on access scope
export default class extends Controller {
  static targets = ["missionSelect"]

  toggleScope(event) {
    if (event.target.value === "scoped") {
      this.missionSelectTarget.classList.remove("hidden")
    } else {
      this.missionSelectTarget.classList.add("hidden")
    }
  }
}
