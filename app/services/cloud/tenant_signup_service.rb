# frozen_string_literal: true

module Cloud
  class TenantSignupService
    Result = Data.define(:success?, :tenant, :user, :errors)
    GENERATED_WORKSPACE_SUFFIX = " workspace"
    MAX_TENANT_NAME_LENGTH = 120

    def initialize(admin_email:, password: nil, password_confirmation: nil, oauth_identity: nil, tenant_name: nil)
      @tenant_name = tenant_name.to_s.strip.presence
      @admin_email = admin_email.to_s.strip.downcase
      @password = password
      @password_confirmation = password_confirmation
      @provider = oauth_identity&.fetch(:provider, nil)
      @uid = oauth_identity&.fetch(:uid, nil)
    end

    def call
      tenant = Tenant.new(name: resolved_tenant_name)
      user = build_user(tenant)

      validate_records(tenant, user)
      return failure_result(tenant, user) if tenant.errors.any? || user.errors.any?

      Tenant.transaction do
        tenant.save!
        tenant.ensure_core_resources!
        user.save!
      end

      Result.new(success?: true, tenant:, user:, errors: [])
    rescue ActiveRecord::RecordInvalid
      failure_result(tenant, user)
    end

    private

    def build_user(tenant)
      attributes = {
        tenant:,
        email: @admin_email,
        role: :admin,
        status: :active,
      }

      if oauth_signup?
        User.new(attributes.merge(provider: @provider, uid: @uid))
      else
        User.new(attributes.merge(password: @password, password_confirmation: @password_confirmation))
      end
    end

    def validate_records(tenant, user)
      tenant.valid?
      user.valid?
      user.errors.add(:uid, :blank) if oauth_signup? && @uid.blank?
    end

    def failure_result(tenant, user)
      Result.new(
        success?: false,
        tenant:,
        user:,
        errors: tenant.errors.full_messages + user.errors.full_messages,
      )
    end

    def oauth_signup?
      @provider.present?
    end

    def resolved_tenant_name
      @tenant_name || generated_tenant_name
    end

    def generated_tenant_name
      sequence = 1

      loop do
        candidate = generated_tenant_name_candidate(sequence)
        return candidate unless tenant_name_taken?(candidate)

        sequence += 1
      end
    end

    def generated_tenant_name_candidate(sequence)
      suffix = sequence == 1 ? GENERATED_WORKSPACE_SUFFIX : "#{GENERATED_WORKSPACE_SUFFIX} #{sequence}"
      label = workspace_label.truncate(MAX_TENANT_NAME_LENGTH - suffix.length, omission: "")

      "#{label.presence || "new"}#{suffix}"
    end

    def workspace_label
      @admin_email.split("@").first.to_s.strip
    end

    def tenant_name_taken?(candidate)
      Tenant.exists?(["LOWER(name) = ?", candidate.downcase])
    end
  end
end
