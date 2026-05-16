# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChatReferences::Search do
  def expect_reference_group(groups, kind:, item:)
    expect(groups).to contain_exactly(
      hash_including(
        kind:,
        items: [hash_including(item)],
      ),
    )
  end

  let(:tenant) { create(:tenant).tap(&:ensure_core_resources!) }
  let(:operation) { tenant.default_operation }

  around do |example|
    original_definitions = ChatReferences::Registry.definitions.dup
    example.run
  ensure
    ChatReferences::Registry.instance_variable_set(:@definitions, original_definitions)
  end

  it "supports registered tenant-scoped reference definitions" do
    register_definition(kind: "api_clients", model_name: "ApiClient", scope: "tenant")
    api_client = create(:api_client, tenant:, name: "Public API")

    groups = described_class.new(tenant:, operation:, kinds: ["api_clients"]).call(query: "public")

    expect(groups).to contain_exactly(
      hash_including(
        kind: "api_clients",
        items: [
          hash_including(
            id: api_client.id,
            sgid: be_present,
            label: api_client.name,
            mention: "#public-api",
            display_mention: "#public-api",
            display_tag: "#api_client_id:#{api_client.id}",
          ),
        ],
      ),
    )
    sgid = groups.first.fetch(:items).first.fetch(:sgid)
    expect(GlobalID::Locator.locate_signed(sgid, for: ChatReferences::SIGNED_ID_PURPOSE)).to eq(api_client)
  end

  it "includes built-in client references for the current tenant" do
    kinds = ["clients"]
    client = create_client_reference(name: "Billing Portal", operation:)
    other_tenant = create(:tenant).tap(&:ensure_core_resources!)
    create_client_reference(name: "Hidden Client", operation: other_tenant.default_operation)

    groups = described_class.new(tenant:, operation:, kinds:).call(query: "billing")

    expect(groups).to contain_exactly(
      hash_including(
        kind: "clients",
        items: [
          hash_including(
            id: client.id,
            sgid: be_present,
            label: client.name,
            mention: "#billing-portal",
            display_mention: "#billing-portal",
            display_tag: "#client_id:#{client.id}",
          ),
        ],
      ),
    )
  end

  it "includes built-in connector references for the current tenant" do
    connector = create(:connector, :llm_provider, :enabled, tenant:, name: "Prod LLM")
    create(:connector, :llm_provider, :enabled, tenant: create(:tenant), name: "Hidden LLM")

    groups = described_class.new(tenant:, operation:, kinds: ["connectors"]).call(query: "prod")

    expect_reference_group(
      groups,
      kind: "connectors",
      item: {
        id: connector.id,
        sgid: be_present,
        label: connector.name,
        mention: "#prod-llm",
        display_tag: "#connector_id:#{connector.id}",
      },
    )
  end

  it "includes built-in test suite references for the current tenant" do
    visible_suite = create(:test_suite, agent: create(:agent, operation:, name: "Suite Agent"), name: "Smoke Suite")
    other_tenant = create(:tenant).tap(&:ensure_core_resources!)
    create(
      :test_suite,
      agent: create(:agent, operation: other_tenant.default_operation, name: "Hidden Agent"),
      name: "Hidden Suite",
    )

    groups = described_class.new(tenant:, operation:, kinds: ["test_suites"]).call(query: "smoke")

    expect_reference_group(
      groups,
      kind: "test_suites",
      item: {
        id: visible_suite.id,
        sgid: be_present,
        label: visible_suite.name,
        mention: "#smoke-suite",
        display_tag: "#test_suite_id:#{visible_suite.id}",
        subtitle: "Suite Agent",
      },
    )
  end

  it "falls back to type and id when a record name cannot become a mention" do
    mission = create(:mission, operation:, name: "!!!")

    groups = described_class.new(tenant:, operation:, kinds: ["missions"]).call(query: "")

    expect(groups.dig(0, :items)).to include(
      hash_including(id: mission.id, mention: "#mission-#{mission.id}", display_mention: "#mission-#{mission.id}"),
    )
  end

  it "returns no groups for unsupported scopes" do
    register_definition(kind: "models", model_name: "Model", scope: "global")

    groups = described_class.new(tenant:, operation:, kinds: ["models"]).call(query: "")

    expect(groups).to eq([])
  end

  it "returns no groups when the required tenant or operation scope is missing" do
    register_definition(kind: "api_clients", model_name: "ApiClient", scope: "tenant")

    expect(described_class.new(tenant:, operation: nil, kinds: ["missions"]).call(query: "")).to eq([])
    expect(described_class.new(tenant:, operation: nil, kinds: ["skills"]).call(query: "")).to eq([])
    expect(described_class.new(tenant: nil, operation:, kinds: ["api_clients"]).call(query: "")).to eq([])
    expect(described_class.new(tenant: nil, operation:, kinds: ["connectors"]).call(query: "")).to eq([])
    expect(described_class.new(tenant: nil, operation:, kinds: ["test_suites"]).call(query: "")).to eq([])
  end

  def register_definition(kind:, model_name:, scope:)
    ChatReferences::Registry.register(
      ChatReferences::Definition.new(
        kind:,
        label: kind.titleize,
        model_name:,
        scope:,
        icon: "fa-solid fa-hashtag",
        search_columns: ["name"],
      ),
    )
  end

  def create_client_reference(name:, operation:)
    create(:client, name:, agent: create(:agent, operation:, name: "#{name} Agent"))
  end

  it "falls back from agent name to mission name to suite type for test suite subtitles", :aggregate_failures do
    search = described_class.new(tenant:, operation:, kinds: ["test_suites"])
    mission_suite = build_stubbed(:test_suite, agent: nil, mission: build_stubbed(:mission, name: "Launch Flow"))
    untargeted_suite = build_stubbed(:test_suite, agent: nil, mission: nil)

    expect(search.send(:record_subtitle, mission_suite)).to eq("Launch Flow")
    expect(search.send(:record_subtitle, untargeted_suite)).to eq(untargeted_suite.suite_type.to_s.titleize)
  end
end
