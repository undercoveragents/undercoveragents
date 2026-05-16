# frozen_string_literal: true

module ConnectorLookup
  module_function

  def find(connector_id, tenant: nil)
    return nil if connector_id.blank?

    return tenant.connectors.find_by(id: connector_id) if tenant.present?

    Connector.find_by(id: connector_id)
  end
end
