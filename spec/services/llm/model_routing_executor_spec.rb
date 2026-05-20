# frozen_string_literal: true

require "rails_helper"

# rubocop:disable RSpec/MultipleMemoizedHelpers
RSpec.describe Llm::ModelRoutingExecutor do
  let(:tenant) { create(:tenant) }
  let(:operation) { create(:operation, tenant:) }
  let(:primary_connector) { create(:connector, :llm_provider, :enabled, tenant:) }
  let(:fallback_connector) { create(:connector, :llm_provider, :enabled, tenant:) }
  let(:comparison_connector) { create(:connector, :llm_provider, :enabled, tenant:) }
  let(:primary_model) { create(:model, model_id: "gpt-primary", provider: primary_connector.provider) }
  let(:fallback_model) { create(:model, model_id: "gpt-fallback", provider: fallback_connector.provider) }
  let(:comparison_model) { create(:model, model_id: "gpt-compare", provider: comparison_connector.provider) }
  let(:agent) { create(:agent, operation:, llm_connector: primary_connector, model_id: primary_model.model_id) }
  let(:chat) { create(:chat, agent:, model: primary_model) }
  let(:primary_route) do
    described_class::Route.new(
      label: "primary",
      connector_id: primary_connector.id,
      connector: primary_connector,
      model_id: primary_model.model_id,
      model_record: primary_model,
      role: "primary",
    )
  end

  before do
    allow(chat).to receive(:context=)
    allow(chat).to receive(:with_model)
    allow(Llm::ChatOptions).to receive(:apply_to_chat)
  end

  describe "#ask" do
    # rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
    it "retries on retryable fallback errors and records each attempt" do
      allow(primary_connector).to receive(:build_context).and_return(instance_double(Object))
      allow(fallback_connector).to receive(:build_context).and_return(instance_double(Object))
      allow(chat).to receive(:resolve_routing_connector).with(fallback_connector.id).and_return(fallback_connector)

      call_count = 0
      allow(chat).to receive(:perform_ask_without_routing) do
        call_count += 1

        raise RubyLLM::RateLimitError, "primary unavailable" if call_count == 1

        create(:message, :assistant, chat:, model: fallback_model, content: "Fallback reply")
        double("response", content: "Fallback reply") # rubocop:disable RSpec/VerifiedDoubles
      end

      executor = described_class.new(
        chat:,
        primary_route:,
        routing_config: {
          "strategy" => "fallback",
          "fallback_models" => [{ "connector_id" => fallback_connector.id, "model_id" => fallback_model.model_id }],
        },
        temperature: 0.4,
        thinking_effort: "medium",
        thinking_budget: 256,
        custom_params: { "top_p" => 0.9 },
        tools_present: false,
      )

      response = executor.ask("Hello")

      expect(response.content).to eq("Fallback reply")
      expect(call_count).to eq(2)
      expect(chat).to have_received(:with_model).with(primary_model.model_id)
      expect(chat).to have_received(:with_model).with(fallback_model.model_id)

      routing = chat.messages.assistant.last.content_raw.fetch("model_routing")
      expect(routing["strategy"]).to eq("fallback")
      expect(routing["attempts"].pluck("status")).to eq(["failed", "success"])
      expect(routing["attempts"].pluck("model_id")).to eq([primary_model.model_id, fallback_model.model_id])
    end
    # rubocop:enable RSpec/ExampleLength, RSpec/MultipleExpectations

    # rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
    it "stores ab test comparison output without adding a second persisted assistant message" do
      create(:message, :system, chat:, content: "System context")
      create(:message, :user, chat:, content: "Earlier question")
      chat.send(:store_runtime_instruction, "Runtime guidance", append: false)

      allow(primary_connector).to receive(:build_context).and_return(instance_double(Object))
      comparison_context = instance_double(RubyLLM::Context)
      comparison_chat = instance_double(RubyLLM::Chat)

      allow(chat).to receive(:resolve_routing_connector).with(comparison_connector.id).and_return(comparison_connector)
      allow(comparison_connector).to receive(:build_context).and_return(comparison_context)
      allow(comparison_context).to receive(:chat).and_return(comparison_chat)
      allow(comparison_chat).to receive(:add_message)
      allow(comparison_chat).to receive(:with_instructions)
      allow(comparison_chat).to receive(:ask).and_return(
        double("comparison-response", content: "Comparison reply"), # rubocop:disable RSpec/VerifiedDoubles
      )

      allow(chat).to receive(:perform_ask_without_routing) do
        create(:message, :assistant, chat:, model: primary_model, content: "Primary reply")
        double("primary-response", content: "Primary reply") # rubocop:disable RSpec/VerifiedDoubles
      end

      executor = described_class.new(
        chat:,
        primary_route:,
        routing_config: {
          "strategy" => "ab_test",
          "comparison_model" => { "connector_id" => comparison_connector.id, "model_id" => comparison_model.model_id },
        },
        temperature: nil,
        thinking_effort: nil,
        thinking_budget: nil,
        custom_params: {},
        tools_present: false,
      )

      response = executor.ask("Compare this answer")

      expect(response.content).to eq("Primary reply")
      expect(chat.messages.assistant.count).to eq(1)
      expect(comparison_chat).to have_received(:add_message).twice
      expect(comparison_chat).to have_received(:with_instructions).with("Runtime guidance", append: false)
      expect(comparison_chat).to have_received(:ask).with("Compare this answer")

      routing = chat.messages.assistant.last.content_raw.fetch("model_routing")
      expect(routing.dig("comparison", "status")).to eq("success")
      expect(routing.dig("comparison", "content")).to eq("Comparison reply")
    end
    # rubocop:enable RSpec/ExampleLength, RSpec/MultipleExpectations
  end

  describe "internal routing branches" do
    it "reports whether routing is enabled" do
      default_executor = described_class.new(
        chat:,
        primary_route:,
        routing_config: { "strategy" => "single" },
        temperature: nil,
        thinking_effort: nil,
        thinking_budget: nil,
        custom_params: {},
        tools_present: false,
      )

      expect(default_executor.enabled?).to be(false)
    end

    # rubocop:disable RSpec/ExampleLength
    it "selects the canary route only when the rollout is active" do
      allow(chat).to receive(:resolve_routing_connector).with(comparison_connector.id).and_return(comparison_connector)

      executor = described_class.new(
        chat:,
        primary_route:,
        routing_config: {
          "strategy" => "canary",
          "canary_model" => { "connector_id" => comparison_connector.id, "model_id" => comparison_model.model_id },
          "canary_percent" => 10,
        },
        temperature: nil,
        thinking_effort: nil,
        thinking_budget: nil,
        custom_params: {},
        tools_present: false,
      )

      allow(executor).to receive(:rand).and_return(0, 99)

      expect(executor.canary_selected_route.role).to eq("canary")
      expect(executor.canary_selected_route.role).to eq("primary")

      fresh_executor = described_class.new(
        chat:,
        primary_route:,
        routing_config: {
          "strategy" => "canary",
          "canary_model" => { "connector_id" => comparison_connector.id, "model_id" => comparison_model.model_id },
          "canary_percent" => 10,
        },
        temperature: nil,
        thinking_effort: nil,
        thinking_budget: nil,
        custom_params: {},
        tools_present: false,
      )
      allow(fresh_executor).to receive(:rand).and_return(0)

      expect(fresh_executor.send(:candidate_routes).map(&:role)).to eq(["canary", "primary"])
    end
    # rubocop:enable RSpec/ExampleLength

    # rubocop:disable RSpec/ExampleLength
    it "records failed comparison attempts and supports keyword conversation history" do
      allow(primary_connector).to receive(:build_context).and_return(instance_double(Object))
      comparison_context = instance_double(RubyLLM::Context)
      comparison_chat = instance_double(RubyLLM::Chat)
      allow(chat).to receive(:resolve_routing_connector).with(comparison_connector.id).and_return(comparison_connector)
      allow(comparison_connector).to receive(:build_context).and_return(comparison_context)
      allow(comparison_context).to receive(:chat).and_return(comparison_chat)
      allow(comparison_chat).to receive(:add_message)
      allow(comparison_chat).to receive(:with_instructions)
      allow(comparison_chat).to receive(:ask).and_raise(StandardError, "compare failed")
      allow(chat).to receive(:perform_ask_without_routing) do
        create(:message, :assistant, chat:, model: primary_model, content: "Primary reply")
        double("primary-response", content: "Primary reply") # rubocop:disable RSpec/VerifiedDoubles
      end

      executor = described_class.new(
        chat:,
        primary_route:,
        routing_config: {
          "strategy" => "ab_test",
          "comparison_model" => { "connector_id" => comparison_connector.id, "model_id" => comparison_model.model_id },
        },
        temperature: nil,
        thinking_effort: nil,
        thinking_budget: nil,
        custom_params: {},
        tools_present: false,
      )

      executor.ask("Compare this answer", with: [{ role: "user", content: "Earlier" }])

      expect(comparison_chat).to have_received(:ask).with(
        "Compare this answer",
        with: [{ role: "user", content: "Earlier" }],
      )
      expect(chat.messages.assistant.last.content_raw.dig("model_routing", "comparison", "status")).to eq("failed")
    end
    # rubocop:enable RSpec/ExampleLength

    # rubocop:disable RSpec/ExampleLength
    it "updates persisted chat models and merges routing metadata payloads" do
      allow(primary_connector).to receive(:build_context).and_return(instance_double(Object))
      allow(fallback_connector).to receive(:build_context).and_return(instance_double(Object))
      allow(chat).to receive(:with_model)

      executor = described_class.new(
        chat:,
        primary_route:,
        routing_config: { "strategy" => "fallback" },
        temperature: nil,
        thinking_effort: nil,
        thinking_budget: nil,
        custom_params: {},
        tools_present: false,
      )
      route = described_class::Route.new(
        label: "fallback",
        connector_id: fallback_connector.id,
        connector: fallback_connector,
        model_id: fallback_model.model_id,
        model_record: fallback_model,
        role: "fallback",
      )

      executor.send(:apply_route!, route)

      expect(chat.reload.model).to eq(fallback_model)
      expect(executor.send(:merged_content_raw, { "provider" => "raw" }, { "strategy" => "fallback" }))
        .to include("model_routing" => { "strategy" => "fallback" })
      expect(executor.send(:merged_content_raw, "raw", { "strategy" => "fallback" }))
        .to include("provider_content_raw" => "raw")
      expect(executor.send(:extract_response_content, :plain_text)).to eq("plain_text")
    end
    # rubocop:enable RSpec/ExampleLength

    it "does not retry once partial assistant output has started" do
      executor = described_class.new(
        chat:,
        primary_route:,
        routing_config: { "strategy" => "fallback" },
        temperature: nil,
        thinking_effort: nil,
        thinking_budget: nil,
        custom_params: {},
        tools_present: false,
      )
      started_at = Time.current
      create(:message, :assistant, chat:, model: primary_model, content: "partial", created_at: started_at + 1.second)

      expect(
        executor.send(:fallback_retryable?, RubyLLM::RateLimitError.new("slow"), started_at:, streamed: false),
      ).to be(false)
      expect(executor.send(:execute_comparison, "ignored", comparison_seed: {}, with: nil)).to be_nil
    end

    it "returns skipped comparison metadata when tools are present" do
      executor = described_class.new(
        chat:,
        primary_route:,
        routing_config: { "strategy" => "ab_test" },
        temperature: nil,
        thinking_effort: nil,
        thinking_budget: nil,
        custom_params: {},
        tools_present: true,
      )

      expect(executor.send(:execute_comparison, "ignored", comparison_seed: {}, with: nil)).to eq(
        { "status" => "skipped", "reason" => "tools_present" },
      )
    end

    it "returns skipped comparison metadata when no comparison route can be built" do
      executor = described_class.new(
        chat:,
        primary_route:,
        routing_config: { "strategy" => "ab_test" },
        temperature: nil,
        thinking_effort: nil,
        thinking_budget: nil,
        custom_params: {},
        tools_present: false,
      )

      expect(executor.send(:execute_comparison, "ignored", comparison_seed: {}, with: nil)).to eq(
        { "status" => "skipped", "reason" => "comparison_model_missing" },
      )
    end

    # rubocop:disable RSpec/ExampleLength
    it "streams yielded chunks and re-raises the last retryable failure when every route fails" do
      allow(chat).to receive(:resolve_routing_connector).with(fallback_connector.id).and_return(fallback_connector)

      executor = described_class.new(
        chat:,
        primary_route:,
        routing_config: {
          "strategy" => "fallback",
          "fallback_models" => [{ "connector_id" => fallback_connector.id, "model_id" => fallback_model.model_id }],
        },
        temperature: nil,
        thinking_effort: nil,
        thinking_budget: nil,
        custom_params: {},
        tools_present: false,
      )

      chunk_events = []
      allow(executor).to receive(:perform_route) do |route, _message, with: nil, &block|
        block&.call("chunk-#{route.role}")
        raise RubyLLM::RateLimitError, with.nil? ? "primary unavailable" : "fallback unavailable"
      end
      allow(executor).to receive(:fallback_retryable?).and_return(true)

      expect do
        executor.send(:execute_primary, "Hello", with: [{ role: "user", content: "Earlier" }]) do |chunk|
          chunk_events << chunk
        end
      end.to raise_error(RubyLLM::RateLimitError)
      expect(chunk_events).to include("chunk-primary", "chunk-fallback")
    end
    # rubocop:enable RSpec/ExampleLength

    it "returns the primary route when no canary route is configured" do
      executor = described_class.new(
        chat:,
        primary_route:,
        routing_config: { "strategy" => "canary" },
        temperature: nil,
        thinking_effort: nil,
        thinking_budget: nil,
        custom_params: {},
        tools_present: false,
      )

      expect(executor.canary_selected_route).to eq(primary_route)
    end

    it "does not persist chat model changes for non-persisted chats" do
      draft_chat = build(:chat, agent:, model: primary_model)
      allow(draft_chat).to receive(:context=)
      allow(draft_chat).to receive(:with_model)
      allow(Llm::ChatOptions).to receive(:apply_to_chat)
      allow(fallback_connector).to receive(:build_context).and_return(instance_double(Object))

      executor = described_class.new(
        chat: draft_chat,
        primary_route:,
        routing_config: { "strategy" => "fallback" },
        temperature: nil,
        thinking_effort: nil,
        thinking_budget: nil,
        custom_params: {},
        tools_present: false,
      )
      route = described_class::Route.new(
        label: "fallback",
        connector_id: fallback_connector.id,
        connector: fallback_connector,
        model_id: fallback_model.model_id,
        model_record: fallback_model,
        role: "fallback",
      )

      expect { executor.send(:apply_route!, route) }.not_to change(draft_chat, :model_id)
    end

    # rubocop:disable RSpec/ExampleLength
    it "returns nil when asked to build a blank, connectorless, or model-less route" do
      allow(chat).to receive(:resolve_routing_connector).with(fallback_connector.id).and_return(nil)
      allow(chat).to receive(:resolve_routing_connector).with(primary_connector.id).and_return(primary_connector)

      executor = described_class.new(
        chat:,
        primary_route:,
        routing_config: { "strategy" => "fallback" },
        temperature: nil,
        thinking_effort: nil,
        thinking_budget: nil,
        custom_params: {},
        tools_present: false,
      )

      expect(executor.send(:build_route, nil, label: "fallback", role: "fallback")).to be_nil
      expect(
        executor.send(
          :build_route,
          { "connector_id" => fallback_connector.id, "model_id" => fallback_model.model_id },
          label: "fallback",
          role: "fallback",
        ),
      ).to be_nil
      expect(
        executor.send(
          :build_route,
          { "connector_id" => primary_connector.id, "model_id" => "" },
          label: "fallback",
          role: "fallback",
        ),
      ).to be_nil
    end
    # rubocop:enable RSpec/ExampleLength

    it "returns false for non-retryable and streamed fallback errors" do
      executor = described_class.new(
        chat:,
        primary_route:,
        routing_config: { "strategy" => "fallback" },
        temperature: nil,
        thinking_effort: nil,
        thinking_budget: nil,
        custom_params: {},
        tools_present: false,
      )
      started_at = Time.current

      expect(
        executor.send(:fallback_retryable?, StandardError.new("boom"), started_at:, streamed: false),
      ).to be(false)
      expect(
        executor.send(:fallback_retryable?, RubyLLM::RateLimitError.new("boom"), started_at:, streamed: true),
      ).to be(false)
    end

    it "returns nil when there is no assistant message to persist metadata onto" do
      executor = described_class.new(
        chat:,
        primary_route:,
        routing_config: { "strategy" => "fallback" },
        temperature: nil,
        thinking_effort: nil,
        thinking_budget: nil,
        custom_params: {},
        tools_present: false,
      )

      expect(executor.send(:persist_metadata, attempts: [], comparison: nil)).to be_nil
    end

    it "re-raises non-retryable primary failures immediately" do
      executor = described_class.new(
        chat:,
        primary_route:,
        routing_config: { "strategy" => "fallback" },
        temperature: nil,
        thinking_effort: nil,
        thinking_budget: nil,
        custom_params: {},
        tools_present: false,
      )

      allow(executor).to receive(:perform_route).and_raise(StandardError, "boom")

      expect { executor.send(:execute_primary, "Hello", with: nil) }.to raise_error(StandardError, "boom")
    end

    it "returns nil when execute_primary has no candidate routes and no captured error" do
      executor = described_class.new(
        chat:,
        primary_route:,
        routing_config: { "strategy" => "fallback" },
        temperature: nil,
        thinking_effort: nil,
        thinking_budget: nil,
        custom_params: {},
        tools_present: false,
      )

      allow(executor).to receive(:candidate_routes).and_return([])

      expect(executor.send(:execute_primary, "Hello", with: nil)).to be_nil
    end

    it "tolerates yielded chunks when no caller block is provided" do
      executor = described_class.new(
        chat:,
        primary_route:,
        routing_config: { "strategy" => "fallback" },
        temperature: nil,
        thinking_effort: nil,
        thinking_budget: nil,
        custom_params: {},
        tools_present: false,
      )

      allow(executor).to receive(:perform_route) do |_route, _message, **_kwargs, &block|
        block&.call("chunk")
        double("response", content: "ok") # rubocop:disable RSpec/VerifiedDoubles
      end

      expect(executor.send(:execute_primary, "Hello", with: nil).first.content).to eq("ok")
    end
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
