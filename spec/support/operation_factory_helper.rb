# frozen_string_literal: true

# Provides a shared helper to find or create the Default operation for use in factories.
# Factories that build resources requiring an operation use this to ensure they land
# in the same operation used by the session fallback (ApplicationController#current_operation).
module OperationFactoryHelper
  def self.default_operation
    tenant = Tenant.default_tenant
    tenant.ensure_core_resources!
    tenant.default_operation
  end
end
