# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChatReferences::SelectionResolver do
  let(:tenant) { create(:tenant).tap(&:ensure_core_resources!) }
  let(:operation) { tenant.default_operation }

  around do |example|
    original_definitions = ChatReferences::Registry.definitions.dup
    example.run
  ensure
    ChatReferences::Registry.instance_variable_set(:@definitions, original_definitions)
  end

  it "deduplicates selected operation references" do
    mission = create(:mission, operation:, name: "Launch Plan")
    payload = [reference_payload(mission, kind: "missions"), reference_payload(mission, kind: "missions")].to_json

    references = resolver(kinds: ["missions"]).resolve(payload)

    expect(references).to contain_exactly(
      {
        "kind" => "missions",
        "type" => "Mission",
        "id" => mission.id,
        "label" => mission.name,
        "slug" => mission.slug,
        "mention" => "#mission",
      },
    )
  end

  it "resolves skills through their operation-owned catalogs" do
    catalog = create(:skill_catalog, operation:)
    skill = create(:skill, skill_catalog: catalog, name: "Brief Writer")

    references = resolver(kinds: ["skills"]).resolve([reference_payload(skill, kind: "skills")])

    expect(references).to contain_exactly(hash_including("id" => skill.id, "type" => "Skill"))
  end

  it "supports registered tenant-scoped definitions" do
    register_definition(kind: "api_clients", model_name: "ApiClient", scope: "tenant")
    api_client = create(:api_client, tenant:, name: "Public API")

    references = resolver(kinds: ["api_clients"]).resolve([reference_payload(api_client, kind: "api_clients")])

    expect(references).to contain_exactly(hash_including("id" => api_client.id, "label" => api_client.name))
  end

  it "resolves built-in client references through the current tenant" do
    client = create(
      :client,
      name: "Billing Portal",
      agent: create(:agent, operation:, name: "Client Agent"),
    )
    other_tenant = create(:tenant).tap(&:ensure_core_resources!)
    hidden_client = create(
      :client,
      name: "Hidden Client",
      agent: create(:agent, operation: other_tenant.default_operation, name: "Other Tenant Agent"),
    )

    references = resolver(kinds: ["clients"]).resolve(
      [
        reference_payload(client, kind: "clients"),
        reference_payload(hidden_client, kind: "clients"),
      ],
    )

    expect(references).to contain_exactly(hash_including("id" => client.id, "label" => client.name, "type" => "Client"))
  end

  it "resolves built-in connector references through the current tenant" do
    connector = create(:connector, :llm_provider, :enabled, tenant:, name: "Prod LLM")
    hidden_connector = create(:connector, :llm_provider, :enabled, tenant: create(:tenant), name: "Hidden LLM")

    references = resolver(kinds: ["connectors"]).resolve(
      [
        reference_payload(connector, kind: "connectors"),
        reference_payload(hidden_connector, kind: "connectors"),
      ],
    )

    expect(references).to contain_exactly(
      hash_including("id" => connector.id, "label" => connector.name, "type" => "Connector"),
    )
  end

  it "resolves built-in test suite references through the current tenant" do
    visible_suite = create(:test_suite, agent: create(:agent, operation:, name: "Suite Agent"), name: "Smoke Suite")
    other_tenant = create(:tenant).tap(&:ensure_core_resources!)
    hidden_suite = create(
      :test_suite,
      agent: create(:agent, operation: other_tenant.default_operation, name: "Hidden Agent"),
      name: "Hidden Suite",
    )

    references = resolver(kinds: ["test_suites"]).resolve(
      [
        reference_payload(visible_suite, kind: "test_suites"),
        reference_payload(hidden_suite, kind: "test_suites"),
      ],
    )

    expect(references).to contain_exactly(
      hash_including("id" => visible_suite.id, "label" => visible_suite.name, "type" => "Test Suite"),
    )
  end

  it "prefers signed global ids over raw ids while still applying scope" do
    mission = create(:mission, operation:, name: "Signed Mission")
    other_mission = create(:mission, operation:, name: "Other Mission")
    payload = reference_payload(other_mission, kind: "missions").merge(
      id: other_mission.id,
      sgid: mission.to_sgid(for: ChatReferences::SIGNED_ID_PURPOSE).to_s,
    )

    references = resolver(kinds: ["missions"]).resolve([payload])

    expect(references).to contain_exactly(hash_including("id" => mission.id, "label" => mission.name))
  end

  it "ignores signed global ids that resolve outside the configured scope" do
    hidden_operation = create(:operation, tenant:)
    hidden_mission = create(:mission, operation: hidden_operation, name: "Hidden Mission")
    payload = reference_payload(hidden_mission, kind: "missions").merge(
      sgid: hidden_mission.to_sgid(for: ChatReferences::SIGNED_ID_PURPOSE).to_s,
    )

    expect(resolver(kinds: ["missions"]).resolve([payload])).to eq([])
  end

  it "ignores invalid or wrong-class signed global ids without falling back to raw ids" do
    mission = create(:mission, operation:, name: "Visible Mission")
    api_client = create(:api_client, tenant:)
    wrong_class_payload = reference_payload(mission, kind: "missions").merge(
      sgid: api_client.to_sgid(for: ChatReferences::SIGNED_ID_PURPOSE).to_s,
    )
    invalid_payload = reference_payload(mission, kind: "missions").merge(
      sgid: "#{mission.to_sgid(for: ChatReferences::SIGNED_ID_PURPOSE)}tampered",
    )

    references = resolver(kinds: ["missions"]).resolve([wrong_class_payload, invalid_payload])

    expect(references).to eq([])
  end

  it "ignores signed global ids that fail verifier checks" do
    mission = create(:mission, operation:, name: "Visible Mission")
    allow(GlobalID::Locator).to receive(:locate_signed).and_call_original
    allow(GlobalID::Locator).to receive(:locate_signed)
      .with("invalid-sgid", for: ChatReferences::SIGNED_ID_PURPOSE)
      .and_raise(ActiveSupport::MessageVerifier::InvalidSignature)

    payload = reference_payload(mission, kind: "missions").merge(sgid: "invalid-sgid")

    expect(resolver(kinds: ["missions"]).resolve([payload])).to eq([])
  end

  it "returns no tenant-via-test-target scope when the tenant is missing" do
    selection_resolver = described_class.new(tenant: nil, operation:, kinds: ["test_suites"])

    expect(selection_resolver.send(:scope_for_test_target_tenant, TestSuite.all)).to be_empty
  end

  it "ignores unsupported scopes and invalid JSON payloads" do
    register_definition(kind: "models", model_name: "Model", scope: "global")
    create(:model, name: "Unused Model")

    references = resolver(kinds: ["models"]).resolve([{ kind: "models", id: Model.last.id }])

    expect(references).to eq([])
    expect(resolver(kinds: ["models"]).resolve("not json")).to eq([])
  end

  it "ignores references without an allowed definition or scoped record" do
    mission = create(:mission, operation:)
    catalog = create(:skill_catalog, operation:)
    skill = create(:skill, skill_catalog: catalog)
    register_definition(kind: "api_clients", model_name: "ApiClient", scope: "tenant")
    api_client = create(:api_client, tenant:)

    expect(resolver(kinds: ["missions"]).resolve([{ kind: "unknown", id: mission.id }])).to eq([])
    expect(described_class.new(tenant:, operation: nil, kinds: ["missions"]).resolve(
             [reference_payload(mission, kind: "missions")],
           )).to eq([])
    expect(described_class.new(tenant:, operation: nil, kinds: ["skills"]).resolve(
             [reference_payload(skill, kind: "skills")],
           )).to eq([])
    expect(described_class.new(tenant: nil, operation:, kinds: ["api_clients"]).resolve(
             [reference_payload(api_client, kind: "api_clients")],
           )).to eq([])
    expect(described_class.new(tenant: nil, operation:, kinds: ["connectors"]).resolve(
             [reference_payload(create(:connector, :llm_provider, :enabled, tenant:), kind: "connectors")],
           )).to eq([])
  end

  it "falls back to context references for invalid mentions and sources" do
    invalid_mention_mission = create(:mission, operation:, name: "Invalid Mention")
    blank_mention_mission = create(:mission, operation:, name: "Blank Mention")
    payload = [
      reference_payload(invalid_mention_mission, kind: "missions").merge(mention: "mission", source: "custom"),
      reference_payload(blank_mention_mission, kind: "missions").merge(mention: ""),
    ]

    references = resolver(kinds: ["missions"]).resolve(payload)

    expect(references).to include(
      hash_including("id" => invalid_mention_mission.id, "label" => invalid_mention_mission.name),
    )
    expect(references.find { |reference| reference["id"] == invalid_mention_mission.id }).not_to have_key("mention")
    expect(references.find { |reference| reference["id"] == invalid_mention_mission.id }).not_to have_key("source")
    expect(references.find { |reference| reference["id"] == blank_mention_mission.id }).not_to have_key("mention")
  end

  def resolver(kinds:)
    described_class.new(tenant:, operation:, kinds:)
  end

  def reference_payload(record, kind:)
    {
      kind:,
      id: record.id,
      label: record.name,
      mention: "##{kind.singularize}",
      source: "inline",
    }
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
end
