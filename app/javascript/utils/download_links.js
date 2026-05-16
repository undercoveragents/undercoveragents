/**
 * Post-processes rendered HTML to prettify download links.
 *
 * Finds <a> tags whose href contains "/dl/" and replaces
 * the link text with "📎 filename" extracted from the URL path.
 *
 * @param {HTMLElement} container
 */
export function prettifyDownloadLinks(container) {
  if (!container) return

  container.querySelectorAll('a[href*="/dl/"]').forEach((link) => {
    const href = link.getAttribute("href")
    const match = href.match(/\/dl\/[^/]+\/(.+?)(?:\?.*)?$/)
    if (!match) return

    const filename = decodeURIComponent(match[1])
    link.textContent = `📎 ${filename}`
    link.classList.add("download-link")
    link.setAttribute("title", `Download ${filename}`)
    link.setAttribute("download", filename)
  })
}
