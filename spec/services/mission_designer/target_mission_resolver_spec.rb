# frozen_string_literal: true

require "rails_helper"

RSpec.describe MissionDesigner::TargetMissionResolver do
  let(:tenant) { create(:tenant) }
  let(:operation) { create(:operation, tenant:) }
  let(:mission) { create(:mission, operation:) }
  let(:runtime_context) do
    BuiltinTools::RuntimeContext::Context.new(
      agent: nil,
      chat: nil,
      mission: nil,
      ui_context: nil,
      user: nil,
      tenant:,
      operation:,
    )
  end

  around do |example|
    Current.reset
    example.run
  ensure
    Current.reset
  end

  describe "#resolve" do
    it "returns the fallback mission when no mission_id is provided" do
      resolver = described_class.new(fallback_mission: mission, runtime_context:)

      expect(resolver.resolve).to eq(mission)
    end

    it "raises a clear error when no mission is available" do
      resolver = described_class.new(fallback_mission: nil, runtime_context:)

      expect { resolver.resolve }
        .to raise_error(ArgumentError, "No mission is available. Provide mission_id or open a mission page first.")
    end

    it "resolves a mission by id inside the current operation" do
      resolver = described_class.new(fallback_mission: nil, runtime_context:)

      expect(resolver.resolve(mission.id)).to eq(mission)
    end

    it "resolves a mission by slug inside the current operation" do
      resolver = described_class.new(fallback_mission: nil, runtime_context:)

      expect(resolver.resolve(mission.slug)).to eq(mission)
    end

    it "resolves a mission by unique name inside the current operation" do
      resolver = described_class.new(fallback_mission: nil, runtime_context:)

      expect(resolver.resolve(mission.name)).to eq(mission)
    end

    it "falls back to the current mission when given one token from its name" do
      mission.update!(name: "AAB mission08 tdaqkw Mission")
      resolver = described_class.new(fallback_mission: mission, runtime_context:)

      expect(resolver.resolve("tdaqkw")).to eq(mission)
    end

    it "matches the fallback mission by exact id, slug, and name", :aggregate_failures do
      resolver = described_class.new(fallback_mission: mission, runtime_context:)

      expect(resolver.resolve(mission.id)).to eq(mission)
      expect(resolver.resolve(mission.slug)).to eq(mission)
      expect(resolver.resolve(mission.name)).to eq(mission)
    end

    it "does not resolve missions from another operation" do
      foreign_mission = create(:mission, operation: create(:operation, tenant:))
      resolver = described_class.new(fallback_mission: nil, runtime_context:)

      expect { resolver.resolve(foreign_mission.id) }
        .to raise_error(ActiveRecord::RecordNotFound, "Mission '#{foreign_mission.id}' was not found.")
    end

    it "falls back to tenant-only scoping when no operation is available" do
      same_tenant_mission = create(:mission, operation: create(:operation, tenant:))
      resolver = described_class.new(fallback_mission: nil, runtime_context: runtime_context.with(operation: nil))

      expect(resolver.resolve(same_tenant_mission.id)).to eq(same_tenant_mission)
    end

    it "asks for an id or slug when a tenant-scoped mission name is ambiguous" do
      create(:mission, operation: create(:operation, tenant:), name: "Shared Mission")
      create(:mission, operation: create(:operation, tenant:), name: "Shared Mission")
      resolver = described_class.new(fallback_mission: nil, runtime_context: runtime_context.with(operation: nil))

      expect { resolver.resolve("Shared Mission") }
        .to raise_error(
          ActiveRecord::RecordNotFound,
          "Multiple missions named 'Shared Mission' were found. Pass the numeric ID or slug instead.",
        )
    end

    it "uses Current tenant and Current operation when runtime context is absent" do
      Current.tenant = tenant
      Current.operation = operation
      resolver = described_class.new(fallback_mission: nil, runtime_context: nil)

      expect(resolver.resolve(mission.id)).to eq(mission)
    end

    it "can resolve without tenant or operation scoping when no context exists" do
      resolver = described_class.new(fallback_mission: nil, runtime_context: nil)

      expect(resolver.resolve(mission.id)).to eq(mission)
    end
  end

  describe "private fallbacks" do
    it "falls back to the fallback mission tenant" do
      resolver = described_class.new(fallback_mission: mission, runtime_context: nil)

      expect(resolver.send(:tenant)).to eq(tenant)
    end

    it "falls back to the fallback mission operation" do
      resolver = described_class.new(fallback_mission: mission, runtime_context: nil)

      expect(resolver.send(:operation)).to eq(operation)
    end

    it "falls back to Current tenant and Current operation" do
      Current.tenant = tenant
      Current.operation = operation
      resolver = described_class.new(fallback_mission: nil, runtime_context: nil)

      expect(resolver.send(:tenant)).to eq(tenant)
      expect(resolver.send(:operation)).to eq(operation)
    end

    it "returns nil for non-matching fallback identifiers" do
      resolver = described_class.new(fallback_mission: mission, runtime_context:)

      expect(resolver.send(:fallback_mission_match, "missing-mission")).to be_nil
    end
  end
end
