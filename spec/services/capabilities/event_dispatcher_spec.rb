# frozen_string_literal: true

require "rails_helper"

RSpec.describe Capabilities::EventDispatcher do
  let(:llm_connector) { create(:connector, :llm_provider, :enabled) }

  def enable_title_generator(agent, enabled: true)
    agent.set_capability_config("chat_title_generator", {
                                  "max_length" => 30,
                                  "max_turns" => 3,
                                  "llm_config_source" => "inherit",
                                  "temperature" => 0.7,
                                }, enabled:,)
    agent.save!
  end

  describe ".dispatch" do
    context "when the chat has an agent with an enabled capability" do
      let(:agent) do
        a = create(:agent, llm_connector:)
        enable_title_generator(a)
        a
      end
      let(:chat) { create(:chat, :playground_context, agent:) }

      it "instantiates the handler and calls handle" do
        handler_double = instance_double(Capabilities::TitleGenerationService)
        allow(Capabilities::TitleGenerationService).to receive(:new).and_return(handler_double)
        allow(handler_double).to receive(:handle)

        described_class.dispatch(:chat_response_completed, chat:)

        expect(handler_double).to have_received(:handle).with(:chat_response_completed, chat:)
      end

      it "returns true when a handler was invoked" do
        allow_any_instance_of(Capabilities::TitleGenerationService).to receive(:handle) # rubocop:disable RSpec/AnyInstance
        result = described_class.dispatch(:chat_response_completed, chat:)
        expect(result).to be(true)
      end
    end

    context "when the agent has only disabled capabilities" do
      let(:agent) do
        a = create(:agent, llm_connector:)
        enable_title_generator(a, enabled: false)
        a
      end
      let(:chat) { create(:chat, :playground_context, agent:) }

      it "returns false without calling any handler" do
        result = described_class.dispatch(:chat_response_completed, chat:)
        expect(result).to be(false)
      end
    end

    context "when the chat has no agent" do
      let(:chat) { create(:chat, :playground_context, agent: nil) }

      it "returns false gracefully" do
        result = described_class.dispatch(:chat_response_completed, chat:)
        expect(result).to be(false)
      end
    end

    context "when a handler raises an error" do
      let(:agent) do
        a = create(:agent, llm_connector:)
        enable_title_generator(a)
        a
      end
      let(:chat) { create(:chat, :playground_context, agent:) }

      it "logs the error and continues without re-raising" do
        allow_any_instance_of(Capabilities::TitleGenerationService) # rubocop:disable RSpec/AnyInstance
          .to receive(:handle).and_raise(StandardError, "boom")
        allow(Rails.logger).to receive(:error)

        expect { described_class.dispatch(:chat_response_completed, chat:) }.not_to raise_error
        expect(Rails.logger).to have_received(:error).with(/EventDispatcher/)
      end
    end

    context "when a capability type has a nil event_handler_class" do
      let(:agent) do
        a = create(:agent, llm_connector:)
        enable_title_generator(a)
        a
      end
      let(:chat) { create(:chat, :playground_context, agent:) }

      before do
        allow(Capabilities::TitleGenerator).to receive(:event_handler_class).and_return(nil)
      end

      it "skips the capability and returns false" do
        result = described_class.dispatch(:chat_response_completed, chat:)
        expect(result).to be(false)
      end
    end

    context "when the payload does not include a :chat key" do
      it "returns false gracefully without raising" do
        result = described_class.dispatch(:chat_response_completed, something_else: "value")
        expect(result).to be(false)
      end
    end

    context "when a capability has a nil configurator" do
      let(:agent) do
        a = create(:agent, llm_connector:)
        enable_title_generator(a)
        a
      end
      let(:chat) { create(:chat, :playground_context, agent:) }

      before do
        allow_any_instance_of(HasCapabilities::CapabilityEntry).to receive(:configurator).and_return(nil) # rubocop:disable RSpec/AnyInstance
      end

      it "skips the capability and returns false" do
        result = described_class.dispatch(:chat_response_completed, chat:)
        expect(result).to be(false)
      end
    end
  end
end
