# frozen_string_literal: true

require "rails_helper"

RSpec.describe RuntimeRecords::Manager do
  include ChannelPluginSpecHelpers

  let(:tenant) { create(:tenant) }
  let(:operation) { create(:operation, tenant:) }
  let(:user) { create(:user, :admin, tenant:) }
  let(:headquarter_operation) { create(:operation, :headquarter, tenant:) }
  let(:context) do
    BuiltinTools::RuntimeContext::Context.new(
      agent: nil,
      chat: nil,
      mission: nil,
      ui_context: nil,
      user:,
      tenant:,
      operation:,
    )
  end
  let(:manager) { described_class.new(context) }
  let(:headquarter_manager) { described_class.new(context.with(operation: headquarter_operation)) }
  let(:definition) { RuntimeRecords::Registry.fetch("mission") }

  before do
    RuntimeRecords::Registry.definitions.clear
  end

  describe "#create" do
    it "accepts JSON object strings for attributes" do
      json_attributes = '{"name":"JSON Mission","description":"Created from JSON"}'
      result = manager.create(resource: "mission", attributes: json_attributes)

      expect(result.record).to be_persisted
      expect(result.record.name).to eq("JSON Mission")
    end

    it "creates an agent with structured attributes" do
      helper_tool = create(:tool, :mission_tool, :enabled, operation:, name: "Designer Helper")
      result = manager.create(
        resource: "agent",
        attributes: {
          name: "JSON Agent",
          description: "Created from JSON",
          model_id: "gpt-4.1",
          assigned_tool_ids: [helper_tool.id],
        },
      )

      expect(result.record).to be_persisted
      expect(result.record.name).to eq("JSON Agent")
      expect(result.record.assigned_tool_ids).to eq([helper_tool.id])
    end

    it "creates a skill catalog with structured attributes" do
      result = manager.create(
        resource: "skill_catalog",
        attributes: {
          name: "Customer Support",
          description: "Knowledge base for support workflows",
        },
      )

      expect(result.record).to be_persisted
      expect(result.record).to have_attributes(
        name: "Customer Support",
        description: "Knowledge base for support workflows",
        operation:,
      )
      expect(result.path).to eq(Rails.application.routes.url_helpers.admin_skill_catalog_path(result.record))
    end

    it "creates a tool through the custom handler" do
      connector = create(:connector, :mcp_server, tenant:)
      result = manager.create(
        resource: "tool",
        attributes: {
          tool_type: "mcp_server",
          name: "Filesystem MCP",
          toolable_attributes: { connector_id: connector.id },
        },
      )

      expect(result.record).to be_persisted
      expect(result.record.tool_type).to eq("mcp_server")
      expect(result.record.configuration["connector_id"]).to eq(connector.id)
    end

    it "creates a client channel and demotes older defaults", :aggregate_failures do
      existing_default = create(:channel, :client, tenant:, operation:, default: true, name: "Existing Default")
      assigned_agent = create(:agent, operation:, name: "Client Agent")
      create(:channel_target, channel: existing_default, target: create(:agent, operation:), default: true)

      result = manager.create(
        resource: "channel",
        attributes: {
          name: "Preview Client",
          channel_type: "client",
          default: true,
          agent_id: assigned_agent.id,
          title: "<p>Hello</p>",
        },
      )

      expect(result.record).to be_persisted
      expect(result.record).to have_attributes(tenant:, default: true, title: "<p>Hello</p>")
      expect(result.record.client_agent).to eq(assigned_agent)
      expect(Channel.where(operation:, channel_type: "client", default: true).pluck(:id)).to eq([result.record.id])
      expect(result.path).to eq(Rails.application.routes.url_helpers.admin_channel_path(result.record, view: :preview))
    end

    it "creates an API channel with a primary credential and operation mission targets" do
      mission_one = create(:mission, operation:)
      create(:mission, operation: create(:operation, tenant:))

      result = manager.create(
        resource: "channel",
        attributes: {
          name: "Public API",
          channel_type: "api",
          access_scope: "all",
        },
      )

      expect(result.record).to be_persisted
      expect(result.record.channel_credentials.count).to eq(1)
      expect(result.record.channel_targets.where(target_type: "Mission").pluck(:target_id))
        .to contain_exactly(mission_one.id)
    end

    it "surfaces the shared read-only reason for Headquarter creates" do
      expect do
        headquarter_manager.create(resource: "mission", attributes: { name: "Headquarter Draft" })
      end.to raise_error(Pundit::NotAuthorizedError, ApplicationPolicy::HEADQUARTER_READ_ONLY_MESSAGE)
    end

    it "rolls back custom create handlers that skip authorization" do
      RuntimeRecords::Registry.register(
        "unsafe_mission",
        label: "Unsafe Mission",
        model_class: Mission,
        permitted_attributes: ["name"],
        scope_resolver: ->(runtime_context) { Mission.where(operation: runtime_context.operation) },
        base_attributes: ->(runtime_context) { { operation: runtime_context.operation } },
        default_page: "designer",
        page_resolver: ->(_page, record:, **) { "/admin/missions/#{record.id}/designer" },
        create_handler: lambda do |context:, attributes:, **|
          Mission.create!(operation: context.operation, name: attributes["name"])
        end,
      )

      expect do
        headquarter_manager.create(resource: "unsafe_mission", attributes: { name: "Unauthorized Mission" })
      end.to raise_error(Pundit::NotAuthorizedError, ApplicationPolicy::HEADQUARTER_READ_ONLY_MESSAGE)
      expect(Mission.where(operation: headquarter_operation, name: "Unauthorized Mission")).to be_empty
    end

    it "post-authorizes handler-created records when the callback checked a different query" do
      RuntimeRecords::Registry.register(
        "prechecked_mission",
        label: "Prechecked Mission",
        model_class: Mission,
        permitted_attributes: ["name"],
        scope_resolver: ->(runtime_context) { Mission.where(operation: runtime_context.operation) },
        base_attributes: ->(runtime_context) { { operation: runtime_context.operation } },
        default_page: "designer",
        page_resolver: ->(_page, record:, **) { "/admin/missions/#{record.id}/designer" },
        create_handler: lambda do |context:, attributes:, authorize:, **|
          Mission.new(operation: context.operation, name: attributes["name"]).tap do |mission|
            authorize.call(mission, :show?)
            mission.save!
          end
        end,
      )

      result = manager.create(resource: "prechecked_mission", attributes: { name: "Post Authorized" })

      expect(result.record).to be_persisted
    end

    it "rejects custom create handlers that return no record" do
      RuntimeRecords::Registry.register(
        "empty_mission",
        label: "Empty Mission",
        model_class: Mission,
        permitted_attributes: ["name"],
        scope_resolver: ->(runtime_context) { Mission.where(operation: runtime_context.operation) },
        base_attributes: ->(runtime_context) { { operation: runtime_context.operation } },
        default_page: "designer",
        page_resolver: ->(_page, record:, **) { "/admin/missions/#{record.id}/designer" },
        create_handler: ->(**) {},
      )

      expect do
        manager.create(resource: "empty_mission", attributes: { name: "No Record" })
      end.to raise_error(ArgumentError, "Empty Mission create handler did not return a record.")
    end
  end

  describe "#navigation_path" do
    it "returns collection paths without a record id" do
      expect(manager.navigation_path(resource: "mission", page: "new")).to eq(
        Rails.application.routes.url_helpers.new_admin_mission_path,
      )
    end
  end

  describe "#update" do
    it "normalizes Agent Designer reasoning-off updates for DeepSeek agents" do
      create(:model, model_id: "deepseek-v4-flash", provider: "deepseek", capabilities: ["reasoning"])
      agent = create(
        :agent,
        operation:,
        model_id: "deepseek-v4-flash",
        thinking_effort: "low",
        thinking_budget: 256,
      )

      result = manager.update(
        resource: "agent",
        record_id: agent.id,
        attributes: { thinking_effort: nil, thinking_budget: nil },
      )

      expect(result.record.reload.thinking_effort).to eq("none")
      expect(result.record.thinking_budget).to be_nil
    end

    it "updates a client channel through the shared runtime handler" do
      current_default = create(:channel, :client, tenant:, operation:, default: true, name: "Current")
      create(:channel_target, channel: current_default, target: create(:agent, operation:), default: true)
      target_channel = create(:channel, :client, tenant:, operation:, default: false, name: "Target")
      create(:channel_target, channel: target_channel, target: create(:agent, operation:), default: true)

      result = manager.update(
        resource: "channel",
        record_id: target_channel.id,
        attributes: {
          default: true,
          new_chat_label: "Start now",
        },
      )

      expect(result.record.reload.default).to be(true)
      expect(result.record.new_chat_label).to eq("Start now")
      expect(current_default.reload.default).to be(false)
    end

    it "updates a skill catalog through the shared runtime path" do
      skill_catalog = create(:skill_catalog, operation:, name: "Support", description: "Old description")

      result = manager.update(
        resource: "skill_catalog",
        record_id: skill_catalog.slug,
        attributes: { description: "Updated description" },
      )

      expect(result.record.reload.description).to eq("Updated description")
    end

    it "rejects attempts to change a channel type" do
      channel = create(:channel, :client, tenant:, operation:)

      expect do
        manager.update(
          resource: "channel",
          record_id: channel.id,
          attributes: { channel_type: "api" },
        )
      end.to raise_error(ArgumentError, "Channel type cannot be changed once the channel exists.")
    end

    it "updates single-target mission channel targets by mission slug and clears them when blank" do
      with_mission_only_channel_type do
        original_mission = create(:mission, operation:, name: "Original Mission")
        replacement_mission = create(:mission, operation:, name: "Replacement Mission")
        channel = create(:channel, tenant:, operation:, channel_type: "mission_only_spec")
        create(:channel_target, :mission, channel:, target: original_mission, default: true)

        manager.update(
          resource: "channel",
          record_id: channel.id,
          attributes: { mission_id: replacement_mission.slug },
        )

        expect(channel.reload.channel_targets.first.target).to eq(replacement_mission)

        manager.update(
          resource: "channel",
          record_id: channel.id,
          attributes: { mission_id: "" },
        )

        expect(channel.reload.channel_targets).to be_empty
      end
    end

    it "keeps scoped API channel mission targets when only agent ids change" do
      first_agent = create(:agent, operation:, name: "A Agent")
      second_agent = create(:agent, operation:, name: "B Agent")
      mission = create(:mission, operation:, name: "Preserved Mission")
      channel = create(:channel, :api, tenant:, operation:, configuration: { "access_scope" => "scoped" })
      create(:channel_target, channel:, target: first_agent, default: true)
      create(:channel_target, :mission, channel:, target: mission, position: 1)

      manager.update(
        resource: "channel",
        record_id: channel.id,
        attributes: { agent_ids: [second_agent.id] },
      )

      expect(channel.reload.channel_targets.where(target_type: "Agent").pluck(:target_id)).to eq([second_agent.id])
      expect(channel.channel_targets.where(target_type: "Mission").pluck(:target_id)).to eq([mission.id])
    end

    it "updates scoped API channel mission targets when mission ids are provided" do
      first_mission = create(:mission, operation:, name: "First Mission")
      second_mission = create(:mission, operation:, name: "Second Mission")
      channel = create(:channel, :api, tenant:, operation:, configuration: { "access_scope" => "scoped" })
      create(:channel_target, :mission, channel:, target: first_mission, default: true)

      manager.update(
        resource: "channel",
        record_id: channel.id,
        attributes: { mission_ids: [second_mission.id] },
      )

      expect(channel.reload.channel_targets.where(target_type: "Mission").pluck(:target_id)).to eq([second_mission.id])
    end
  end

  describe "#destroy" do
    it "destroys a skill catalog through the shared runtime path" do
      skill_catalog = create(:skill_catalog, operation:, name: "Support")

      result = manager.destroy(resource: "skill_catalog", record_id: skill_catalog.slug)

      expect(SkillCatalog.find_by(id: skill_catalog.id)).to be_nil
      expect(result.path).to eq(Rails.application.routes.url_helpers.admin_skill_catalogs_path)
    end
  end

  describe "private helpers" do
    it "parses ActionController::Parameters and Hash values", :aggregate_failures do
      params_hash = ActionController::Parameters.new(name: "From Params")

      expect(manager.send(:parse_hash, nil)).to eq({})
      expect(manager.send(:parse_hash, params_hash)).to eq({ "name" => "From Params" })
      expect(manager.send(:parse_hash, { name: "From Hash" })).to eq({ "name" => "From Hash" })
    end

    it "returns an empty hash for blank JSON strings" do
      expect(manager.send(:parse_string_hash, "   ")).to eq({})
    end

    it "raises when JSON strings are not objects", :aggregate_failures do
      expect { manager.send(:parse_string_hash, "[]") }
        .to raise_error(ArgumentError, "Expected a JSON object.")
      expect { manager.send(:parse_hash, 1) }
        .to raise_error(ArgumentError, "Expected attributes to be a hash or JSON object string.")
    end

    it "rejects unknown attributes" do
      expect { manager.send(:sanitize_attributes, definition, { bad: true }) }
        .to raise_error(ArgumentError, "Unknown mission attributes: bad")
    end

    it "raises when record ids are blank or missing", :aggregate_failures do
      expect { manager.send(:find_record!, definition, nil) }
        .to raise_error(ArgumentError, "Provide record_id.")
      expect { manager.send(:find_record!, definition, "missing") }
        .to raise_error(ActiveRecord::RecordNotFound, "Mission 'missing' was not found.")
    end

    it "finds records by a unique exact name inside the scoped context" do
      mission = create(:mission, operation:, name: "Unique Runtime Mission")

      expect(manager.send(:find_record!, definition, mission.name)).to eq(mission)
    end

    it "raises when an exact record name is ambiguous inside the scope" do
      create(:mission, operation:, name: "Shared Runtime Mission")
      create(:mission, operation:, name: "Shared Runtime Mission")

      expect { manager.send(:find_record!, definition, "Shared Runtime Mission") }
        .to raise_error(
          ActiveRecord::RecordNotFound,
          "Multiple missions named 'Shared Runtime Mission' were found. Pass the numeric ID or slug instead.",
        )
    end

    it "returns nil for unique-name lookups on models without a name column" do
      message_definition = double(model_class: Message, label: "Message")

      expect(manager.send(:unique_name_match, Message.all, message_definition, "ignored")).to be_nil
    end

    it "raises when a policy class is missing" do
      missing_policy_record = Object.new

      expect { manager.send(:authorize!, missing_policy_record, :show?) }
        .to raise_error(ArgumentError, "Missing policy for Object.")
    end

    it "raises when a same-tenant non-admin user is not authorized" do
      regular_user = create(:user, tenant:)
      regular_context = context.with(user: regular_user)
      regular_manager = described_class.new(regular_context)
      mission = create(:mission, operation:)

      expect { regular_manager.send(:authorize!, mission, :update?) }
        .to raise_error(Pundit::NotAuthorizedError, "You do not have permission to do that.")
    end

    it "raises when no operation is available for channel operations" do
      tenantless_manager = described_class.new(context.with(operation: nil))

      expect do
        tenantless_manager.create(resource: "channel", attributes: { name: "Tenantless", channel_type: "client" })
      end.to raise_error(ArgumentError, "No active operation is available for channels.")
    end
  end
end
