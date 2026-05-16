import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// Provides a live elapsed-time counter while a run is in progress.
// Automatically stops when the run finishes (detected via Turbo Stream
// replacing the wrapper element with finished=true).
export default class extends Controller {
  static targets = ["duration"]
  static values = {
    startedAt: String,
    finished: { type: String, default: "false" }
  }

  connect() {
    this.startTimer()
    this.startFallbackPolling()
  }

  disconnect() {
    this.stopTimer()
    this.stopFallbackPolling()
  }

  finishedValueChanged() {
    if (this.finishedValue === "true") {
      this.stopTimer()
      this.stopFallbackPolling()
    } else {
      this.startTimer()
      this.startFallbackPolling()
    }
  }

  startTimer() {
    this.stopTimer()
    if (this.finishedValue === "true" || !this.startedAtValue) return

    this.timer = setInterval(() => this.updateDuration(), 100)
  }

  stopTimer() {
    if (this.timer) {
      clearInterval(this.timer)
      this.timer = null
    }
  }

  startFallbackPolling() {
    this.stopFallbackPolling()
    if (this.finishedValue === "true") return

    this.pollTimer = setInterval(() => this.refreshRun(), 1500)
    this.pollBootstrapTimer = setTimeout(() => this.refreshRun(), 300)
  }

  stopFallbackPolling() {
    if (this.pollTimer) {
      clearInterval(this.pollTimer)
      this.pollTimer = null
    }

    if (this.pollBootstrapTimer) {
      clearTimeout(this.pollBootstrapTimer)
      this.pollBootstrapTimer = null
    }
  }

  async refreshRun() {
    if (this.finishedValue === "true") return

    const refreshPath = `${window.location.pathname}.turbo_stream`

    const response = await fetch(refreshPath, {
      headers: {
        Accept: "text/vnd.turbo-stream.html"
      },
      credentials: "same-origin"
    })

    if (!response.ok) return

    const stream = await response.text()
    if (stream) Turbo.renderStreamMessage(stream)
  }

  updateDuration() {
    if (!this.hasDurationTarget || !this.startedAtValue) return

    const started = new Date(this.startedAtValue)
    const elapsed = (Date.now() - started.getTime()) / 1000

    this.durationTarget.textContent = this.formatDuration(elapsed)
  }

  formatDuration(seconds) {
    if (seconds < 60) {
      return `${seconds.toFixed(2)}s`
    } else if (seconds < 3600) {
      const m = Math.floor(seconds / 60)
      const s = Math.round(seconds % 60)
      return `${m}m ${s}s`
    } else {
      const h = Math.floor(seconds / 3600)
      const m = Math.floor((seconds % 3600) / 60)
      return `${h}h ${m}m`
    }
  }
}
