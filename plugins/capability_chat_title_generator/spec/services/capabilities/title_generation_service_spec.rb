# frozen_string_literal: true

require "rails_helper"

RSpec.describe Capabilities::TitleGenerationService do
  let(:llm_connector) { create(:connector, :llm_provider, :enabled) }
  let(:agent) do
    create(:agent, llm_connector:).tap do |record|
      record.set_capability_config("chat_title_generator", {
                                     "max_length" => 30,
                                     "max_turns" => 3,
                                     "llm_config_source" => "inherit",
                                     "temperature" => 0.7,
                                   }, enabled: true,)
      record.save!
    end
  end
  let(:chat) { create(:chat, :playground_context, agent:) }

  let(:service) { described_class.new(agent.capability(:chat_title_generator)) }

  before do
    create(:message, :user, chat:, content: "Show me user data")
    create(:message, :assistant, chat:, content: "Here is the user data...")

    llm_response = instance_double(RubyLLM::Message, content: "User Data Query")
    llm_chat = instance_double(Chat, ask: llm_response)
    allow(BuiltinAgents::Runner).to receive(:build_chat!).and_return(llm_chat)
  end

  it "updates chat title" do
    service.handle(:chat_response_completed, chat:)
    expect(chat.reload.title).to eq("User Data Query")
    expect(BuiltinAgents::Runner).to have_received(:build_chat!).with(
      hash_including(
        builtin_key: "chat_title_generator",
        title: "Title Generation",
        parent_chat: chat,
        execution_context: :system,
        input_values: { max_length: 30 },
      ),
    )
  end

  it "ignores unrelated events" do
    original_title = chat.title

    service.handle(:chat_created, chat:)

    expect(chat.reload.title).to eq(original_title)
    expect(BuiltinAgents::Runner).not_to have_received(:build_chat!)
  end
end
