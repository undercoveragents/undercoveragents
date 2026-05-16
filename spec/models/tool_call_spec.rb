# frozen_string_literal: true

# == Schema Information
#
# Table name: tool_calls
# Database name: primary
#
#  id                :bigint           not null, primary key
#  arguments         :jsonb
#  display_name      :string
#  duration_ms       :integer
#  icon              :string
#  name              :string           not null
#  thought_signature :string
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  message_id        :bigint           not null
#  tool_call_id      :string           not null
#
# Indexes
#
#  index_tool_calls_on_message_id    (message_id)
#  index_tool_calls_on_name          (name)
#  index_tool_calls_on_tool_call_id  (tool_call_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (message_id => messages.id)
#
require "rails_helper"

RSpec.describe ToolCall do
  describe "factory" do
    it "creates a valid tool_call" do
      tool_call = create(:tool_call)
      expect(tool_call).to be_persisted
    end
  end

  describe "associations" do
    it { is_expected.to belong_to(:message) }
  end

  describe "attributes" do
    it "stores the name" do
      tool_call = create(:tool_call, name: "sql_query_test")
      expect(tool_call.name).to eq("sql_query_test")
    end

    it "stores the tool_call_id" do
      tool_call = create(:tool_call, tool_call_id: "call_abc")
      expect(tool_call.tool_call_id).to eq("call_abc")
    end

    it "stores arguments as JSONB" do
      tool_call = create(:tool_call, arguments: { "question" => "test" })
      expect(tool_call.reload.arguments).to eq({ "question" => "test" })
    end

    it "stores duration_ms" do
      tool_call = create(:tool_call, duration_ms: 1234)
      expect(tool_call.reload.duration_ms).to eq(1234)
    end

    it "allows nil duration_ms" do
      tool_call = create(:tool_call, duration_ms: nil)
      expect(tool_call.reload.duration_ms).to be_nil
    end

    it "stores display metadata for builtin runtime tools" do
      tool_call = create(:tool_call, name: "read_mission_flow")

      expect(tool_call.display_name).to eq("Read Mission Flow")
      expect(tool_call.icon).to eq("fa-solid fa-diagram-project")
    end

    it "stores display metadata for assigned tool runtime names" do
      sql_query = create(:tools_sql_query, tool_name: "Orders Explorer")
      agent = create(:agent)
      agent.tool_ids = [sql_query._tool_record.id]
      agent.save!
      chat = create(:chat, agent:)
      message = create(:message, chat:, role: :assistant, content: "Done")

      tool_call = create(:tool_call, message:, name: "sql_query_orders_explorer")

      expect(tool_call.display_name).to eq("Orders Explorer")
      expect(tool_call.icon).to eq("fa-solid fa-database")
    end
  end

  describe "#sync_display_metadata!" do
    it "fills blank display metadata using the resolver" do
      message = create(:message, role: :assistant, content: "Done")
      tool_call = build(:tool_call, message:, name: "read_mission_flow", display_name: nil, icon: nil)

      tool_call.sync_display_metadata!

      expect(tool_call.reload.display_name).to eq("Read Mission Flow")
      expect(tool_call.icon).to eq("fa-solid fa-diagram-project")
    end

    it "leaves existing metadata untouched" do
      tool_call = create(:tool_call, name: "read_mission_flow", display_name: "Custom Label", icon: "fa-solid fa-star")

      tool_call.sync_display_metadata!

      expect(tool_call.reload.display_name).to eq("Custom Label")
      expect(tool_call.icon).to eq("fa-solid fa-star")
    end
  end
end
