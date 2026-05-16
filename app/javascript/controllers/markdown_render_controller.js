import { Controller } from "@hotwired/stimulus"
import { getMarkdown } from "stream-markdown-parser"
import { overrideFenceRenderer } from "utils/markdown"
import { prettifyDownloadLinks } from "utils/download_links"

/**
 * MarkdownRenderController
 *
 * Renders raw markdown content into HTML when the element connects.
 * Used for persisted assistant messages that need markdown formatting.
 */
export default class extends Controller {
  static values = {
    content: String,
  }

  connect() {
    if (this.contentValue) {
      this.render()
    }
  }

  render() {
    const md = getMarkdown()
    overrideFenceRenderer(md)
    this.element.innerHTML = md.render(this.contentValue)
    this.wrapTables()
    prettifyDownloadLinks(this.element)
  }

  wrapTables() {
    this.element.querySelectorAll("table").forEach((table) => {
      if (!table.parentElement || table.parentElement.classList.contains("markdown-table-wrapper")) {
        return
      }

      const wrapper = document.createElement("div")
      wrapper.className = "markdown-table-wrapper"
      table.parentNode.insertBefore(wrapper, table)
      wrapper.appendChild(table)
    })
  }
}
