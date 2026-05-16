/**
 * CameraManager — centralized, smooth camera control for the Mission Designer.
 *
 * Every viewport change (pan, zoom, fit, follow) goes through this module so
 * animations never fight each other and the camera never "jumps".
 *
 * Key concepts:
 *   - **Follow**: accumulates newly added nodes and smoothly fits them after a
 *     short debounce window (500 ms by default).
 *   - **Lock**: while locked (e.g. during auto-arrange CSS transition) all
 *     follow requests are queued but not executed; they fire once unlocked.
 *   - **Generation counter**: bumped on invalidate() — any in-flight timers
 *     whose generation doesn't match are silently discarded.
 */

const DEFAULT_MAX_ZOOM = 1.3
const DEFAULT_FOLLOW_MAX_ZOOM = 0.85
const FOLLOW_DEBOUNCE_MS = 500
const FOLLOW_DURATION_MS = 800
const FIT_DURATION_MS = 600
const CENTER_DURATION_MS = 400
const ARRANGE_SETTLE_MS = 350       // must be > CSS transition duration (300 ms)

export default class CameraManager {
  /**
   * @param {Object} options
   * @param {number} [options.maxZoom]           – hard max zoom level
   * @param {number} [options.followMaxZoom]     – max zoom used when following new nodes
   * @param {number} [options.followDebounceMs]  – accumulation window before follow fires
   */
  constructor(options = {}) {
    this._instance = null
    this._maxZoom = options.maxZoom ?? DEFAULT_MAX_ZOOM
    this._followMaxZoom = options.followMaxZoom ?? DEFAULT_FOLLOW_MAX_ZOOM
    this._followDebounceMs = options.followDebounceMs ?? FOLLOW_DEBOUNCE_MS

    // Follow state
    this._pendingFollowNodes = []
    this._followTimer = null
    this._generation = 0

    // Animation overlap protection: track when the last animation ends
    // so overlapping follows merge instead of fighting.
    this._animatingUntil = 0
    this._lastFollowedNodeIds = new Set()

    // Lock state (used during auto-arrange)
    this._locked = false
    this._followAfterUnlock = false
  }

  /** Bind or rebind the React Flow instance (call from onInit). */
  setInstance(instance) {
    this._instance = instance
  }

  /** Current React Flow instance (read-only). */
  get instance() {
    return this._instance
  }

  /** Max zoom constant, exposed for external consumers. */
  get maxZoom() {
    return this._maxZoom
  }

  // ─── Public API ────────────────────────────────────────────────────

  /**
   * Queue a set of nodes to follow. Nodes are accumulated over the debounce
   * window and then the camera smoothly fits their bounding box.
   *
   * @param {Array}  nodes        – node objects (must have id, position)
   */
  followNodes(nodes) {
    if (!nodes.length) return
    this._pendingFollowNodes.push(...nodes)

    if (this._locked) {
      // Will fire when unlocked
      this._followAfterUnlock = true
      return
    }

    this._scheduleFollow()
  }

  /**
   * Smoothly fit the entire flow into view.
   * @param {number} [duration]
   */
  fitAll(duration) {
    this._cancelPendingFollow()
    if (!this._instance) return
    this._instance.fitView({
      padding: 0.3,
      maxZoom: this._maxZoom,
      duration: duration ?? FIT_DURATION_MS,
    })
  }

  /**
   * Smoothly center on a specific node.
  * Handles nested nodes by computing absolute position.
   *
   * @param {Object}  node
   * @param {Object}  [opts]
   * @param {number}  [opts.zoom]     – target zoom (defaults to current, clamped)
   * @param {number}  [opts.duration] – animation duration ms
   * @param {boolean} [opts.waitForResize] – if true, waits for a resize event
   *   before centering (e.g. when sidebar opens)
   * @param {Element} [opts.resizeTarget]  – element to observe for resize
   */
  centerOnNode(node, opts = {}) {
    if (!this._instance) return
    this._cancelPendingFollow()

    const absX = node.position?.x || 0
    const absY = node.position?.y || 0
    const currentZoom = this._instance.getZoom()
    const targetZoom = opts.zoom ?? Math.min(Math.max(currentZoom, 0.5), this._maxZoom)
    const duration = opts.duration ?? CENTER_DURATION_MS

    const doCenter = () => {
      if (!this._instance) return
      this._instance.setCenter(absX + 140, absY + 60, {
        zoom: targetZoom,
        duration,
      })
    }

    if (opts.waitForResize && opts.resizeTarget) {
      this._centerAfterResize(opts.resizeTarget, doCenter)
    } else {
      doCenter()
    }
  }

  /**
   * Zoom in, out, or fit.
   * @param {"in"|"out"|"fit"} action
   */
  zoom(action) {
    if (!this._instance) return
    if (action === "in") this._instance.zoomIn({ duration: 200 })
    else if (action === "out") this._instance.zoomOut({ duration: 200 })
    else if (action === "fit") this.fitAll()
  }

  /**
   * Lock the camera — follow requests are queued but not executed.
   * Used during auto-arrange CSS transitions to prevent the camera from
   * moving while nodes are animating to their new positions.
   */
  lock() {
    this._locked = true
  }

  /**
   * Unlock the camera. If nodes were queued while locked, fires follow now.
   */
  unlock() {
    this._locked = false
    if (this._followAfterUnlock && this._pendingFollowNodes.length > 0) {
      this._followAfterUnlock = false
      this._scheduleFollow()
    } else {
      this._followAfterUnlock = false
    }
  }

  /**
   * Cancel all pending follows and bump the generation counter so any
   * in-flight timers self-cancel. Call this before an operation that will
   * supersede pending camera movements (e.g. auto-arrange).
   */
  invalidate() {
    this._cancelPendingFollow()
    this._generation++
    this._animatingUntil = 0
    this._lastFollowedNodeIds = new Set()
  }

  /**
   * Lock + invalidate. Convenience for the start of an auto-arrange.
   * Returns the settle timeout (ms) callers should wait before the CSS
   * node transition completes.
   */
  lockForArrange() {
    this.invalidate()
    this.lock()
    return ARRANGE_SETTLE_MS
  }

  /**
   * Called after arrange CSS transition completes. Unlocks the camera and
   * adjusts **only if nodes moved outside the visible viewport**.
   *
   * Key principle: NEVER change zoom during arrange settle. Only pan
   * if content went off-screen. If everything fits → do nothing.
   */
  settleAfterArrange() {
    this.unlock()
    if (!this._instance) return

    const viewport = this._instance.getViewport()
    const container = document.querySelector(".ms-canvas-wrapper")
    if (!container || !container.clientWidth || !container.clientHeight) return

    const cw = container.clientWidth
    const ch = container.clientHeight

    // Viewport bounds in flow coordinates
    const viewLeft = -viewport.x / viewport.zoom
    const viewTop = -viewport.y / viewport.zoom
    const viewRight = viewLeft + cw / viewport.zoom
    const viewBottom = viewTop + ch / viewport.zoom

    // Compute bounding box of all top-level nodes
    const allNodes = this._instance.getNodes()
    if (!allNodes.length) return

    let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity
    for (const n of allNodes) {
      const x = n.position?.x || 0
      const y = n.position?.y || 0
      const w = n.measured?.width || n.style?.width || 260
      const h = n.measured?.height || n.style?.height || 120
      minX = Math.min(minX, x)
      minY = Math.min(minY, y)
      maxX = Math.max(maxX, x + w)
      maxY = Math.max(maxY, y + h)
    }

    if (minX >= Infinity) return

    const flowWidth = maxX - minX
    const flowHeight = maxY - minY
    const viewWidth = viewRight - viewLeft
    const viewHeight = viewBottom - viewTop

    // Check if the flow fits in the viewport at current zoom
    const fitsAtCurrentZoom = flowWidth <= viewWidth && flowHeight <= viewHeight

    if (fitsAtCurrentZoom) {
      // Flow fits at current zoom — check if it's already visible
      const margin = 30
      const isVisible =
        minX >= viewLeft - margin && maxX <= viewRight + margin &&
        minY >= viewTop - margin && maxY <= viewBottom + margin

      if (isVisible) return // Everything visible — camera stays still

      // Flow fits but is panned off — smoothly pan to center it (no zoom change)
      const centerX = minX + flowWidth / 2
      const centerY = minY + flowHeight / 2
      this._instance.setCenter(centerX, centerY, {
        zoom: viewport.zoom,
        duration: FIT_DURATION_MS,
      })
    } else {
      // Flow doesn't fit at current zoom — need to zoom out to show everything
      this._instance.fitView({
        padding: 0.15,
        maxZoom: viewport.zoom, // never zoom IN, only out
        duration: FIT_DURATION_MS,
      })
    }
  }

  /**
   * @deprecated Use settleAfterArrange() instead.
   * Unlock after arrange + optionally fit.
   */
  unlockAfterArrange(fit = false) {
    this.unlock()
    if (fit) this.fitAll(FOLLOW_DURATION_MS)
  }

  /** Clean up timers. */
  destroy() {
    this._cancelPendingFollow()
    this._instance = null
  }

  // ─── Internal ──────────────────────────────────────────────────────

  /** Cancel any pending follow timer and clear the accumulated node list. */
  _cancelPendingFollow() {
    clearTimeout(this._followTimer)
    this._followTimer = null
    this._pendingFollowNodes = []
  }

  /** Schedule the debounced follow, animation-aware. */
  _scheduleFollow() {
    clearTimeout(this._followTimer)
    const gen = this._generation

    // If a follow animation is still running, compute extra delay so the
    // new follow starts after the current animation completes. This prevents
    // overlapping fitBounds calls that cause mid-animation direction changes.
    const now = Date.now()
    const animRemaining = Math.max(0, this._animatingUntil - now)
    const delay = Math.max(this._followDebounceMs, animRemaining + 50)

    this._followTimer = setTimeout(() => {
      if (this._generation !== gen || this._locked) return
      this._executeFollow()
    }, delay)
  }

  /** Execute the accumulated follow — fitBounds on all pending nodes. */
  _executeFollow() {
    const pending = this._pendingFollowNodes
    this._pendingFollowNodes = []
    if (!pending.length || !this._instance) return

    const allNodes = this._instance.getNodes()
    const nodeMap = {}
    for (const n of allNodes) nodeMap[n.id] = n

    // Merge with previously followed nodes if the last animation was recent.
    // This prevents a jarring zoom-in when following a single new node right
    // after a multi-node follow (the camera would jump from the wide view to
    // a tight zoom on just the new node).
    const mergedIds = new Set(pending.map((n) => n.id))
    const now = Date.now()
    if (now - this._animatingUntil < 200) {
      for (const prevId of this._lastFollowedNodeIds) {
        if (!mergedIds.has(prevId) && nodeMap[prevId]) {
          mergedIds.add(prevId)
          pending.push(nodeMap[prevId])
        }
      }
    }

    // Track which nodes this follow covers
    this._lastFollowedNodeIds = mergedIds

    let minX = Infinity
    let minY = Infinity
    let maxX = -Infinity
    let maxY = -Infinity

    for (const added of pending) {
      const live = nodeMap[added.id] || added
      const absX = live.position?.x || 0
      const absY = live.position?.y || 0
      const w = live.measured?.width || live.style?.width || 260
      const h = live.measured?.height || live.style?.height || 120
      minX = Math.min(minX, absX)
      minY = Math.min(minY, absY)
      maxX = Math.max(maxX, absX + w)
      maxY = Math.max(maxY, absY + h)
    }

    if (minX >= Infinity) return

    // Mark animation window
    this._animatingUntil = Date.now() + FOLLOW_DURATION_MS

    this._instance.fitBounds(
      { x: minX, y: minY, width: maxX - minX, height: maxY - minY },
      { padding: 0.5, maxZoom: this._followMaxZoom, duration: FOLLOW_DURATION_MS },
    )
  }

  /**
   * Wait for a resize (e.g. sidebar opening), then center.
   * Falls back after a short timeout if no resize occurs.
   */
  _centerAfterResize(element, callback) {
    if (!element) {
      callback()
      return
    }

    let done = false
    const finish = () => {
      if (done) return
      done = true
      // Give React Flow's own ResizeObserver one tick to process
      setTimeout(callback, 0)
    }

    const observer = new ResizeObserver(() => {
      observer.disconnect()
      finish()
    })
    observer.observe(element)

    // Fallback if no resize happens (sidebar already open)
    setTimeout(() => {
      observer.disconnect()
      finish()
    }, 50)
  }
}
