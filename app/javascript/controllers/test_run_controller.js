import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// Manages the test suite run page — expand/collapse result rows and
// continuously reconcile server state while the run is active so the UI
// does not depend on every transient Turbo broadcast being delivered.
export default class extends Controller {
  static bootstrapPollDelay = 300
  static staleUpdateThreshold = 4000
  static staleCheckInterval = 1000

  static values = {
    pollUrl: String,
  }

  connect() {
    this.expandedRows = new Set()
    this.lastUpdateAt = Date.now()

    const status = this.getCurrentStatus()

    if (this.isInProgress(status)) {
      this.observeMutations()
      this.startFallbackPolling()
    }
  }

  disconnect() {
    this.stopFallbackPolling()
    if (this.observer) this.observer.disconnect()
  }

  // ── Expand / Collapse result detail ──────────────────────────

  toggleDetail(event) {
    const row = event.currentTarget.closest('.test-result-row')
    if (!row) return

    const detail = row.querySelector('.test-result-detail')
    const icon = row.querySelector('.test-expand-icon')
    if (!detail) return

    const isHidden = detail.classList.contains('hidden')
    detail.classList.toggle('hidden')
    if (icon) icon.classList.toggle('rotate-90')

    if (isHidden) {
      this.expandedRows.add(row.id)
    } else {
      this.expandedRows.delete(row.id)
    }
  }

  // Re-expand rows that were open before a Turbo Stream replacement
  restoreExpanded() {
    for (const rowId of this.expandedRows) {
      const row = document.getElementById(rowId)
      if (!row) continue

      const detail = row.querySelector('.test-result-detail')
      const icon = row.querySelector('.test-expand-icon')

      if (detail && detail.classList.contains('hidden')) {
        detail.classList.remove('hidden')
      }
      if (icon && !icon.classList.contains('rotate-90')) {
        icon.classList.add('rotate-90')
      }
    }
  }

  // ── Mutation Observer (Turbo Stream updates) ─────────────────

  observeMutations() {
    this.observer = new MutationObserver(() => {
      this.lastUpdateAt = Date.now()
      this.restoreExpanded()
      this.checkForCompletion()
    })

    this.observer.observe(this.element, { childList: true, subtree: true })
  }

  // ── Status detection ─────────────────────────────────────────

  getCurrentStatus() {
    const el = this.element.querySelector('#test-run-current-status')
    return el?.dataset?.status || 'pending'
  }

  isInProgress(status) {
    return ['pending', 'running', 'evaluating'].includes(status)
  }

  isTerminal(status) {
    return ['completed', 'failed', 'cancelled'].includes(status)
  }

  // When we detect a terminal status via DOM change, schedule a
  // stop polling once the run is finished.
  checkForCompletion() {
    const status = this.getCurrentStatus()

    if (this.isTerminal(status)) {
      this.stopFallbackPolling()
    }
  }

  // ── Turbo Stream catch-up polling ────────────────────────────

  startFallbackPolling() {
    this.stopFallbackPolling()
    if (this.isTerminal(this.getCurrentStatus())) return

    this.staleCheckTimer = setInterval(() => this.refreshIfStale(), this.constructor.staleCheckInterval)
    this.pollBootstrapTimer = setTimeout(() => this.refreshRun(), this.constructor.bootstrapPollDelay)
  }

  stopFallbackPolling() {
    if (this.staleCheckTimer) {
      clearInterval(this.staleCheckTimer)
      this.staleCheckTimer = null
    }

    if (this.pollBootstrapTimer) {
      clearTimeout(this.pollBootstrapTimer)
      this.pollBootstrapTimer = null
    }
  }

  // ── Turbo Stream refresh ─────────────────────────────────────

  refreshIfStale() {
    if (this.refreshInFlight || this.isTerminal(this.getCurrentStatus())) return
    if (Date.now() - this.lastUpdateAt < this.constructor.staleUpdateThreshold) return

    this.refreshRun()
  }

  async refreshRun() {
    if (this.refreshInFlight || this.isTerminal(this.getCurrentStatus())) return

    this.refreshInFlight = true

    try {
      const response = await fetch(this.pollUrlValue || `${window.location.pathname}.turbo_stream`, {
        headers: {
          Accept: "text/vnd.turbo-stream.html",
        },
        credentials: "same-origin",
      })

      if (!response.ok) return

      const stream = await response.text()
      if (stream) {
        this.lastUpdateAt = Date.now()
        Turbo.renderStreamMessage(stream)
      }
    } finally {
      this.refreshInFlight = false
    }
  }
}
