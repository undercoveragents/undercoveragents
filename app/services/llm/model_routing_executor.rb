# frozen_string_literal: true

module Llm
  # rubocop:disable Metrics/ClassLength
  class ModelRoutingExecutor
    Route = Data.define(:label, :connector_id, :connector, :model_id, :model_record, :role)

    RETRYABLE_ERRORS = [
      Timeout::Error,
      Faraday::TimeoutError,
      Faraday::ConnectionFailed,
      RubyLLM::RateLimitError,
      RubyLLM::ServiceUnavailableError,
      RubyLLM::OverloadedError,
      RubyLLM::ServerError,
    ].freeze

    # rubocop:disable Metrics/ParameterLists
    def initialize(chat:, primary_route:, routing_config:, temperature:, thinking_effort:, thinking_budget:,
                   custom_params:, tools_present:, response_format: nil, response_schema: nil)
      @chat = chat
      @primary_route = primary_route
      @routing_config = Llm::ModelRoutingConfig.normalize(routing_config)
      @temperature = temperature
      @thinking_effort = thinking_effort
      @thinking_budget = thinking_budget
      @custom_params = custom_params
      @response_format = response_format
      @response_schema = response_schema
      @tools_present = tools_present
    end
    # rubocop:enable Metrics/ParameterLists

    def enabled?
      strategy != Llm::ModelRoutingConfig::DEFAULT_STRATEGY
    end

    def canary_selected_route
      return primary_route unless strategy == "canary"

      route = canary_route
      return primary_route unless route
      return primary_route unless active_canary_rollout?

      route
    end

    # rubocop:disable Style/ArgumentsForwarding
    def ask(message = nil, with: nil, &block)
      comparison_seed = build_comparison_seed if strategy == "ab_test"
      response, attempts = execute_primary(message, with:, &block)
      comparison = execute_comparison(message, comparison_seed:, with:)
      persist_metadata(attempts:, comparison:)
      response
    end
    # rubocop:enable Style/ArgumentsForwarding

    private

    attr_reader :chat, :custom_params, :primary_route, :response_format, :response_schema, :temperature,
                :thinking_budget, :thinking_effort, :tools_present

    def strategy
      @routing_config.fetch("strategy", Llm::ModelRoutingConfig::DEFAULT_STRATEGY)
    end

    def execute_primary(message = nil, with: nil, &block)
      attempts = []
      last_error = nil

      candidate_routes.each do |route|
        started_at = Time.current
        streamed = false

        begin
          response = perform_route(route, message, with:) do |chunk|
            streamed = true
            block&.call(chunk)
          end

          attempts << attempt_payload(route:, status: "success")
          return [response, attempts]
        rescue StandardError => e
          attempts << attempt_payload(route:, status: "failed", error: e)
          last_error = e
          raise unless fallback_retryable?(e, started_at:, streamed:)
        end
      end

      raise last_error if last_error
    end

    def execute_comparison(message = nil, comparison_seed:, with: nil)
      return unless strategy == "ab_test"
      return { "status" => "skipped", "reason" => "tools_present" } if tools_present

      route = comparison_route
      return { "status" => "skipped", "reason" => "comparison_model_missing" } unless route

      response = perform_comparison_route(route, message, with:, comparison_seed:)
      {
        "status" => "success",
        "route" => route_payload(route),
        "content" => extract_response_content(response),
      }
    rescue StandardError => e
      {
        "status" => "failed",
        "route" => route_payload(route),
        "error_class" => e.class.name,
        "error_message" => e.message,
      }
    end

    # rubocop:disable Style/ArgumentsForwarding
    def perform_route(route, message = nil, with: nil, &block)
      apply_route!(route)
      chat.send(:perform_ask_without_routing, message, with:, &block)
    end
    # rubocop:enable Style/ArgumentsForwarding

    def perform_comparison_route(route, message = nil, comparison_seed:, with: nil)
      comparison_chat = build_comparison_chat(route, comparison_seed:)
      return comparison_chat.ask(message) if with.nil?

      comparison_chat.ask(message, with:)
    end

    # rubocop:disable Metrics/AbcSize
    def apply_route!(route)
      chat.context = route.connector.build_context
      chat.with_model(route.model_id)
      Llm::ChatOptions.apply_to_chat(
        chat:,
        model_id: route.model_id,
        model_record: route.model_record,
        tools_present:,
        temperature:,
        thinking_effort:,
        thinking_budget:,
        custom_params:,
        response_format:,
        response_schema:,
      )

      return unless chat.persisted?
      return if route.model_record.blank? || chat[:model_id] == route.model_record.id

      persist_chat_model_record(route)
    end
    # rubocop:enable Metrics/AbcSize

    def candidate_routes
      @candidate_routes ||= begin
        base_route = canary_selected_route
        routes = [base_route]

        if strategy == "fallback"
          routes.concat(fallback_routes)
        elsif strategy == "canary" && base_route.role == "canary"
          routes << primary_route
        end

        routes.compact
      end
    end

    def fallback_routes
      Array(@routing_config["fallback_models"]).filter_map do |route|
        build_route(route, label: "fallback", role: "fallback")
      end
    end

    def canary_route
      @canary_route ||= build_route(@routing_config["canary_model"], label: "canary", role: "canary")
    end

    def comparison_route
      @comparison_route ||= build_route(@routing_config["comparison_model"], label: "comparison", role: "comparison")
    end

    def build_route(route_config, label:, role:)
      return if route_config.blank?

      connector = chat.send(:resolve_routing_connector, route_config["connector_id"])
      return if connector.blank?

      model_id = route_config["model_id"].to_s.presence
      model_record = Llm::ChatOptions.resolve_model(model_id)
      return if model_id.blank?

      Route.new(
        label:,
        connector_id: connector.id,
        connector:,
        model_id:,
        model_record:,
        role:,
      )
    end

    def active_canary_rollout?
      percent = @routing_config["canary_percent"].to_i
      percent.positive? && rand(100) < percent
    end

    def fallback_retryable?(error, started_at:, streamed:)
      return false unless RETRYABLE_ERRORS.any? { |klass| error.is_a?(klass) }
      return false if streamed
      return false if partial_response_recorded?(started_at)

      true
    end

    def partial_response_recorded?(started_at)
      assistant_activity = chat.messages.assistant
                               .where(created_at: started_at..)
                               .where("COALESCE(content, '') <> '' OR COALESCE(thinking_text, '') <> ''")
                               .exists?
      return true if assistant_activity

      ToolCall.joins(:message)
              .where(messages: { chat_id: chat.id })
              .exists?(["tool_calls.created_at >= ?", started_at])
    end

    def persist_metadata(attempts:, comparison:)
      message = latest_assistant_message
      return if message.blank?

      payload = {
        "strategy" => strategy,
        "primary_route" => route_payload(primary_route),
        "attempts" => attempts,
      }
      payload["comparison"] = comparison if comparison.present?

      existing_content_raw = message.content_raw
      message.update!(
        content_raw: merged_content_raw(existing_content_raw, payload),
        updated_at: Time.current,
      )
    end

    def latest_assistant_message
      chat.messages.assistant.order(:created_at, :id).last
    end

    def build_comparison_seed
      {
        messages: ordered_existing_messages.map(&:to_llm),
        runtime_instructions: chat.send(:runtime_instructions).dup,
      }
    end

    def build_comparison_chat(route, comparison_seed:)
      comparison_chat = route.connector.build_context.chat(
        model: route.model_id,
        provider: route.connector.provider.to_sym,
      )

      seed_comparison_chat(comparison_chat, comparison_seed)
      apply_comparison_chat_options(comparison_chat, route)

      comparison_chat
    end

    def ordered_existing_messages
      messages = chat.messages.order(:created_at, :id).to_a
      system_messages, non_system_messages = messages.partition { |message| message.role.to_s == "system" }
      system_messages + non_system_messages
    end

    def merged_content_raw(existing_content_raw, payload)
      if existing_content_raw.is_a?(Hash)
        existing_content_raw.merge("model_routing" => payload)
      elsif existing_content_raw.present?
        { "provider_content_raw" => existing_content_raw, "model_routing" => payload }
      else
        { "model_routing" => payload }
      end
    end

    def attempt_payload(route:, status:, error: nil)
      payload = route_payload(route).merge("status" => status)
      return payload unless error

      payload.merge(
        "error_class" => error.class.name,
        "error_message" => error.message,
      )
    end

    def route_payload(route)
      {
        "label" => route.label,
        "role" => route.role,
        "connector_id" => route.connector_id,
        "model_id" => route.model_id,
      }
    end

    def extract_response_content(response)
      return response.content if response.respond_to?(:content)

      response.to_s
    end

    def persist_chat_model_record(route)
      chat.update!(model: route.model_record)
    end

    def seed_comparison_chat(comparison_chat, comparison_seed)
      comparison_seed.fetch(:messages, []).each do |message|
        comparison_chat.add_message(message)
      end

      comparison_seed.fetch(:runtime_instructions, []).each_with_index do |instruction, index|
        comparison_chat.with_instructions(instruction, append: index.positive?)
      end
    end

    def apply_comparison_chat_options(comparison_chat, route)
      Llm::ChatOptions.apply_to_chat(
        chat: comparison_chat,
        model_id: route.model_id,
        model_record: route.model_record,
        tools_present: false,
        temperature:,
        thinking_effort:,
        thinking_budget:,
        custom_params:,
        response_format:,
        response_schema:,
      )
    end
  end
  # rubocop:enable Metrics/ClassLength
end
