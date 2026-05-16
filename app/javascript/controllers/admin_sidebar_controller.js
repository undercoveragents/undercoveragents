import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { collapsed: { type: Boolean, default: false } }
  static targets = ["icon"]

  connect() {
    this.frameLoadHandler = this.syncActiveLink.bind(this)
    document.addEventListener("turbo:frame-load", this.frameLoadHandler, true)
    this.syncState()
    this.syncActiveLink()
  }

  disconnect() {
    document.removeEventListener("turbo:frame-load", this.frameLoadHandler, true)
  }

  toggle() {
    this.collapsedValue = !this.collapsedValue
    this.syncState()
    this.persistState()
  }

  syncState() {
    this.element.classList.toggle("sidebar-collapsed", this.collapsedValue)

    if (this.hasIconTarget) {
      this.iconTarget.classList.toggle("fa-chevron-left", !this.collapsedValue)
      this.iconTarget.classList.toggle("fa-chevron-right", this.collapsedValue)
    }
  }

  async persistState() {
    try {
      const csrfToken = document.querySelector("meta[name='csrf-token']")?.content
      await fetch("/admin/sidebar", {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": csrfToken,
        },
        body: JSON.stringify({ collapsed: this.collapsedValue }),
      })
    } catch {
      // Non-critical — sidebar state persistence is best-effort
    }
  }

  activateLink(event) {
    this.setActiveLink(event.currentTarget)
  }

  syncActiveLink() {
    requestAnimationFrame(() => {
      const links = Array.from(this.element.querySelectorAll(".sidebar-link"))
      const currentPath = window.location.pathname
      const exactMatch = links.find((link) => this.linkPath(link) === currentPath)
      const prefixMatch = links
        .filter((link) => this.linkPath(link) !== "/admin" && currentPath.startsWith(`${this.linkPath(link)}/`))
        .sort((left, right) => this.linkPath(right).length - this.linkPath(left).length)[0]

      this.setActiveLink(exactMatch || prefixMatch)
    })
  }

  setActiveLink(activeLink) {
    if (!activeLink) return

    this.element.querySelectorAll(".sidebar-link.active").forEach((link) => {
      link.classList.remove("active")
    })
    activeLink.classList.add("active")
  }

  linkPath(link) {
    return new URL(link.href, window.location.origin).pathname.replace(/\/$/, "") || "/"
  }
}
