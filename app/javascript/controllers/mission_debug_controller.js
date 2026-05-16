import { Controller } from "@hotwired/stimulus"

// Manages the mission debug lifecycle — run/stop/reset, variable collection,
// and bridges Turbo Stream node-state events to the React canvas.
// Lives inside the sidebar Debug tab panel.
export default class extends Controller {
  static targets = ["nodeEvents", "inputField"]
  static values = {
    missionId: Number,
    executeUrl: String,
    cancelUrl: String,
    runStatusUrl: String,
    runCatchUpUrl: String,
    debugInputsUrl: String,
    loadDebugRunUrl: String,
    resetDebugUrl: String,
    activeRunId: Number,
  }

  connect() {
    this._liveNodeStates = {}

    // Listen for flow-saved events from the mission controller to refresh debug inputs
    this._boundRefreshInputs = () => this.#refreshDebugInputs()
    document.addEventListener("ms:flow-saved", this._boundRefreshInputs)

    // Listen for input changes to persist values to localStorage
    this._boundPersistInputs = () => this.#saveInputsToStorage()
    this.element.addEventListener("input", this._boundPersistInputs)
    this.element.addEventListener("change", this._boundPersistInputs)

    // Restore saved input values from localStorage
    this.#restoreInputsFromStorage()

    // Observe node events container for new child elements (from Turbo Stream broadcasts)
    this.nodeEventsObserver = new MutationObserver((mutations) => {
      mutations.forEach((mutation) => {
        mutation.addedNodes.forEach((node) => {
          if (node.nodeType !== Node.ELEMENT_NODE) return
          if (node.dataset.nodeId) {
            this.#dispatchNodeState(node)
          } else if (node.dataset.edgeId) {
            this.#dispatchEdgeState(node)
          }
        })
      })
    })

    if (this.hasNodeEventsTarget) {
      this.nodeEventsObserver.observe(this.nodeEventsTarget, { childList: true })
    }

    // Auto-recover active run on page load
    if (this.activeRunIdValue && this.activeRunIdValue > 0) {
      // Auto-open the debug sidebar tab so the user sees the running state
      document.dispatchEvent(new CustomEvent("ms:activate-sidebar-tab", { detail: { tab: "debug" } }))
      this.#dispatchToCanvas("ms:mode-change", { mode: "run" })
      this.#processExistingNodeEvents()
      this.#scheduleCatchUp()
    } else if (this.hasNodeEventsTarget && this.nodeEventsTarget.children.length > 0) {
      // Finished run loaded from server — dispatch existing node events to canvas
      this.#processExistingNodeEvents()
    }
  }

  disconnect() {
    if (this.nodeEventsObserver) this.nodeEventsObserver.disconnect()
    if (this._catchUpTimer) clearTimeout(this._catchUpTimer)
    if (this._boundRefreshInputs) document.removeEventListener("ms:flow-saved", this._boundRefreshInputs)
    if (this._boundPersistInputs) {
      this.element.removeEventListener("input", this._boundPersistInputs)
      this.element.removeEventListener("change", this._boundPersistInputs)
    }
  }

  // ── Run execution ──
  startRun() {
    const canvas = document.getElementById("mission-designer-root")
    const nodeErrors = canvas ? JSON.parse(canvas.dataset.nodeErrors || "{}") : {}
    if (Object.keys(nodeErrors).length > 0) {
      this.#showValidationError("Fix configuration errors in highlighted nodes before running.")
      return
    }

    const { variables, triggerData, fileFields } = this.#collectInputData()
    const flowInput = document.getElementById("mission-flow-data")
    const flowData = flowInput ? this.#mergeGlobalVariables(flowInput.value) : null
    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content

    // Keep debug tab active (no tab switch needed)

    // Enable debug mode on React canvas
    this.#dispatchToCanvas("ms:mode-change", { mode: "run" })

    // Cancel any pending or in-flight catch-up from a previous run
    if (this._catchUpTimer) {
      clearTimeout(this._catchUpTimer)
      this._catchUpTimer = null
    }
    if (this._catchUpController) {
      this._catchUpController.abort()
      this._catchUpController = null
    }

    // Clear stale node events from previous run
    if (this.hasNodeEventsTarget) this.nodeEventsTarget.innerHTML = ""
    this._liveNodeStates = {}
    this._timelineSyncInFlight = false

    // Dispatch reset to React canvas
    this.#dispatchToCanvas("ms:reset-debug", {})

    // Always use FormData to support file uploads
    const formData = new FormData()
    if (flowData) formData.append("flow_data", flowData)
    formData.append("variables", JSON.stringify(variables))
    formData.append("trigger_data", JSON.stringify(triggerData))

    // Append file fields
    Object.entries(fileFields).forEach(([fieldName, files]) => {
      files.forEach((file) => formData.append(`trigger_files[${fieldName}][]`, file))
    })

    fetch(this.executeUrlValue, {
      method: "POST",
      headers: {
        "X-CSRF-Token": csrfToken,
        "Accept": "text/vnd.turbo-stream.html",
      },
      body: formData,
    })
      .then((response) => response.text())
      .then((html) => {
        Turbo.renderStreamMessage(html)
        // Process any node events that arrived before the observer caught them
        this.#processExistingNodeEvents()
        // Poll run status after a delay to catch up on events missed before subscription was active
        this.#scheduleCatchUp()
      })
      .catch(() => {
        // Silently handle — the panel will remain in its current state
      })
  }

  // ── Stop execution ──
  stopRun() {
    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content

    // Cancel any pending catch-up polling
    if (this._catchUpTimer) {
      clearTimeout(this._catchUpTimer)
      this._catchUpTimer = null
    }
    if (this._catchUpController) {
      this._catchUpController.abort()
      this._catchUpController = null
    }

    fetch(this.cancelUrlValue, {
      method: "POST",
      headers: {
        "X-CSRF-Token": csrfToken,
        "Accept": "text/vnd.turbo-stream.html",
      },
    })
      .then((response) => response.text())
      .then((html) => {
        Turbo.renderStreamMessage(html)
        // Schedule a catch-up to sync any node states that the DebugRunner
        // broadcasts after the currently-executing node finishes.
        this.#scheduleCatchUp()
      })
      .catch(() => {})
  }

  // ── Reset execution ──
  resetRun() {
    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content

    // Clear node events and reset canvas immediately
    if (this.hasNodeEventsTarget) this.nodeEventsTarget.innerHTML = ""
    this._liveNodeStates = {}
    this.#dispatchToCanvas("ms:reset-debug", {})
    this.#dispatchToCanvas("ms:mode-change", { mode: "design" })

    // Cancel any pending catch-up
    if (this._catchUpTimer) {
      clearTimeout(this._catchUpTimer)
      this._catchUpTimer = null
    }
    if (this._catchUpController) {
      this._catchUpController.abort()
      this._catchUpController = null
    }

    fetch(this.resetDebugUrlValue, {
      method: "POST",
      headers: {
        "X-CSRF-Token": csrfToken,
        "Accept": "text/vnd.turbo-stream.html",
      },
    })
      .then((response) => response.text())
      .then((html) => {
        Turbo.renderStreamMessage(html)
      })
      .catch(() => {})
  }

  // ── Timeline node click ──
  selectTimelineNode(event) {
    const nodeId = event.currentTarget.dataset.nodeId
    if (nodeId) {
      this.#dispatchToCanvas("ms:select-debug-node", { nodeId })
    }
  }

  // ── Load past run ──
  loadPastRun(event) {
    const runId = event.currentTarget.dataset.runId
    if (!runId) return

    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content
    const url = `${this.loadDebugRunUrlValue}?run_id=${runId}`

    // Reset canvas before loading
    if (this.hasNodeEventsTarget) this.nodeEventsTarget.innerHTML = ""
    this._liveNodeStates = {}
    this.#dispatchToCanvas("ms:reset-debug", {})

    fetch(url, {
      headers: {
        "X-CSRF-Token": csrfToken,
        "Accept": "text/vnd.turbo-stream.html",
      },
    })
      .then((response) => response.text())
      .then((html) => {
        Turbo.renderStreamMessage(html)
        this.#processExistingNodeEvents()
        this.#openExecutionSection()
      })
      .catch(() => {})
  }

  // ── Private ──

  #collectInputData() {
    const variables = {}
    const triggerData = {}
    const fileFields = {}

    this.element.querySelectorAll(".ms-debug-input-card").forEach((card) => {
      const isTrigger = card.dataset.trigger === "true"
      const keyEl = card.querySelector(".ms-debug-input-key")
      const key = keyEl ? keyEl.textContent.trim() : ""
      if (!key) return

      // Handle file inputs
      const fileEl = card.querySelector("input[type='file']")
      if (fileEl && fileEl.files.length > 0) {
        fileFields[key] = Array.from(fileEl.files)
        return
      }

      // Handle checkbox inputs (boolean)
      const checkboxEl = card.querySelector("input[type='checkbox']")
      if (checkboxEl && !card.querySelector(".ms-debug-input-text, .ms-debug-input-textarea")) {
        const target = isTrigger ? triggerData : variables
        target[key] = checkboxEl.checked
        return
      }

      // Handle text/textarea/number/date inputs
      const valueEl = card.querySelector(".ms-debug-input-text, .ms-debug-input-textarea")
      const raw = valueEl ? valueEl.value : ""
      const isArray = valueEl?.dataset.arrayType === "true"
      const target = isTrigger ? triggerData : variables

      if (isArray) {
        target[key] = raw.split("\n").map((s) => s.trim()).filter(Boolean)
      } else {
        // Try to parse JSON values
        try {
          target[key] = JSON.parse(raw)
        } catch {
          target[key] = raw
        }
      }
    })

    return { variables, triggerData, fileFields }
  }

  #processExistingNodeEvents() {
    if (!this.hasNodeEventsTarget) return
    this.nodeEventsTarget.querySelectorAll("[data-node-id]").forEach((node) => {
      this.#dispatchNodeState(node)
    })
    this.nodeEventsTarget.querySelectorAll("[data-edge-id]").forEach((node) => {
      this.#dispatchEdgeState(node)
    })
  }

  #openExecutionSection() {
    const timeline = document.getElementById("mission-timeline-content")
    if (!timeline) return
    const details = timeline.closest("details.ms-debug-section")
    if (details) details.open = true
  }

  #scheduleCatchUp() {
    if (this._catchUpTimer) clearTimeout(this._catchUpTimer)
    this._catchUpTimer = setTimeout(() => this.#catchUpMissedEvents(), 1500)
  }

  #catchUpMissedEvents() {
    if (!this.hasRunStatusUrlValue) return

    fetch(this.runStatusUrlValue, { headers: { "Accept": "application/json" } })
      .then((r) => r.json())
      .then((data) => {
        if (!data.execution_log) return

        // Compute per-node completion counts and keep only the last state per node
        const completionCounts = {}
        const latestByNode = {}
        data.execution_log.forEach((entry) => {
          if (entry.status === "success") {
            const isIterOrLoop = entry.node_type === "iterator" || entry.node_type === "loop"
            if (isIterOrLoop && entry.next_port === "done") {
              const currentCount = completionCounts[entry.node_id] || 0
              const count = entry.node_type === "iterator" && Array.isArray(entry.output)
                ? entry.output.length
                : entry.node_type === "loop"
                  ? currentCount
                  : currentCount + 1
              completionCounts[entry.node_id] = count
            } else {
              completionCounts[entry.node_id] = (completionCounts[entry.node_id] || 0) + 1
            }
          }
          latestByNode[entry.node_id] = entry
        })

        Object.values(latestByNode).forEach((entry) => {
          const liveInfo = this._liveNodeStates[entry.node_id] || {}
          const currentLiveState = liveInfo.state
          if (currentLiveState === "running") return
          const isIterOrLoop = entry.node_type === "iterator" || entry.node_type === "loop"
          const entryStatus = entry.status || "success"
          const state = (isIterOrLoop && entryStatus === "success" && entry.next_port !== "done")
            ? "running"
            : entryStatus
          if (state === "running" && currentLiveState && currentLiveState !== "running") return
          const error = entry.error || liveInfo.error || null
          this.#dispatchToCanvas("ms:node-state-update", {
            nodeId: entry.node_id,
            state,
            nodeType: entry.node_type,
            nextPort: entry.next_port || null,
            durationMs: entry.duration_ms || null,
            error,
            completedCount: completionCounts[entry.node_id] || 0,
          })
        })

        Object.entries(data.node_states || {}).forEach(([nodeId, stateInfo]) => {
          const liveInfo = this._liveNodeStates[nodeId] || {}
          if (liveInfo.state === "running") return

          this.#dispatchToCanvas("ms:node-state-update", {
            nodeId,
            state: stateInfo.status,
            nodeType: stateInfo.node_type || null,
            nextPort: stateInfo.next_port || null,
            durationMs: stateInfo.duration_ms || null,
            error: stateInfo.error || liveInfo.error || null,
            completedCount: stateInfo.completed_count || 0,
          })
        })

        Object.entries(data.edge_states || {}).forEach(([edgeId, state]) => {
          this.#dispatchToCanvas("ms:edge-state-update", { edgeId, state })
        })

        // If a node is currently executing, dispatch its "running" state so the
        // canvas highlights it even when the original broadcast was missed.
        if (data.current_node_id && !latestByNode[data.current_node_id]) {
          this.#dispatchToCanvas("ms:node-state-update", {
            nodeId: data.current_node_id,
            state: "running",
            nodeType: null,
            nextPort: null,
            durationMs: null,
            error: null,
            completedCount: 0,
          })
        }

        const finished = ["completed", "failed", "cancelled"].includes(data.status)

        // Detect timeline desync: if the server has more execution_log entries
        // than the DOM timeline, broadcasts were missed — sync via full catch-up.
        const timelineEl = document.getElementById("mission-timeline-entries")
        const domEntryCount = timelineEl ? timelineEl.children.length : 0
        const serverEntryCount = data.execution_log.length
        const timelineOutOfSync = serverEntryCount > domEntryCount

        if (finished) {
          this.#fetchFullCatchUp()
        } else {
          if (timelineOutOfSync && !this._timelineSyncInFlight) {
            this.#syncTimeline()
          }
          this._catchUpTimer = setTimeout(() => this.#catchUpMissedEvents(), 2000)
        }
      })
      .catch(() => {
        this._catchUpTimer = setTimeout(() => this.#catchUpMissedEvents(), 3000)
      })
  }

  // Syncs the timeline by fetching the full catch-up during active execution.
  // Guarded by _timelineSyncInFlight to prevent concurrent fetches.
  #syncTimeline() {
    if (!this.hasRunCatchUpUrlValue) return
    this._timelineSyncInFlight = true
    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content

    fetch(this.runCatchUpUrlValue, {
      headers: {
        "X-CSRF-Token": csrfToken,
        "Accept": "text/vnd.turbo-stream.html",
      },
    })
      .then((response) => response.text())
      .then((html) => {
        if (html && html.trim().length > 0) {
          Turbo.renderStreamMessage(html)
          this.#processExistingNodeEvents()
        }
      })
      .catch(() => {})
      .finally(() => {
        this._timelineSyncInFlight = false
      })
  }

  #fetchFullCatchUp() {
    if (!this.hasRunCatchUpUrlValue) return
    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content

    const controller = new AbortController()
    this._catchUpController = controller

    fetch(this.runCatchUpUrlValue, {
      headers: {
        "X-CSRF-Token": csrfToken,
        "Accept": "text/vnd.turbo-stream.html",
      },
      signal: controller.signal,
    })
      .then((response) => response.text())
      .then((html) => {
        if (html && html.trim().length > 0) {
          Turbo.renderStreamMessage(html)
          this.#processExistingNodeEvents()
        }
      })
      .catch((error) => {
        if (error.name === "AbortError") return
      })
  }

  #dispatchEdgeState(node) {
    const canvas = document.getElementById("mission-designer-root")
    if (!canvas) return
    canvas.dispatchEvent(new CustomEvent("ms:edge-state-update", {
      bubbles: true,
      detail: {
        edgeId: node.dataset.edgeId,
        state: node.dataset.edgeState,
      },
    }))
  }

  #dispatchNodeState(node) {
    const canvas = document.getElementById("mission-designer-root")
    if (!canvas) return

    const liveNodeId = node.dataset.nodeId
    const liveState = node.dataset.state
    const liveError = node.dataset.error || null
    const prevLive = this._liveNodeStates[liveNodeId] || {}
    const preservedError = liveError || prevLive.error || null
    this._liveNodeStates[liveNodeId] = { state: liveState, error: preservedError }

    canvas.dispatchEvent(new CustomEvent("ms:node-state-update", {
      bubbles: true,
      detail: {
        nodeId: liveNodeId,
        state: liveState,
        nodeType: node.dataset.nodeType,
        nextPort: node.dataset.nextPort || null,
        durationMs: node.dataset.durationMs ? parseFloat(node.dataset.durationMs) : null,
        error: preservedError,
        completedCount: node.dataset.completedCount ? parseInt(node.dataset.completedCount, 10) : 0,
      },
    }))
  }

  #dispatchToCanvas(eventName, detail) {
    const canvas = document.getElementById("mission-designer-root")
    if (!canvas) return
    canvas.dispatchEvent(new CustomEvent(eventName, { bubbles: true, detail }))
  }

  #showValidationError(message) {
    const runStatus = document.getElementById("mission-run-status")
    if (!runStatus) return
    runStatus.innerHTML = `
      <div class="ms-debug-run-indicator" style="color: #ef4444; background: rgba(239,68,68,0.1); max-width: 340px; white-space: normal; text-align: left;">
        <i class="fa-solid fa-triangle-exclamation" style="flex-shrink: 0;"></i>
        <span>${message}</span>
      </div>`
  }

  #refreshDebugInputs() {
    if (!this.debugInputsUrlValue) return

    // Collect only user-modified values before refresh (skip server defaults)
    const currentValues = {}
    this.element.querySelectorAll(".ms-debug-input-card").forEach((card) => {
      const keyEl = card.querySelector(".ms-debug-input-key")
      const key = keyEl ? keyEl.textContent.trim() : ""
      if (!key) return
      const inputEl = card.querySelector(".ms-debug-input-text, .ms-debug-input-textarea")
      if (inputEl && inputEl.value !== inputEl.defaultValue) {
        currentValues[key] = inputEl.value
      }
      const checkboxEl = card.querySelector("input[type='checkbox']")
      if (checkboxEl && !inputEl && checkboxEl.checked !== checkboxEl.defaultChecked) {
        currentValues[key] = checkboxEl.checked
      }
    })

    const container = this.element.querySelector(".ms-debug-sidebar-inputs")
    if (!container) return

    fetch(this.debugInputsUrlValue, {
      headers: { "Accept": "text/html" },
    })
      .then((r) => r.text())
      .then((html) => {
        container.innerHTML = html

        // Restore from localStorage first, then overlay in-memory values
        this.#restoreInputsFromStorage()
        container.querySelectorAll(".ms-debug-input-card").forEach((card) => {
          const keyEl = card.querySelector(".ms-debug-input-key")
          const key = keyEl ? keyEl.textContent.trim() : ""
          if (!key || !(key in currentValues)) return
          const inputEl = card.querySelector(".ms-debug-input-text, .ms-debug-input-textarea")
          if (inputEl) { inputEl.value = currentValues[key]; return }
          const checkboxEl = card.querySelector("input[type='checkbox']")
          if (checkboxEl) checkboxEl.checked = !!currentValues[key]
        })
      })
      .catch(() => {})
  }

  // ── Input persistence (localStorage) ──

  get #storageKey() {
    return `mission-debug-inputs-${this.missionIdValue}`
  }

  #saveInputsToStorage() {
    const values = {}
    this.element.querySelectorAll(".ms-debug-input-card").forEach((card) => {
      const keyEl = card.querySelector(".ms-debug-input-key")
      const key = keyEl ? keyEl.textContent.trim() : ""
      if (!key) return

      // Skip file inputs — cannot persist
      const fileEl = card.querySelector("input[type='file']")
      if (fileEl) return

      const checkboxEl = card.querySelector("input[type='checkbox']")
      if (checkboxEl && !card.querySelector(".ms-debug-input-text, .ms-debug-input-textarea")) {
        values[key] = { type: "checkbox", value: checkboxEl.checked }
        return
      }

      const inputEl = card.querySelector(".ms-debug-input-text, .ms-debug-input-textarea")
      if (inputEl) {
        values[key] = { type: "text", value: inputEl.value }
      }
    })

    try {
      localStorage.setItem(this.#storageKey, JSON.stringify(values))
    } catch {
      // Storage full or unavailable — silently ignore
    }
  }

  #restoreInputsFromStorage() {
    let saved
    try {
      const raw = localStorage.getItem(this.#storageKey)
      if (!raw) return
      saved = JSON.parse(raw)
    } catch {
      return
    }
    if (!saved || typeof saved !== "object") return

    this.element.querySelectorAll(".ms-debug-input-card").forEach((card) => {
      const keyEl = card.querySelector(".ms-debug-input-key")
      const key = keyEl ? keyEl.textContent.trim() : ""
      if (!key || !saved[key]) return

      const entry = saved[key]

      if (entry.type === "checkbox") {
        const checkboxEl = card.querySelector("input[type='checkbox']")
        if (checkboxEl) checkboxEl.checked = !!entry.value
        return
      }

      const inputEl = card.querySelector(".ms-debug-input-text, .ms-debug-input-textarea")
      if (inputEl) inputEl.value = entry.value || ""
    })
  }

  #mergeGlobalVariables(flowDataStr) {
    try {
      const flow = JSON.parse(flowDataStr)
      const gvInput = document.getElementById("mission-global-variables")
      if (gvInput) {
        flow.global_variables = JSON.parse(gvInput.value || "[]")
      }
      return JSON.stringify(flow)
    } catch {
      return flowDataStr
    }
  }
}
