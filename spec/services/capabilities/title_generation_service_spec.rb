# frozen_string_literal: true

require "rails_helper"

RSpec.describe Capabilities::TitleGenerationService do
  let(:llm_connector) { create(:connector, :llm_provider, :enabled) }
  let(:agent) do
    a = create(:agent, llm_connector:)
    a.set_capability_config("chat_title_generator", {
                              "max_length" => 30,
                              "max_turns" => 3,
                              "llm_config_source" => "inherit",
                              "temperature" => 0.7,
                            }, enabled: true,)
    a.save!
    a
  end
  let(:chat) { create(:chat, :playground_context, agent:) }

  let(:capabilitable) { agent.capability(:chat_title_generator) }
  let(:service) { described_class.new(capabilitable) }

  let(:llm_chat_double) { double("RubyLLM::Chat").as_null_object } # rubocop:disable RSpec/VerifiedDoubles
  let(:llm_response) { instance_double(RubyLLM::Message, content: "User Data Query") }

  # Convenience wrapper — mirrors EventDispatcher's call pattern
  def handle_event(target_chat = chat)
    service.handle(:chat_response_completed, chat: target_chat)
  end

  before do
    create(:model, model_id: "gpt-4.1") unless Model.exists?(model_id: "gpt-4.1")
    allow_any_instance_of(Chat).to receive(:with_model).and_return(nil) # rubocop:disable RSpec/AnyInstance
    allow_any_instance_of(Chat).to receive(:with_temperature).and_return(nil) # rubocop:disable RSpec/AnyInstance
    allow_any_instance_of(Chat).to receive(:context=) # rubocop:disable RSpec/AnyInstance
    allow_any_instance_of(Chat).to receive(:to_llm).and_return(llm_chat_double) # rubocop:disable RSpec/AnyInstance
    allow_any_instance_of(Chat).to receive(:ask).and_return(llm_response) # rubocop:disable RSpec/AnyInstance
  end

  describe "#handle" do
    context "when capability is within turn window" do
      before do
        create(:message, :user, chat:, content: "Show me user data")
        create(:message, :assistant, chat:, content: "Here is the user data...")
      end

      it "generates a title for the chat" do
        handle_event
        expect(chat.reload.title).to eq("User Data Query")
      end

      it "creates a system chat for title generation" do
        expect { handle_event }.to change(Chat, :count).by(1)
        title_chat = Chat.last
        expect(title_chat.execution_context).to eq("system")
        expect(title_chat.parent_chat).to eq(chat)
      end

      it "broadcasts the playground title update" do
        allow(ActionCable.server).to receive(:broadcast)
        handle_event

        expect(ActionCable.server).to have_received(:broadcast).with(
          chat.ui_stream_channel_name,
          hash_including(
            type: "chat_title",
            chat_id: chat.id,
            target: "chat-#{chat.id}-title",
            title: "User Data Query",
          ),
        )
      end
    end

    context "when no user messages exist" do
      it "does not generate a title" do
        expect { handle_event }.not_to(change { chat.reload.title })
      end
    end

    context "when user turns exceed max_turns" do
      before do
        4.times do |i|
          create(:message, :user, chat:, content: "Message #{i}")
          create(:message, :assistant, chat:, content: "Response #{i}")
        end
      end

      it "does not generate a title" do
        expect { handle_event }.not_to(change { chat.reload.title })
      end
    end

    context "when the chat has no agent" do
      let(:agentless_chat) { create(:chat, :playground_context, agent: nil) }
      let(:capabilitable) { Capabilities::TitleGenerator.new(max_length: 30, max_turns: 3) }

      it "does not generate a title" do
        expect { handle_event(agentless_chat) }.not_to(change { agentless_chat.reload.title })
      end
    end

    context "when the LLM returns a blank response" do
      let(:blank_response) { instance_double(RubyLLM::Message, content: "") }

      before do
        create(:message, :user, chat:, content: "Hello")
        allow_any_instance_of(Chat).to receive(:ask).and_return(blank_response) # rubocop:disable RSpec/AnyInstance
      end

      it "does not update the title" do
        expect { handle_event }.not_to(change { chat.reload.title })
      end
    end

    context "when the LLM returns a nil response content" do
      let(:nil_response) { instance_double(RubyLLM::Message, content: nil) }

      before do
        create(:message, :user, chat:, content: "Hello")
        allow_any_instance_of(Chat).to receive(:ask).and_return(nil_response) # rubocop:disable RSpec/AnyInstance
      end

      it "does not update the title" do
        expect { handle_event }.not_to(change { chat.reload.title })
      end
    end

    context "when the LLM returns a quoted title" do
      let(:quoted_response) { instance_double(RubyLLM::Message, content: '"My Great Title"') }

      before do
        create(:message, :user, chat:, content: "Hello")
        allow_any_instance_of(Chat).to receive(:ask).and_return(quoted_response) # rubocop:disable RSpec/AnyInstance
      end

      it "strips surrounding quotes from the title" do
        handle_event
        expect(chat.reload.title).to eq("My Great Title")
      end
    end

    context "when title generation fails" do
      before do
        create(:message, :user, chat:, content: "Hello")
        allow_any_instance_of(Chat).to receive(:ask).and_raise(StandardError, "LLM error") # rubocop:disable RSpec/AnyInstance
        allow(Rails.logger).to receive(:error)
      end

      it "logs the error and does not change title" do
        expect { handle_event }.not_to(change { chat.reload.title })
        expect(Rails.logger).to have_received(:error).with(/TitleGenerationService/)
      end
    end

    context "with custom LLM configuration" do
      let(:custom_connector) { create(:connector, :llm_provider, :enabled) }
      let(:agent) do
        a = create(:agent, llm_connector:)
        a.set_capability_config("chat_title_generator", {
                                  "max_length" => 50,
                                  "max_turns" => 3,
                                  "llm_config_source" => "custom",
                                  "llm_connector_id" => custom_connector.id,
                                  "model_id" => "gpt-4.1-mini",
                                  "temperature" => 0.1,
                                }, enabled: true,)
        a.save!
        a
      end

      before do
        create(:model, model_id: "gpt-4.1-mini") unless Model.exists?(model_id: "gpt-4.1-mini")
        create(:message, :user, chat:, content: "Custom config test")
      end

      it "generates a title successfully" do
        handle_event
        expect(chat.reload.title).to eq("User Data Query")
      end
    end

    context "when custom connector is not found" do
      let(:deleted_connector) { create(:connector, :llm_provider, :enabled) }
      let(:agent) do
        a = create(:agent, llm_connector:)
        a.set_capability_config("chat_title_generator", {
                                  "max_length" => 30,
                                  "max_turns" => 3,
                                  "llm_config_source" => "custom",
                                  "llm_connector_id" => nil,
                                  "model_id" => "gpt-4.1",
                                  "temperature" => 0.5,
                                }, enabled: true,)
        a.save!
        a
      end

      before do
        create(:message, :user, chat:, content: "Hello")
      end

      it "generates a title with nil connector context" do
        handle_event
        expect(chat.reload.title).to eq("User Data Query")
      end
    end

    context "when agent has no llm_connector (nil connector from resolve_connector)" do
      let(:agent_without_connector) do
        a = create(:agent, llm_connector: nil)
        a.set_capability_config("chat_title_generator", {
                                  "max_length" => 30,
                                  "max_turns" => 3,
                                  "llm_config_source" => "inherit",
                                  "temperature" => 0.7,
                                }, enabled: true,)
        a.save!
        a
      end
      let(:chat_without_connector) { create(:chat, :playground_context, agent: agent_without_connector) }

      before do
        create(:message, :user, chat: chat_without_connector, content: "Hello nil connector")
      end

      it "generates a title using nil context (covers connector&.connectable nil safe-nav)" do
        event_service = described_class.new(agent_without_connector.capability(:chat_title_generator))
        event_service.handle(:chat_response_completed, chat: chat_without_connector)
        expect(chat_without_connector.reload.title).to eq("User Data Query")
      end
    end

    context "when message content is nil" do
      before do
        create(:message, :user, chat:, content: nil)
        create(:message, :assistant, chat:, content: nil)
      end

      it "generates a title without errors" do
        handle_event
        expect(chat.reload.title).to eq("User Data Query")
      end
    end

    context "when a non-subscribed event is dispatched" do
      it "does nothing" do
        expect { service.handle(:unknown_event, chat:) }.not_to(raise_error)
      end
    end

    context "when capabilitable is nil" do
      let(:nil_config_service) { described_class.new(nil) }

      before { create(:message, :user, chat:, content: "Hello") }

      it "does not generate a title" do
        expect { nil_config_service.handle(:chat_response_completed, chat:) }
          .not_to(change { chat.reload.title })
      end
    end
  end
end
