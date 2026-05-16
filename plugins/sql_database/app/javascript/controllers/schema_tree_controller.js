import { Controller } from "@hotwired/stimulus"

// Manages collapsible tree view for database schema objects
export default class extends Controller {
  static targets = ["node"]

  toggle(event) {
    const button = event.currentTarget
    const nodeId = button.dataset.schemaTreeNodeId
    const node = this.element.querySelector(
      `[data-schema-tree-content="${nodeId}"]`
    )
    const chevron = button.querySelector("[data-chevron]")

    if (node) {
      node.classList.toggle("hidden")
      if (chevron) {
        chevron.classList.toggle("rotate-90")
      }
    }
  }

  expandAll() {
    this.element
      .querySelectorAll("[data-schema-tree-content]")
      .forEach((node) => node.classList.remove("hidden"))
    this.element
      .querySelectorAll("[data-chevron]")
      .forEach((chevron) => chevron.classList.add("rotate-90"))
  }

  collapseAll() {
    this.element
      .querySelectorAll("[data-schema-tree-content]")
      .forEach((node) => node.classList.add("hidden"))
    this.element
      .querySelectorAll("[data-chevron]")
      .forEach((chevron) => chevron.classList.remove("rotate-90"))
  }
}
