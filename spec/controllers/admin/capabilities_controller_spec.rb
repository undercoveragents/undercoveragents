# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::CapabilitiesController do
  describe "#stored_capability_config" do
    it "returns nil when the agent configuration payload is missing" do
      controller.instance_variable_set(:@agent, instance_double(Agent, configuration: nil))
      controller.instance_variable_set(:@capability_key, :chat_title_generator)

      expect(controller.send(:stored_capability_config)).to be_nil
    end
  end

  describe "#render_capability_errors" do
    it "handles configurators without _agent_record=" do
      controller.instance_variable_set(:@agent, create(:agent))
      configurator = Object.new

      allow(controller).to receive(:load_form_data)
      allow(controller).to receive(:render)

      controller.send(:render_capability_errors, configurator)

      expect(controller.instance_variable_get(:@capability_config)).to eq(configurator)
      expect(controller).to have_received(:render).with(:edit, status: :unprocessable_content)
    end
  end
end
