/**
 * Overrides the markdown-it fence renderer to produce standard <pre><code> blocks
 * instead of the library's custom code-block/code-editor divs.
 *
 * @param {object} md - A markdown-it instance (e.g. from getMarkdown())
 */
export function overrideFenceRenderer(md) {
  md.renderer.rules.fence = (tokens, idx) => {
    const token = tokens[idx]
    const info = String(token.info || "").trim()
    const lang = info.split(/\s+/g)[0] || ""
    const content = String(token.content || "")
    const escaped = content
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
    const langClass = lang ? ` class="language-${lang}"` : ""
    return `<pre${langClass}><code>${escaped}</code></pre>`
  }
}
