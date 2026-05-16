# frozen_string_literal: true

require "rails_helper"

RSpec.describe ArchivalMemory do
  subject(:archival_memory) { build(:archival_memory) }

  describe "associations" do
    it { is_expected.to belong_to(:agent) }
    it { is_expected.to belong_to(:user) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:content) }

    it "requires the user to belong to the same tenant as the agent" do
      tenant = create(:tenant)
      foreign_tenant = create(:tenant)
      agent = create(:agent, operation: create(:operation, tenant:))
      user = create(:user, tenant: foreign_tenant)

      archival_memory = build(:archival_memory, agent:, user:)

      expect(archival_memory).not_to be_valid
      expect(archival_memory.errors[:user]).to include("must belong to the same tenant as the agent")
    end
  end

  describe "scopes" do
    let(:agent) { create(:agent) }
    let(:user)  { create(:user) }

    describe ".for_agent" do
      it "returns memories belonging to the given agent" do
        ours        = create(:archival_memory, agent:, user:)
        other_agent = create(:agent)
        _theirs     = create(:archival_memory, agent: other_agent, user:)

        expect(described_class.for_agent(agent.id)).to eq([ours])
      end
    end

    describe ".for_user" do
      it "returns memories belonging to the given user" do
        ours       = create(:archival_memory, agent:, user:)
        other_user = create(:user)
        _theirs    = create(:archival_memory, agent:, user: other_user)

        expect(described_class.for_user(user.id)).to eq([ours])
      end
    end

    describe ".with_tags" do
      it "returns memories matching any of the given tags" do
        tagged    = create(:archival_memory, agent:, user:, tags: ["important"])
        _untagged = create(:archival_memory, agent:, user:, tags: [])

        expect(described_class.with_tags(["important"])).to eq([tagged])
      end
    end

    describe ".recent" do
      it "returns memories ordered by newest first" do
        old    = create(:archival_memory, agent:, user:, created_at: 2.days.ago)
        recent = create(:archival_memory, agent:, user:, created_at: 1.hour.ago)

        expect(described_class.recent).to eq([recent, old])
      end
    end
  end

  describe ".semantic_search" do
    let(:agent) { create(:agent) }
    let(:user)  { create(:user) }

    it "returns memories ordered by cosine similarity" do
      target_embedding = Array.new(1536) { 0.5 }
      similar     = create(:archival_memory, agent:, user:, embedding: target_embedding)
      _dissimilar = create(:archival_memory, agent:, user:, embedding: Array.new(1536) { -0.5 })

      results = described_class.semantic_search(
        agent_id: agent.id,
        query_embedding: target_embedding,
      )

      expect(results.first).to eq(similar)
    end

    it "filters results by user_id when provided" do
      embedding  = Array.new(1536) { 0.5 }
      own_mem    = create(:archival_memory, agent:, user:, embedding:)
      other_user = create(:user)
      _other_mem = create(:archival_memory, agent:, user: other_user, embedding:)

      results = described_class.semantic_search(
        agent_id: agent.id,
        user_id: user.id,
        query_embedding: embedding,
      )

      expect(results).to contain_exactly(own_mem)
    end

    it "returns memories for all users when user_id is omitted" do
      embedding = Array.new(1536) { 0.5 }
      user2     = create(:user)
      mem1 = create(:archival_memory, agent:, user:, embedding:)
      mem2 = create(:archival_memory, agent:, user: user2, embedding:)

      results = described_class.semantic_search(
        agent_id: agent.id,
        query_embedding: embedding,
      )

      expect(results).to contain_exactly(mem1, mem2)
    end

    it "filters by tags when provided" do
      embedding = Array.new(1536) { 0.5 }
      tagged    = create(:archival_memory, agent:, user:, embedding:, tags: ["work"])
      untagged  = create(:archival_memory, agent:, user:, embedding:, tags: [])

      results = described_class.semantic_search(
        agent_id: agent.id,
        query_embedding: embedding,
        tags: ["work"],
      )

      expect(results).to include(tagged)
      expect(results).not_to include(untagged)
    end

    it "paginates results" do
      embedding = Array.new(1536) { 0.5 }
      create_list(:archival_memory, 5, agent:, user:, embedding:)

      results = described_class.semantic_search(
        agent_id: agent.id,
        query_embedding: embedding,
        per_page: 2,
        page: 0,
      )

      expect(results.size).to eq(2)
    end
  end
end
