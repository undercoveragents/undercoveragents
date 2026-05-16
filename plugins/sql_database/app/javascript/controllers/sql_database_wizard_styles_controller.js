import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    urls: Array,
  }

  connect() {
    this.ensureStylesheets()
  }

  ensureStylesheets() {
    if (!this.hasUrlsValue) return

    this.urlsValue
      .map((url) => this.normalizeUrl(url))
      .filter(Boolean)
      .forEach((url) => {
        if (this.stylesheetLoaded(url)) return

        const link = document.createElement("link")
        link.rel = "stylesheet"
        link.href = url
        link.dataset.sqlDatabaseWizardStylesheet = url
        document.head.appendChild(link)
      })
  }

  stylesheetLoaded(url) {
    return Array.from(document.head.querySelectorAll("link[rel='stylesheet']")).some((link) => {
      const href = this.normalizeUrl(link.getAttribute("href"))
      return href === url || link.dataset.sqlDatabaseWizardStylesheet === url
    })
  }

  normalizeUrl(url) {
    if (!url) return null

    try {
      return new URL(url, window.location.origin).toString()
    } catch {
      return url
    }
  }
}
