# frozen_string_literal: true

# == Schema Information
#
# Table name: clients
# Database name: primary
#
#  id            :bigint           not null, primary key
#  configuration :jsonb            not null
#  default       :boolean          default(FALSE), not null
#  name          :string           not null
#  slug          :string
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  agent_id      :bigint           not null
#  tenant_id     :bigint           not null
#
# Indexes
#
#  index_clients_on_agent_id            (agent_id)
#  index_clients_on_default             (default)
#  index_clients_on_slug                (slug) UNIQUE
#  index_clients_on_tenant_id           (tenant_id)
#  index_clients_on_tenant_id_and_name  (tenant_id,name) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (agent_id => agents.id)
#  fk_rails_...  (tenant_id => tenants.id)
#
require "rails_helper"

RSpec.describe Client do
  describe "associations" do
    it { is_expected.to belong_to(:agent) }
  end

  describe "validations" do
    subject(:client) { build(:client) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_uniqueness_of(:name).scoped_to(:tenant_id).case_insensitive }
    it { is_expected.to validate_length_of(:name).is_at_most(100) }
    it { is_expected.to validate_length_of(:title).is_at_most(5000) }
    it { is_expected.to validate_length_of(:welcome_message).is_at_most(10_000) }
    it { is_expected.to validate_length_of(:footer).is_at_most(5000) }

    it "requires the agent to be enabled" do
      client = build(:client, agent: create(:agent, :disabled))
      expect(client).not_to be_valid
      expect(client.errors[:agent]).to include("must be enabled")
    end

    it "requires the agent to be selectable" do
      client = build(:client, agent: create(:agent, selectable: false))

      expect(client).not_to be_valid
      expect(client.errors[:agent]).to include("must be selectable")
    end

    it "requires the agent to belong to the same tenant" do
      tenant = create(:tenant)
      other_tenant = create(:tenant)
      other_operation = create(:operation, tenant: other_tenant)
      other_connector = create(:connector, :llm_provider, :enabled, tenant: other_tenant)
      client = build(
        :client,
        tenant:,
        agent: create(:agent, operation: other_operation, llm_connector: other_connector),
      )

      expect(client).not_to be_valid
      expect(client.errors[:agent]).to include("must belong to the same tenant")
    end
  end

  describe "sanitization" do
    it "strips disallowed HTML tags on save" do
      client = create(:client, title: '<p>Hello</p><script>alert("x")</script>')
      expect(client.reload.title).not_to include("<script>")
    end

    it "preserves allowed formatting tags" do
      html = "<p><strong>Bold</strong> and <em>italic</em></p>"
      client = create(:client, title: html)
      expect(client.reload.title).to eq(html)
    end

    it "strips table tags" do
      client = create(:client, welcome_message: "<table><tr><td>Cell</td></tr></table>")
      expect(client.reload.welcome_message).to eq("Cell")
    end

    it "preserves link tags with href" do
      html = '<p><a href="https://example.com">Link</a></p>'
      client = create(:client, footer: html)
      expect(client.reload.footer).to eq(html)
    end

    it "skips blank fields without error" do
      client = create(:client, title: nil, welcome_message: "", footer: "<p>Present</p>")
      expect(client.reload.footer).to eq("<p>Present</p>")
      expect(client.title).to be_nil
      expect(client.welcome_message).to eq("")
    end

    it "stores rich content in configuration" do
      client = create(:client, title: "<p>Brand</p>", welcome_message: "<p>Welcome</p>", footer: "<p>Footer</p>")

      expect(client.reload.configuration).to include(
        "content" => include(
          "title" => "<p>Brand</p>",
          "welcome_message" => "<p>Welcome</p>",
          "footer" => "<p>Footer</p>",
        ),
      )
    end
  end

  describe "configuration-backed labels" do
    it "persists custom labels in configuration" do
      client = create(:client, new_chat_label: "Start here", delete_chat_confirm_message: "Really remove it?")

      expect(client.reload.new_chat_label).to eq("Start here")
      expect(client.configuration).to include(
        "labels" => include(
          "new_chat_label" => "Start here",
          "delete_chat_confirm_message" => "Really remove it?",
        ),
      )
    end

    it "falls back to defaults for blank labels" do
      client = create(:client, name: "Acme", new_chat_label: "")

      expect(client.reload.new_chat_label).to eq("New chat")
      expect(client.welcome_heading).to eq("Welcome to Acme")
    end

    it "ignores blank stored label overrides" do
      client = build(:client, name: "Acme")
      client.configuration = { "labels" => { "new_chat_label" => "" } }

      expect(client.new_chat_label).to eq("New chat")
    end

    it "resets invalid configuration payloads before validation" do
      client = build(:client)
      client.configuration = "invalid"

      expect(client.title).to be_nil

      client.valid?

      expect(client.configuration).to eq({})
    end

    it "validates label length limits" do
      client = build(:client, new_chat_label: "a" * 2001)

      expect(client).not_to be_valid
      expect(client.errors[:new_chat_label]).to include("is too long (maximum is 2000 characters)")
    end
  end

  describe "message action configuration" do
    it "persists message action settings in configuration" do
      client = build(:client, name: "Acme")
      client.message_actions_visibility = "always"
      client.copy_user_message_enabled = false

      expect(client.message_actions_visibility).to eq("always")
      expect(client.copy_user_message_enabled).to be(false)
      expect(client.configuration).to include(
        "message_actions" => include(
          "message_actions_visibility" => "always",
          "copy_user_message_enabled" => false,
        ),
      )
    end

    it "keeps stored message action overrides and ignores unknown keys" do
      client = build(:client, name: "Acme")
      client.configuration = {
        "message_actions" => {
          "message_actions_visibility" => "",
          "copy_user_message_enabled" => false,
          "unknown" => true,
        },
      }

      expect(client.message_actions_visibility).to eq("")
      expect(client.copy_user_message_enabled).to be(false)
      expect(client.send(:effective_message_action_settings)).not_to have_key("unknown")
    end

    it "validates message action visibility values" do
      client = build(:client, message_actions_visibility: "sometimes")

      expect(client).not_to be_valid
      expect(client.errors[:message_actions_visibility]).to include("must be one of: always, hover")
    end

    it "accepts non-blank primitive overrides and rejects nil overrides" do
      client = build(:client)
      custom_value = Object.new
      def custom_value.respond_to?(*)
        false
      end

      expect(client.send(:persist_message_action_override?, "copy_user_message_enabled", custom_value)).to be(true)
      expect(client.send(:persist_message_action_override?, "copy_user_message_enabled", nil)).to be(false)
    end
  end

  describe ".default_labels" do
    it "exposes the configuration-backed attribute names" do
      expect(described_class.configuration_attribute_names).to include(:title, :welcome_message, :new_chat_label)
    end

    it "falls back to the app name when no client name is provided" do
      expect(described_class.default_labels(client_name: nil)["welcome_heading"]).to eq("Welcome to Undercover Agents")
    end
  end

  describe "default flag" do
    it "cannot remove default if no other default exists" do
      client = create(:client, default: true)
      client.default = false
      expect(client).not_to be_valid
      expect(client.errors[:default]).to be_present
    end

    it "allows removing default if another default exists" do
      create(:client, default: true)
      client2 = create(:client, default: true, name: "Second")
      client2.default = false
      expect(client2).to be_valid
    end
  end

  describe ".current_settings" do
    it "returns a hash with the default client settings" do
      agent = create(:agent)
      create(:client, default: true, agent:, name: "Test Client", title: "<p>Title</p>")

      settings = described_class.current_settings
      expect(settings[:name]).to eq("Test Client")
      expect(settings[:title]).to eq("<p>Title</p>")
      expect(settings[:agent_id]).to eq(agent.id)
      expect(settings[:agent_name]).to eq(agent.name)
      expect(settings[:labels]).to include(
        "new_chat_label" => "New chat",
        "welcome_heading" => "Welcome to Test Client",
      )
    end

    it "returns nil when no default client exists" do
      expect(described_class.current_settings).to be_nil
    end

    it "returns nil when no tenant is available" do
      expect(described_class.current_settings(tenant: nil)).to be_nil
    end

    it "includes logo_url when logo is attached" do
      create(:client, :with_logo, default: true)
      settings = described_class.current_settings
      expect(settings[:logo_url]).to be_present
    end

    it "caches the result" do
      create(:client, default: true)
      described_class.current_settings # warm cache
      allow(Rails.cache).to receive(:fetch).and_call_original
      described_class.current_settings
      expect(Rails.cache).to have_received(:fetch)
    end

    it "returns nil for agent_name when agent association is not loaded" do
      agent = create(:agent)
      create(:client, default: true, agent:)
      allow_any_instance_of(described_class).to receive(:agent).and_return(nil) # rubocop:disable RSpec/AnyInstance

      settings = described_class.current_settings
      expect(settings[:agent_name]).to be_nil
    end
  end

  describe "cache invalidation" do
    it "invalidates cache after save" do
      client = create(:client, default: true)
      described_class.current_settings # warm cache
      client.update!(name: "Updated Name")

      settings = described_class.current_settings
      expect(settings[:name]).to eq("Updated Name")
    end

    it "invalidates cache after destroy" do
      client = create(:client, default: true)
      _other = create(:client, default: true, name: "Other")
      described_class.current_settings # warm cache
      client.destroy!

      settings = described_class.current_settings
      expect(settings[:name]).to eq("Other")
    end

    it "invalidates all tenant caches when no tenant is provided" do
      allow(Rails.cache).to receive(:delete_matched)

      described_class.invalidate_settings_cache!

      expect(Rails.cache).to have_received(:delete_matched).with("client/*/default_settings")
    end
  end

  describe "scopes" do
    describe ".ordered" do
      it "returns clients ordered by name" do
        create(:client, name: "Zeta")
        create(:client, name: "Alpha", default: false)
        expect(described_class.ordered.pluck(:name)).to eq(["Alpha", "Zeta"])
      end
    end
  end
end
