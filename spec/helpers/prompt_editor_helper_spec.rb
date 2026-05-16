# frozen_string_literal: true

require "rails_helper"

RSpec.describe PromptEditorHelper do
  describe "#build_prompt_editor_config" do
    it "preserves string variables alongside normalized hash variables" do
      config = helper.build_prompt_editor_config(
        variables: ["account_id", { name: "user_id" }, { "name" => "order_id" }],
        show_variables: true,
        system_value: "System prompt",
      )

      expect(config.var_names).to eq(["account_id", "user_id", "order_id"])
      expect(JSON.parse(config.variables_json)).to eq(["account_id", "user_id", "order_id"])
      expect(config.var_labels["account_id"]).to eq("{{account_id}}")
      expect(config.show_variables).to be(true)
    end
  end
end
