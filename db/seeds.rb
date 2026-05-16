# frozen_string_literal: true

# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# ── Default Tenant & System Admin ─────────────────────────────────────────────
admin_email = ENV.fetch("ADMIN_EMAIL", "admin@localhost")
admin_password = ENV.fetch("ADMIN_PASSWORD", "Changeme123!")

default_tenant = Tenant.find_or_create_by!(name: "Default Tenant") do |tenant|
  tenant.description = "Default tenant for the application bootstrap data and initial administration."
  Rails.logger.info "Created default tenant: Default Tenant"
end

default_tenant.ensure_core_resources!

User.find_or_create_by!(email: admin_email) do |user|
  user.password = admin_password
  user.role = "system_admin"
  user.status = "active"
  user.tenant = default_tenant
  Rails.logger.info "Created default system admin user: #{admin_email}"
end

# ───────────────────────────────────────────────────────────────────────────────
Model.refresh!
BuiltinAgents::Synchronizer.ensure_present!(tenant: default_tenant)
BuiltinTestSuites::Synchronizer.ensure_present!(tenant: default_tenant)
