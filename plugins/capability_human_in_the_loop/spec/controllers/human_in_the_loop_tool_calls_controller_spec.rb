# frozen_string_literal: true

require "rails_helper"

RSpec.describe HumanInTheLoopToolCallsController do
  describe "#tool_call_accessible?" do
    let(:user) { create(:user) }

    before do
      allow(controller).to receive(:current_user).and_return(user)
    end

    it "returns false when the tool call has no message" do
      controller.instance_variable_set(
        :@tool_call,
        instance_double(
          ToolCall,
          human_in_the_loop_tool_call?: true,
          message: nil,
        ),
      )

      expect(controller.send(:tool_call_accessible?)).to be(false)
    end

    it "returns false when the tool call message has no chat" do
      controller.instance_variable_set(
        :@tool_call,
        instance_double(
          ToolCall,
          human_in_the_loop_tool_call?: true,
          message: instance_double(Message, chat: nil),
        ),
      )

      expect(controller.send(:tool_call_accessible?)).to be(false)
    end
  end

  describe "#response_params" do
    it "converts plain hash payloads without requiring ActionController parameters" do
      allow(controller).to receive(:params).and_return(
        { responses: { "question_1" => { "selected_option" => "Blue" } } }.with_indifferent_access,
      )

      expect(controller.send(:response_params)).to eq(
        "question_1" => { "selected_option" => "Blue" },
      )
    end
  end
end
