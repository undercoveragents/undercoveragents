/**
 * Shared helper for handling connector-change events that update a Turbo Frame
 * with model options from the server.
 *
 * @param {Event} event - The change event from a connector select
 * @param {string} modelOptionsUrl - Base URL for fetching model options
 * @param {string} frameId - DOM id of the Turbo Frame to update
 * @param {object} [extraParams={}] - Additional query params to include
 */
export function handleConnectorChange(event, modelOptionsUrl, frameId, extraParams = {}) {
  const connectorId = event.target.value
  const frame = document.getElementById(frameId)
  if (!frame) return

  const url = new URL(modelOptionsUrl, window.location.origin)
  if (connectorId) url.searchParams.set("connector_id", connectorId)

  for (const [key, value] of Object.entries(extraParams)) {
    if (value) url.searchParams.set(key, value)
  }

  frame.src = url.pathname + url.search
}
