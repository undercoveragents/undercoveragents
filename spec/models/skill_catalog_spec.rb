# frozen_string_literal: true

# == Schema Information
#
# Table name: skill_catalogs
# Database name: primary
#
#  id              :bigint           not null, primary key
#  description     :text
#  name            :string           not null
#  slug            :string           not null
#  source_metadata :jsonb            not null
#  source_type     :string           default("manual"), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  operation_id    :bigint           not null
#
# Indexes
#
#  index_skill_catalogs_on_operation_id           (operation_id)
#  index_skill_catalogs_on_operation_id_and_name  (operation_id,name) UNIQUE
#  index_skill_catalogs_on_slug                   (slug) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (operation_id => operations.id)
#
require "rails_helper"

RSpec.describe SkillCatalog do
  describe "associations" do
    it { is_expected.to belong_to(:operation) }
    it { is_expected.to have_many(:skills).dependent(:destroy) }
  end

  describe "validations" do
    subject(:skill_catalog) { build(:skill_catalog) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_uniqueness_of(:name).scoped_to(:operation_id) }
    it { is_expected.to validate_length_of(:name).is_at_most(120) }
  end

  describe "agent integration" do
    it "returns agents assigned through configuration" do
      skill_catalog = create(:skill_catalog)
      assigned_agent = create(:agent, operation: skill_catalog.operation)
      unassigned_agent = create(:agent, operation: skill_catalog.operation)
      assigned_agent.update!(skill_catalog_ids: [skill_catalog.id])

      expect(skill_catalog.assigned_agents).to include(assigned_agent)
      expect(skill_catalog.assigned_agents).not_to include(unassigned_agent)
    end

    it "removes itself from agent configuration when destroyed" do
      skill_catalog = create(:skill_catalog)
      agent = create(:agent, operation: skill_catalog.operation)
      agent.update!(skill_catalog_ids: [skill_catalog.id])

      skill_catalog.destroy!

      expect(agent.reload.skill_catalog_ids).to eq([])
    end

    it "counts imported skills and bundled resources" do
      skill_catalog = create(:skill_catalog)
      imported_skill = create(:skill, :imported, skill_catalog:)
      create(:skill, skill_catalog:)
      create(:skill_resource, skill: imported_skill)

      expect(skill_catalog.imported_skills_count).to eq(1)
      expect(skill_catalog.total_resource_count).to eq(1)
    end

    it "counts builtin skills separately from imported skills" do
      skill_catalog = create(:skill_catalog)
      create(:skill, :builtin, skill_catalog:)

      expect(skill_catalog.builtin_skills_count).to eq(1)
      expect(skill_catalog.imported_skills_count).to eq(0)
    end

    it "skips agents that no longer include the catalog id during detach" do
      skill_catalog = create(:skill_catalog)
      stale_agent = instance_double(Agent, skill_catalog_ids: [], save!: true)
      relation = instance_double(ActiveRecord::Relation)

      allow(Agent).to receive(:where).and_return(relation)
      allow(relation).to receive(:find_each).and_yield(stale_agent)

      skill_catalog.send(:detach_from_agents)

      expect(stale_agent).not_to have_received(:save!)
    end
  end

  describe ".preload_index_metrics" do
    let(:primary_catalog) { create(:skill_catalog) }
    let(:secondary_catalog) { create(:skill_catalog) }

    before do
      excluded_catalog = create(:skill_catalog, operation: primary_catalog.operation)
      imported_skill = create(:skill, :imported, skill_catalog: primary_catalog)
      create(:skill, :builtin, skill_catalog: primary_catalog)
      create(:skill, skill_catalog: primary_catalog)
      create(:skill, skill_catalog: secondary_catalog)
      create(:skill_resource, skill: imported_skill)

      create(:agent, operation: primary_catalog.operation).update!(skill_catalog_ids: [primary_catalog.id])
      create(:agent, operation: secondary_catalog.operation).update!(skill_catalog_ids: [secondary_catalog.id])
      create(:agent, operation: primary_catalog.operation).update!(skill_catalog_ids: [excluded_catalog.id])

      described_class.preload_index_metrics([primary_catalog, secondary_catalog])
    end

    it "assigns grouped counts to each catalog" do
      aggregate_failures do
        expect(primary_catalog.skill_count).to eq(3)
        expect(primary_catalog.imported_skills_count).to eq(1)
        expect(primary_catalog.builtin_skills_count).to eq(1)
        expect(primary_catalog.total_resource_count).to eq(1)
        expect(primary_catalog.assigned_agents_count).to eq(1)
        expect(secondary_catalog.skill_count).to eq(1)
        expect(secondary_catalog.imported_skills_count).to eq(0)
        expect(secondary_catalog.builtin_skills_count).to eq(0)
        expect(secondary_catalog.total_resource_count).to eq(0)
        expect(secondary_catalog.assigned_agents_count).to eq(1)
      end
    end

    it "returns when no catalogs are provided" do
      expect { described_class.preload_index_metrics([]) }.not_to raise_error
    end
  end

  describe "count helpers" do
    it "falls back to counting skills through the association" do
      skill_catalog = create(:skill_catalog)
      create_list(:skill, 2, skill_catalog:)

      expect(skill_catalog.skill_count).to eq(2)
    end

    it "falls back to counting assigned agents through configuration" do
      skill_catalog = create(:skill_catalog)
      assigned_agent = create(:agent, operation: skill_catalog.operation)
      assigned_agent.update!(skill_catalog_ids: [skill_catalog.id])

      expect(skill_catalog.assigned_agents_count).to eq(1)
    end
  end

  describe "source helpers" do
    it "reports whether a catalog is manual or builtin" do
      expect(build(:skill_catalog)).to be_manual
      expect(build(:skill_catalog, :builtin)).to be_builtin
    end

    it "normalizes non-hash source metadata to an empty hash" do
      skill_catalog = build(:skill_catalog, source_metadata: "invalid")

      skill_catalog.send(:normalize_source_metadata)

      expect(skill_catalog.source_metadata).to eq({})
    end

    it "adds a validation error when source metadata is not a hash" do
      skill_catalog = build(:skill_catalog, source_metadata: "invalid")

      skill_catalog.send(:source_metadata_must_be_hash)

      expect(skill_catalog.errors[:source_metadata]).to include("must be a JSON object")
    end
  end
end
