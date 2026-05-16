import { Controller } from "@hotwired/stimulus"

// Manages light/dark theme toggling.
// Persists user preference in localStorage and cookies.
export default class extends Controller {
  static targets = ["sunIcon", "moonIcon"]

  connect() {
    this._chartkickLoadHandler = this.refreshCharts.bind(this)
    window.addEventListener("chartkick:load", this._chartkickLoadHandler)
    this.applyTheme(this.currentTheme)
    this.refreshCharts()
  }

  disconnect() {
    window.removeEventListener("chartkick:load", this._chartkickLoadHandler)
  }

  toggle() {
    const next = this.currentTheme === "dark" ? "light" : "dark"
    this.writeTheme(next)
    this.applyTheme(next)
  }

  // --- private ---------------------------------------------------------

  get currentTheme() {
    const storedTheme = this.readStoredTheme()
    if (storedTheme) return storedTheme

    return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light"
  }

  readStoredTheme() {
    try {
      const theme = localStorage.getItem("theme")
      return theme === "dark" || theme === "light" ? theme : null
    } catch {
      return null
    }
  }

  writeTheme(theme) {
    try {
      localStorage.setItem("theme", theme)
    } catch {
      // Ignore browsers that block localStorage.
    }

    document.cookie = `theme=${theme}; Max-Age=31536000; Path=/; SameSite=Lax`
  }

  applyTheme(theme) {
    const root = document.documentElement
    const previousTheme = root.dataset.theme

    root.classList.toggle("dark", theme === "dark")
    root.dataset.theme = theme
    root.style.backgroundColor = this.backgroundColorFor(theme)
    root.style.color = this.textColorFor(theme)
    root.style.colorScheme = theme

    this.updateIcons(theme)

    if (previousTheme && previousTheme !== theme) {
      this.refreshCharts()
    }
  }

  updateIcons(theme) {
    if (!this.hasSunIconTarget || !this.hasMoonIconTarget) return

    if (theme === "dark") {
      this.sunIconTarget.classList.remove("hidden")
      this.moonIconTarget.classList.add("hidden")
    } else {
      this.sunIconTarget.classList.add("hidden")
      this.moonIconTarget.classList.remove("hidden")
    }
  }

  refreshCharts() {
    if (!window.Chartkick?.eachChart) return

    const colors = this.chartThemeColors()

    requestAnimationFrame(() => {
      window.Chartkick.eachChart((chart) => this.updateChartTheme(chart, colors))
    })
  }

  chartThemeColors() {
    const styles = getComputedStyle(document.documentElement)
    const darkMode = document.documentElement.dataset.theme === "dark"

    return {
      axisBorder: darkMode ? "rgba(148, 163, 184, 0.22)" : styles.getPropertyValue("--border-default").trim(),
      xGrid: darkMode ? "rgba(148, 163, 184, 0.10)" : "rgba(148, 163, 184, 0.12)",
      yGrid: darkMode ? "rgba(148, 163, 184, 0.18)" : "rgba(148, 163, 184, 0.16)",
      textMuted: styles.getPropertyValue("--text-muted").trim(),
      textSecondary: styles.getPropertyValue("--text-secondary").trim()
    }
  }

  updateChartTheme(chart, colors) {
    const chartObject = chart?.getChartObject?.()
    if (!chartObject) return

    const xAxisOptions = {
      gridLineColor: colors.xGrid,
      gridLineWidth: 1,
      labels: { style: { color: colors.textMuted } },
      lineColor: colors.axisBorder,
      tickColor: colors.axisBorder
    }

    const yAxisOptions = {
      gridLineColor: colors.yGrid,
      gridLineWidth: 1,
      labels: { style: { color: colors.textMuted } },
      lineColor: colors.axisBorder,
      tickColor: colors.axisBorder,
      title: { style: { color: colors.textSecondary } }
    }

    chartObject.xAxis?.forEach((axis) => axis.update(xAxisOptions, false))
    chartObject.yAxis?.forEach((axis) => axis.update(yAxisOptions, false))

    chartObject.legend?.update?.({ itemStyle: { color: colors.textSecondary } }, false)
    chartObject.redraw?.()
  }

  backgroundColorFor(theme) {
    return theme === "dark" ? "#020617" : "#f8fafc"
  }

  textColorFor(theme) {
    return theme === "dark" ? "#f1f5f9" : "#0f172a"
  }
}
