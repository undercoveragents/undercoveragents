import { Controller } from "@hotwired/stimulus"

// Manages the Table Visibility page: collapsible groups,
// Select All / Deselect All, and real-time "n of N selected" counter.
export default class extends Controller {
  static targets = ["checkbox", "groupContent", "groupChevron", "counter"]

  // ── Group-level collapse (tree-view) ──

  toggleGroup ({ params: { group } }) {
    const content = this.groupContentTargets.find(el => el.dataset.group === group)
    const chevron = this.groupChevronTargets.find(el => el.dataset.group === group)

    if (content) content.classList.toggle("hidden")
    if (chevron) chevron.classList.toggle("rotate-90")
  }

  // ── Checkbox operations ──

  selectAll () {
    this.checkboxTargets.forEach(cb => { cb.checked = true })
    this.#updateCounter()
  }

  deselectAll () {
    this.checkboxTargets.forEach(cb => { cb.checked = false })
    this.#updateCounter()
  }

  // Called on every individual checkbox change
  updateCounter () {
    this.#updateCounter()
  }

  // ── Private ──

  #updateCounter () {
    if (!this.hasCounterTarget) return

    const total = this.checkboxTargets.length
    const checked = this.checkboxTargets.filter(cb => cb.checked).length
    this.counterTarget.textContent = `${checked} of ${total} selected`
  }
}
