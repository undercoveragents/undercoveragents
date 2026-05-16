# frozen_string_literal: true

module AuthenticationHelpers
  def sign_in(user = nil)
    user ||= create(:user, :admin, tenant: default_tenant)
    post sessions_path, params: { email: user.email, password: "Password123!" }
    user
  end

  def default_tenant
    @default_tenant ||= Tenant.default_tenant.tap(&:ensure_core_resources!)
  end

  def default_operation
    @default_operation ||= default_tenant.default_operation
  end
end

RSpec.configure do |config|
  config.include AuthenticationHelpers, type: :request

  # Auto-sign in for all request specs. Use `unauthenticated: true` metadata to skip.
  config.before(:each, type: :request) do |example|
    sign_in unless example.metadata[:unauthenticated]
  end
end
