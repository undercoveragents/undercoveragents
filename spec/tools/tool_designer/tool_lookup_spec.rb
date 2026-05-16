# frozen_string_literal: true

require "rails_helper"

RSpec.describe ToolDesigner::ToolLookup do
  let(:tenant) { create(:tenant).tap(&:ensure_core_resources!) }
  let(:operation) { tenant.default_operation }
  let(:tool_record) do
    create(
      :tool,
      operation:,
      name: "Orders Explorer",
      toolable: Tools::MissionTool.new(mission_id: create(:mission, operation:).id),
    )
  end
  let(:lookup_class) do
    Class.new do
      include ToolDesigner::ToolLookup

      def initialize(runtime_context: nil, current_tool: nil)
        @runtime_context = runtime_context
        @current_tool = current_tool
      end
    end
  end

  around do |example|
    Current.tenant = nil
    example.run
  ensure
    Current.reset
  end

  it "returns nil for blank identifiers when the current tool is not a Tool" do
    lookup = lookup_class.new(current_tool: Object.new)

    expect(lookup.send(:resolve_tool, nil)).to be_nil
  end

  it "falls back to the current tool tenant and operation" do
    lookup = lookup_class.new(current_tool: tool_record)

    expect(lookup.send(:tenant)).to eq(tenant)
    expect(lookup.send(:operation)).to eq(operation)
  end

  it "scopes lookup by tenant when no operation is available" do
    foreign_tenant = create(:tenant).tap(&:ensure_core_resources!)
    foreign_tool = create(
      :tool,
      operation: foreign_tenant.default_operation,
      name: "Foreign Tool",
      toolable: Tools::MissionTool.new(mission_id: create(:mission, operation: foreign_tenant.default_operation).id),
    )
    runtime_context = BuiltinTools::RuntimeContext::Context.new(
      agent: nil,
      chat: nil,
      mission: nil,
      ui_context: nil,
      user: nil,
      tenant:,
      operation: nil,
    )
    lookup = lookup_class.new(runtime_context:)

    expect(lookup.send(:resolve_tool, tool_record.id)).to eq(tool_record)
    expect { lookup.send(:resolve_tool, foreign_tool.id) }
      .to raise_error(ActiveRecord::RecordNotFound, "Tool '#{foreign_tool.id}' was not found.")
  end

  it "falls back to Current.tenant and then the default tenant" do
    Current.tenant = tenant
    lookup = lookup_class.new

    expect(lookup.send(:tenant)).to eq(tenant)

    Current.reset
    expect(lookup_class.new.send(:tenant)).to eq(Tenant.default_tenant)
  end
end
