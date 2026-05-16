import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["slider", "value", "label"]

  connect() {
    this.update()
  }

  update() {
    const temp = parseFloat(this.sliderTarget.value)
    this.valueTarget.textContent = temp.toFixed(1)
    this.labelTarget.textContent = `(${this.temperatureLabel(temp)})`
  }

  temperatureLabel(temp) {
    if (temp <= 0.3) return "Precise"
    if (temp <= 0.7) return "Balanced"
    if (temp <= 1.2) return "Creative"
    return "Experimental"
  }
}
