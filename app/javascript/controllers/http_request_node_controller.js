import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["authType", "authSection", "bodyMode", "bodyModeChoice", "bodySection", "retryEnabled", "retryFields"]

  connect() {
    this.sync()
  }

  sync() {
    this.#syncAuthorization()
    this.#syncBodyMode()
    this.#syncRetryFields()
  }

  #syncAuthorization() {
    const authType = this.hasAuthTypeTarget ? this.authTypeTarget.value : "none"
    this.authSectionTargets.forEach((section) => {
      section.hidden = section.dataset.authMode !== authType
    })
  }

  #syncBodyMode() {
    const selectedMode = this.hasBodyModeTarget ? this.bodyModeTarget.value || "none" : this.bodyModeChoiceTargets.find((choice) => choice.checked)?.value || "none"
    this.bodySectionTargets.forEach((section) => {
      section.hidden = section.dataset.bodyMode !== selectedMode
    })

    this.bodyModeChoiceTargets.forEach((choice) => {
      choice.closest(".ms-http-request-mode-pill")?.classList.toggle("is-active", choice.checked)
    })
  }

  #syncRetryFields() {
    if (!(this.hasRetryEnabledTarget && this.hasRetryFieldsTarget)) return

    this.retryFieldsTarget.hidden = !this.retryEnabledTarget.checked
  }
}
