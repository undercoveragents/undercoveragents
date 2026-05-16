# frozen_string_literal: true

# == Schema Information
#
# Table name: archival_memories
# Database name: primary
#
#  id         :bigint           not null, primary key
#  content    :text             not null
#  embedding  :vector(1536)
#  tags       :string           default([]), not null, is an Array
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  agent_id   :bigint           not null
#  user_id    :bigint           not null
#
# Indexes
#
#  index_archival_memories_on_agent_id  (agent_id)
#  index_archival_memories_on_tags      (tags) USING gin
#  index_archival_memories_on_user_id   (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (agent_id => agents.id)
#  fk_rails_...  (user_id => users.id)
#
class ArchivalMemory < ApplicationRecord
  belongs_to :agent
  belongs_to :user

  has_neighbors :embedding

  scope :with_tags, ->(tags) { where("tags && ARRAY[?]::varchar[]", Array(tags)) }
  scope :for_agent, ->(agent_id) { where(agent_id:) }
  scope :for_user, ->(user_id) { where(user_id:) }
  scope :recent, -> { order(created_at: :desc) }
  validates :content, presence: true
  validate :user_must_belong_to_agent_tenant

  # Semantic search using cosine similarity via pgvector.
  #
  # @param agent_id [Integer]
  # @param query_embedding [Array<Float>]
  # @param tags [Array<String>] optional tag filter
  # @param page [Integer] 0-indexed page number
  # @param per_page [Integer]
  # @return [ActiveRecord::Relation]
  def self.semantic_search(agent_id:, query_embedding:, **options)
    scope = for_agent(agent_id)
    scope = scope.for_user(options[:user_id]) if options[:user_id]
    tags = options.fetch(:tags, [])
    page = options[:page] || 0
    per_page = options[:per_page] || 10
    scope = scope.with_tags(tags) if tags.any?
    scope
      .nearest_neighbors(:embedding, query_embedding, distance: "cosine")
      .limit(per_page)
      .offset(page * per_page)
  end

  private

  def user_must_belong_to_agent_tenant
    return if agent.blank? || user.blank?
    return if agent.operation.tenant_id == user.tenant_id

    errors.add(:user, "must belong to the same tenant as the agent")
  end
end
