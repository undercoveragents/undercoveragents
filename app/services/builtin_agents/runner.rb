# frozen_string_literal: true

module BuiltinAgents
  class Runner
    def self.resolve_tenant(tenant: nil, **options)
      [
        tenant,
        tenant_from_chat(options[:chat]),
        tenant_from_chat(options[:parent_chat]),
        options[:user]&.tenant,
        tenant_from_runtime_context(options.fetch(:runtime_context, {})),
        Current.tenant,
        Tenant.default_tenant,
      ].find(&:present?)
    end

    def self.tenant_from_chat(chat)
      return if chat.blank?

      chat.agent&.operation&.tenant || chat.mission&.operation&.tenant
    end

    def self.tenant_from_runtime_context(runtime_context)
      Array(runtime_context.values).filter_map { |value| tenant_from_runtime_value(value) }.first
    end

    def self.tenant_from_runtime_value(value)
      return value.tenant if value.respond_to?(:tenant) && value.tenant.present?
      return value.operation.tenant if value.respond_to?(:operation) && value.operation.present?

      nil
    end

    def self.build_chat!(builtin_key:, **options)
      agent = BuiltinAgents::Resolver.find!(
        builtin_key,
        tenant: resolve_tenant(**options),
      )
      agent.build_chat(**agent_chat_options(options))
    end

    def self.configure_chat!(chat:, builtin_key:, **options)
      agent = BuiltinAgents::Resolver.find!(
        builtin_key,
        tenant: resolve_tenant(chat:, user: chat.user, **options),
      )
      chat.update!(agent:) if chat.agent_id != agent.id
      chat.configure_for_agent(agent, **agent_chat_options(options))
    end

    def self.ask!(builtin_key:, prompt:, **)
      chat = build_chat!(builtin_key:, **)

      chat.ask(prompt)
    end

    def self.agent_chat_options(options)
      options.except(:tenant, :chat)
    end
  end
end
