import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "modelFrame",
    "sourceInput",
    "nodeConfigFields",
    "nodeSourceNotice",
    "systemPreferenceNotice",
    "runtimeNotice",
    "temperatureField",
    "temperatureInput",
    "temperatureHint",
    "thinkingField",
    "thinkingEffortInput",
    "thinkingHint",
    "thinkingBudgetField",
    "thinkingBudgetInput",
  ]

  connect() {
    this.syncCapabilities()
  }

  syncCapabilities() {
    const select = this.#modelSelect()
    const selectedOption = select?.selectedOptions?.[0]
    const hasSelectedModel = Boolean(selectedOption?.value)
    const capabilities = this.#selectedCapabilities(selectedOption)

    this.#toggleField({
      enabled: hasSelectedModel && this.#capabilityEnabled(capabilities, "supportsTemperature", "supports_temperature"),
      field: this.hasTemperatureFieldTarget ? this.temperatureFieldTarget : null,
      inputs: this.hasTemperatureInputTarget ? [this.temperatureInputTarget] : [],
      hint: this.hasTemperatureHintTarget ? this.temperatureHintTarget : null,
      hasSelectedModel,
    })

    this.#syncTemperatureTooltip({
      enabled: hasSelectedModel && this.#capabilityEnabled(capabilities, "supportsTemperature", "supports_temperature"),
      hasSelectedModel,
    })

    this.#toggleField({
      enabled: hasSelectedModel && this.#capabilityEnabled(capabilities, "supportsReasoning", "supports_reasoning"),
      field: this.hasThinkingFieldTarget ? this.thinkingFieldTarget : null,
      inputs: this.hasThinkingEffortInputTarget ? [this.thinkingEffortInputTarget] : [],
      hint: this.hasThinkingHintTarget ? this.thinkingHintTarget : null,
      hasSelectedModel,
    })

    this.syncThinkingBudget()
    this.syncSource()
  }

  syncSource() {
    const source = this.hasSourceInputTarget ? this.sourceInputTarget.value : "node"
    const nodeConfigEnabled = source === "node"

    if (this.hasNodeConfigFieldsTarget) {
      this.nodeConfigFieldsTarget.classList.toggle("llm-settings-disabled", !nodeConfigEnabled)
      this.nodeConfigFieldsTarget.querySelectorAll("input, select, textarea, button").forEach((input) => {
        if (nodeConfigEnabled) {
          if (input.dataset.llmSettingsSourceWasDisabled !== undefined) {
            input.disabled = input.dataset.llmSettingsSourceWasDisabled === "true"
            delete input.dataset.llmSettingsSourceWasDisabled
          }
        } else {
          if (input.dataset.llmSettingsSourceWasDisabled === undefined) {
            input.dataset.llmSettingsSourceWasDisabled = input.disabled ? "true" : "false"
          }
          input.disabled = true
        }
      })
    }

    this.#toggleSourceNotice(this.hasNodeSourceNoticeTarget ? this.nodeSourceNoticeTarget : null, source === "node")
    this.#toggleSourceNotice(
      this.hasSystemPreferenceNoticeTarget ? this.systemPreferenceNoticeTarget : null,
      source === "system_preference",
    )
    this.#toggleSourceNotice(this.hasRuntimeNoticeTarget ? this.runtimeNoticeTarget : null, source === "runtime")
    if (nodeConfigEnabled) this.syncThinkingBudget()
  }

  syncThinkingBudget() {
    if (!this.hasThinkingBudgetFieldTarget || !this.hasThinkingBudgetInputTarget) return

    const hasReasoningModel = this.hasThinkingEffortInputTarget && !this.thinkingEffortInputTarget.disabled
    const effort = this.hasThinkingEffortInputTarget ? this.thinkingEffortInputTarget.value : ""
    const enabled = hasReasoningModel && effort !== "" && effort !== "none"

    this.thinkingBudgetFieldTarget.classList.toggle("llm-settings-disabled", !enabled)
    this.thinkingBudgetInputTarget.disabled = !enabled
  }

  #modelSelect() {
    return this.hasModelFrameTarget ? this.modelFrameTarget.querySelector("select") : null
  }

  #selectedCapabilities(option) {
    if (!option?.dataset?.customProperties) return {}

    try {
      return JSON.parse(option.dataset.customProperties)
    } catch (_error) {
      return {}
    }
  }

  #capabilityEnabled(capabilities, ...keys) {
    return keys.some((key) => capabilities[key] === true || capabilities[key] === "true")
  }

  #toggleField({ enabled, field, inputs, hint, hasSelectedModel }) {
    if (field) field.classList.toggle("llm-settings-disabled", !enabled)
    inputs.forEach((input) => {
      input.disabled = !enabled
    })

    if (!hint) return

    if (enabled) {
      hint.textContent = hint.dataset.llmSettingsSupportedMessage || ""
    } else if (hasSelectedModel) {
      hint.textContent = hint.dataset.llmSettingsUnsupportedMessage || ""
    } else {
      hint.textContent = hint.dataset.llmSettingsUnselectedMessage || ""
    }
  }

  #syncTemperatureTooltip({ enabled, hasSelectedModel }) {
    const message = hasSelectedModel && !enabled && this.hasTemperatureFieldTarget
      ? (this.temperatureFieldTarget.dataset.llmSettingsUnsupportedMessage || "")
      : ""

    if (this.hasTemperatureFieldTarget) this.temperatureFieldTarget.title = message
    if (this.hasTemperatureInputTarget) this.temperatureInputTarget.title = message

    const shell = this.hasTemperatureFieldTarget
      ? this.temperatureFieldTarget.querySelector(".llm-settings-temperature")
      : null

    if (shell) shell.title = message
  }

  #toggleSourceNotice(element, visible) {
    if (!element) return

    element.hidden = !visible
  }
}
