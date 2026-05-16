import { escapeHtml } from "utils/html"

export function renderTestSuccess(result, data, { includeToolNames = false } = {}) {
  const version = data.details?.version
    ? `<span class="text-xs ml-2" style="color: var(--text-muted);">${escapeHtml(data.details.version)}</span>`
    : ""
  const toolNames = includeToolNames ? data.details?.tool_names : null
  const toolsInfo = toolNames && toolNames.length > 0
    ? `<div class="mt-2 text-xs" style="color: var(--text-muted);"><span class="font-medium">Tools:</span> ${toolNames.map((name) => escapeHtml(name)).join(", ")}</div>`
    : ""

  result.className = "test-connection-result test-connection-success"
  result.innerHTML = `
    <div class="flex items-center gap-2">
      <i class="fa-solid fa-circle-check"></i>
      <span class="font-medium">${escapeHtml(data.message)}</span>
    </div>
    ${version ? `<div class="mt-1">${version}</div>` : ""}
    ${toolsInfo}`
}

export function renderTestFailure(result, message) {
  result.className = "test-connection-result test-connection-error"
  result.innerHTML = `
    <div class="flex items-start gap-2">
      <i class="fa-solid fa-circle-xmark mt-0.5"></i>
      <div>
        <span class="font-medium">Connection failed</span>
        <p class="mt-1 text-xs font-mono whitespace-pre-wrap" style="opacity: 0.9;">${escapeHtml(message)}</p>
      </div>
    </div>`
}

export function renderTestError(result, error) {
  result.className = "test-connection-result test-connection-error"
  result.innerHTML = `
    <div class="flex items-start gap-2">
      <i class="fa-solid fa-circle-xmark mt-0.5"></i>
      <div>
        <span class="font-medium">Request failed</span>
        <p class="mt-1 text-xs font-mono whitespace-pre-wrap" style="opacity: 0.9;">${escapeHtml(error.message || "Could not reach the server")}</p>
      </div>
    </div>`
}

export async function runTestConnection({ btn, result, url, fetchOptions, includeToolNames = false }) {
  btn.disabled = true
  btn.innerHTML = '<i class="fa-solid fa-spinner fa-spin mr-1"></i>Testing connection...'
  result.innerHTML = ""
  result.className = "test-connection-result"

  try {
    if (!url) {
      throw new Error("Missing test connection endpoint")
    }

    const response = await fetch(url, fetchOptions)

    if (!response.ok && response.headers.get("content-type")?.indexOf("application/json") === -1) {
      throw new Error(`Server error (HTTP ${response.status})`)
    }

    const data = await response.json()

    if (data.success) {
      renderTestSuccess(result, data, { includeToolNames })
    } else {
      renderTestFailure(result, data.message)
    }
  } catch (error) {
    console.error("Test connection error:", error)
    renderTestError(result, error)
  } finally {
    btn.disabled = false
    btn.innerHTML = '<i class="fa-solid fa-plug-circle-check mr-1"></i>Test Connection'
  }
}
