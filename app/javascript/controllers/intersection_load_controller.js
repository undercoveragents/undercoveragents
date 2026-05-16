import { Controller } from "@hotwired/stimulus"

/**
 * IntersectionLoadController
 *
 * Watches a sentinel element with IntersectionObserver.
 * When the element enters the viewport, fetches the configured URL as a
 * Turbo Stream response and lets Turbo process the stream actions.
 *
 * Usage:
 *   data-controller="intersection-load"
 *   data-intersection-load-url-value="<turbo_stream_url>"
 */
export default class extends Controller {
  static values = {
    url: String,
  }

  connect() {
    this.#observe()
  }

  disconnect() {
    this.observer?.disconnect()
  }

  // ── Private ──────────────────────────────────────────────────────────────────

  #observe() {
    this.observer = new IntersectionObserver(this.#onIntersect.bind(this), {
      rootMargin: "200px",
    })
    this.observer.observe(this.element)
  }

  #onIntersect(entries) {
    if (!entries[0].isIntersecting) return

    this.observer.disconnect()
    this.#load()
  }

  #load() {
    fetch(this.urlValue, {
      headers: { Accept: "text/vnd.turbo-stream.html" },
      credentials: "same-origin",
    })
      .then((response) => response.text())
      .then((html) => Turbo.renderStreamMessage(html))
  }
}
