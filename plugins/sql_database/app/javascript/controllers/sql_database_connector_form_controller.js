import { Controller } from "@hotwired/stimulus"
import Choices from "choices.js"
import { runTestConnection } from "utils/connection_test"
import { escapeHtml } from "utils/html"

const DEFAULT_PORTS = {
  postgresql: 5432,
  mysql: 3306,
  sqlite: null,
}

const DISCOVERY_ADAPTERS = new Set(["postgresql"])

export default class extends Controller {
  static targets = [
    "fieldsModeBody",
    "connectionStringBody",
    "adapterSelect",
    "hostInput",
    "portInput",
    "connectionStringInput",
    "sslInput",
    "databaseSelect",
    "databaseManualInput",
    "databaseSelectWrapper",
    "databaseManualWrapper",
    "databaseHint",
    "databaseLoadRow",
    "databaseLoadBtn",
    "databaseResult",
    "testBtn",
    "testResult",
  ]

  static values = {
    testUrl: String,
    databaseOptionsUrl: String,
    autoLoadDatabases: Boolean,
    currentDatabase: String,
  }

  connect() {
    this.databaseChoices = new Choices(this.databaseSelectTarget, {
      searchEnabled: true,
      placeholder: true,
      placeholderValue: "Select a database...",
      shouldSort: false,
      itemSelectText: "",
      noResultsText: "No databases found",
      noChoicesText: "Load databases to continue",
      allowHTML: false,
    })

    this.syncPortPlaceholder()
    this.syncConnectionMode()

    if (this.autoLoadDatabasesValue && this.discoverySupported) {
      this.loadDatabases()
    }
  }

  disconnect() {
    if (this.databaseChoices) {
      this.databaseChoices.destroy()
      this.databaseChoices = null
    }
  }

  syncConnectionMode() {
    const fieldsMode = this.fieldsModeEnabled

    this.fieldsModeBodyTarget.classList.toggle("hidden", !fieldsMode)
    this.connectionStringBodyTarget.classList.toggle("hidden", fieldsMode)
    this.toggleBodyDisabledState(this.fieldsModeBodyTarget, !fieldsMode)
    this.toggleBodyDisabledState(this.connectionStringBodyTarget, fieldsMode)
    this.hostInputTarget.required = fieldsMode
    this.connectionStringInputTarget.required = !fieldsMode

    this.syncPortPlaceholder()
    this.syncAdapterState()
  }

  onAdapterChange() {
    const currentValue = this.latestDatabaseValue()

    this.syncPortPlaceholder()
    this.resetDatabaseChoices(currentValue)
    this.syncAdapterState()
  }

  async loadDatabases() {
    if (!this.hasDatabaseOptionsUrlValue || !this.discoverySupported) return

    const btn = this.databaseLoadBtnTarget
    const selectedValue = this.currentDatabaseValue()

    btn.disabled = true
    btn.innerHTML = '<i class="fa-solid fa-spinner fa-spin mr-1"></i>Loading databases...'
    this.renderStatus(this.databaseResultTarget, "info", "Loading available databases from the server...")

    const form = this.element.querySelector("form")
    const formData = new FormData(form)
    formData.delete("_method")

    try {
      const response = await fetch(this.databaseOptionsUrlValue, {
        method: "POST",
        headers: {
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content,
          Accept: "application/json",
        },
        body: formData,
      })

      if (!response.ok && response.headers.get("content-type")?.indexOf("application/json") === -1) {
        throw new Error(`Server error (HTTP ${response.status})`)
      }

      const data = await response.json()

      if (data.success) {
        const databases = this.normalizeDatabases(data.databases)

        this.populateDatabaseChoices(databases, selectedValue)
        this.syncAdapterState()
        this.renderStatus(this.databaseResultTarget, "success", data.message || "Loaded database list.")
      } else {
        this.renderStatus(this.databaseResultTarget, "error", data.message || "Could not load databases.")
      }
    } catch (error) {
      console.error("Database discovery error:", error)
      this.renderStatus(
        this.databaseResultTarget,
        "error",
        error.message || "Could not reach the server to load databases.",
      )
    } finally {
      btn.disabled = false
      btn.innerHTML = '<i class="fa-solid fa-arrows-rotate mr-1"></i>Load Databases'
    }
  }

  async testConnection() {
    const form = this.element.querySelector("form")
    const formData = new FormData(form)
    formData.delete("_method")

    await runTestConnection({
      btn: this.testBtnTarget,
      result: this.testResultTarget,
      url: this.hasTestUrlValue ? this.testUrlValue : null,
      fetchOptions: {
        method: "POST",
        headers: {
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content,
          Accept: "application/json",
        },
        body: formData,
      },
    })
  }

  get fieldsModeEnabled() {
    return this.element.querySelector('input[name="sql_database_connection_mode"]:checked')?.value !== "connection_string"
  }

  get discoverySupported() {
    return this.fieldsModeEnabled && DISCOVERY_ADAPTERS.has(this.adapterSelectTarget.value)
  }

  toggleBodyDisabledState(container, disabled) {
    container.querySelectorAll("input, select, textarea").forEach((element) => {
      element.disabled = disabled
    })
  }

  syncAdapterState() {
    const discoverySupported = this.discoverySupported
    const showDatabaseSelect = discoverySupported
    const currentValue = this.currentDatabaseValue()

    if (showDatabaseSelect && currentValue) {
      this.databaseChoices.setChoiceByValue(currentValue)
      this.databaseSelectTarget.value = currentValue
    } else {
      this.databaseManualInputTarget.value = currentValue
    }

    this.databaseSelectWrapperTarget.classList.toggle("hidden", !showDatabaseSelect)
    this.databaseManualWrapperTarget.classList.toggle("hidden", showDatabaseSelect)
    this.databaseLoadRowTarget.classList.toggle("hidden", !discoverySupported)
    this.databaseSelectTarget.disabled = !showDatabaseSelect
    this.databaseSelectTarget.required = showDatabaseSelect
    this.databaseManualInputTarget.disabled = showDatabaseSelect || !this.fieldsModeEnabled
    this.databaseManualInputTarget.required = this.fieldsModeEnabled && !showDatabaseSelect

    this.renderDatabaseHelper()
  }

  renderDatabaseHelper() {
    if (!this.fieldsModeEnabled) {
      this.databaseResultTarget.classList.add("hidden")
      return
    }

    if (this.discoverySupported) {
      const selectedValue = this.currentDatabaseValue()
      const message = selectedValue
        ? `Current selection: ${selectedValue}. Reload the catalog if the server changed.`
        : "Load the server catalog to populate the database dropdown."

      this.databaseHintTarget.textContent = "Load the current catalog from the configured server, then pick the database from the dropdown."
      this.renderStatus(this.databaseResultTarget, "info", message)
      return
    }

    this.databaseHintTarget.textContent = this.adapterSelectTarget.value === "mysql"
      ? "Enter the database name directly for MySQL connections."
      : "SQLite uses a manual database identifier or local file path."

    this.renderStatus(
      this.databaseResultTarget,
      "info",
      this.adapterSelectTarget.value === "mysql"
        ? "MySQL uses manual database name entry."
        : "This adapter uses a manual database identifier or local file path.",
    )
  }

  populateDatabaseChoices(databases, selectedValue = "") {
    const uniqueValues = [...new Set(databases.filter(Boolean))]

    if (selectedValue && !uniqueValues.includes(selectedValue)) {
      uniqueValues.unshift(selectedValue)
    }

    const choices = [
      { value: "", label: uniqueValues.length ? "Select a database..." : "No databases found", selected: !selectedValue },
      ...uniqueValues.map((database) => ({
        value: database,
        label: database,
        selected: database === selectedValue,
      })),
    ]

    this.databaseChoices.clearStore()
    this.databaseChoices.setChoices(choices, "value", "label", true)

    if (selectedValue) {
      this.databaseChoices.setChoiceByValue(selectedValue)
    }

    this.databaseSelectTarget.value = selectedValue || ""
  }

  normalizeDatabases(databases) {
    if (!Array.isArray(databases)) return []

    return databases
      .flatMap((value) => (Array.isArray(value) ? value : [value]))
      .map((value) => String(value).trim())
      .filter(Boolean)
  }

  resetDatabaseChoices(selectedValue = "") {
    this.populateDatabaseChoices(selectedValue ? [selectedValue] : [], selectedValue)
  }

  currentDatabaseValue() {
    if (!this.fieldsModeEnabled) return ""

    return this.discoverySupported ? this.databaseSelectTarget.value : this.databaseManualInputTarget.value
  }

  latestDatabaseValue() {
    return this.databaseSelectTarget.value || this.databaseManualInputTarget.value
  }

  syncPortPlaceholder() {
    if (!this.hasPortInputTarget || !this.hasAdapterSelectTarget) return

    const defaultPort = DEFAULT_PORTS[this.adapterSelectTarget.value]
    this.portInputTarget.placeholder = defaultPort == null ? "" : String(defaultPort)
  }

  renderStatus(target, kind, message) {
    target.className = `ui-wizard__status is-${kind}`
    target.innerHTML = `
      <i class="fa-solid ${this.statusIcon(kind)}"></i>
      <p>${escapeHtml(message)}</p>`
    target.classList.remove("hidden")
  }

  statusIcon(kind) {
    return {
      error: "fa-circle-xmark",
      info: "fa-circle-info",
      success: "fa-circle-check",
    }[kind] || "fa-circle-info"
  }
}
