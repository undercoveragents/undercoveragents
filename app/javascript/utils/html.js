/**
 * Escapes HTML entities to prevent XSS when interpolating user content.
 *
 * @param {string} text - Raw text to escape
 * @returns {string} HTML-safe string
 */
export function escapeHtml(text) {
  const div = document.createElement("div")
  div.textContent = text
  return div.innerHTML
}
