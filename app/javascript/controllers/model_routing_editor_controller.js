import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["hiddenInput", "strategyInput", "fallbackSection", "canarySection", "abTestSection", "fallbackList", "routeTemplate"]

  static values = {
    modelCatalog: String,
  }

  connect() {
    this.#hydrateFallbackRoutes()
    this.#sync(false)
  }

  strategyChanged() {
    if (this.strategyInputTarget.value === "fallback" && this.#fallbackRoutes().length === 0) {
      this.#appendFallbackRoute()
    }

    this.#sync(true)
  }

  connectorChanged(event) {
    this.#refreshRouteModels(event.currentTarget.closest("[data-model-routing-route]"))
    this.#sync(true)
  }

  addFallbackRoute() {
    this.#appendFallbackRoute()
    this.#sync(true)
  }

  removeRoute(event) {
    event.currentTarget.closest("[data-model-routing-route]")?.remove()

    if (this.strategyInputTarget.value === "fallback" && this.#fallbackRoutes().length === 0) {
      this.#appendFallbackRoute()
    }

    this.#sync(true)
  }

  sync() {
    this.#sync(true)
  }

  #sync(notify) {
    this.#toggleSections()
    this.hiddenInputTarget.value = this.#serializedValue()

    if (!notify) return

    this.hiddenInputTarget.dispatchEvent(new Event("change", { bubbles: true }))
  }

  #toggleSections() {
    const strategy = this.strategyInputTarget.value

    this.fallbackSectionTarget.hidden = strategy !== "fallback"
    this.canarySectionTarget.hidden = strategy !== "canary"
    this.abTestSectionTarget.hidden = strategy !== "ab_test"
  }

  #appendFallbackRoute() {
    const fragment = this.routeTemplateTarget.content.cloneNode(true)
    const route = fragment.querySelector("[data-model-routing-route]")
    this.fallbackListTarget.appendChild(fragment)
    this.#refreshRouteModels(route)
  }

  #hydrateFallbackRoutes() {
    this.#fallbackRoutes().forEach((route) => this.#refreshRouteModels(route))
  }

  #fallbackRoutes() {
    return Array.from(this.fallbackListTarget.querySelectorAll("[data-model-routing-route]"))
  }

  #refreshRouteModels(route) {
    if (!route) return

    const connectorSelect = route.querySelector('[data-model-routing-editor-role="connector"]')
    const modelSelect = route.querySelector('[data-model-routing-editor-role="model"]')
    if (!connectorSelect || !modelSelect) return

    const selectedModel = modelSelect.value
    const options = this.#modelCatalog()[connectorSelect.value] || []

    modelSelect.innerHTML = ""
    modelSelect.appendChild(this.#buildOption("Select a model…", ""))
    options.forEach((option) => modelSelect.appendChild(this.#buildOption(option.label, option.value)))

    modelSelect.value = options.some((option) => option.value === selectedModel) ? selectedModel : ""
  }

  #buildOption(label, value) {
    const option = document.createElement("option")
    option.textContent = label
    option.value = value
    return option
  }

  #serializedValue() {
    const strategy = this.strategyInputTarget.value
    if (!strategy || strategy === "single") return ""

    const config = { strategy }
    if (strategy === "fallback") {
      config.fallback_models = this.#fallbackRoutes()
        .map((route) => this.#routeValue(route))
        .filter((route) => Object.keys(route).length > 0)
    } else if (strategy === "canary") {
      config.canary_model = this.#routeValue(this.canarySectionTarget.querySelector("[data-model-routing-route]"))
      const percent = this.canarySectionTarget.querySelector('[data-model-routing-editor-role="canary-percent"]')?.value
      if (percent !== undefined && percent !== "") config.canary_percent = Number.parseInt(percent, 10)
    } else if (strategy === "ab_test") {
      config.comparison_model = this.#routeValue(this.abTestSectionTarget.querySelector("[data-model-routing-route]"))
    }

    return JSON.stringify(config)
  }

  #routeValue(route) {
    if (!route) return {}

    const connectorId = route.querySelector('[data-model-routing-editor-role="connector"]')?.value
    const modelId = route.querySelector('[data-model-routing-editor-role="model"]')?.value
    const value = {}

    if (connectorId) value.connector_id = Number.parseInt(connectorId, 10)
    if (modelId) value.model_id = modelId

    return value
  }

  #modelCatalog() {
    try {
      return JSON.parse(this.modelCatalogValue || "{}")
    } catch (_error) {
      return {}
    }
  }
}
