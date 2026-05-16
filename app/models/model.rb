# frozen_string_literal: true

# == Schema Information
#
# Table name: models
# Database name: primary
#
#  id                :bigint           not null, primary key
#  capabilities      :jsonb
#  context_window    :integer
#  family            :string
#  knowledge_cutoff  :date
#  max_output_tokens :integer
#  metadata          :jsonb
#  modalities        :jsonb
#  model_created_at  :datetime
#  name              :string           not null
#  pricing           :jsonb
#  provider          :string           not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  model_id          :string           not null
#
# Indexes
#
#  index_models_on_capabilities           (capabilities) USING gin
#  index_models_on_family                 (family)
#  index_models_on_modalities             (modalities) USING gin
#  index_models_on_provider               (provider)
#  index_models_on_provider_and_model_id  (provider,model_id) UNIQUE
#
class Model < ApplicationRecord
  acts_as_model chats_foreign_key: :model_id

  PICKER_COLUMNS = [:model_id, :name, :provider, :capabilities].freeze
  ATTACHMENT_ACCEPTS_BY_INPUT_MODALITY = {
    "image" => ["image/*"],
    "pdf" => ["application/pdf"],
    "audio" => ["audio/*"],
    "video" => ["video/*"],
    "file" => ["*/*"],
  }.freeze
  ATTACHMENT_MODALITIES = ATTACHMENT_ACCEPTS_BY_INPUT_MODALITY.keys.freeze

  scope :picker_projection, -> { select(*PICKER_COLUMNS) }

  def supports_capability?(capability)
    Array(capabilities).map(&:to_s).include?(capability.to_s)
  end

  def supports_temperature?
    supports_capability?("temperature")
  end

  def supports_reasoning?
    supports_capability?("reasoning")
  end

  def supports_attachments?
    attachment_input_modalities.any?
  end

  def attachment_accept
    attachment_input_modalities
      .flat_map { |modality| ATTACHMENT_ACCEPTS_BY_INPUT_MODALITY.fetch(modality) }
      .uniq
      .join(",")
      .presence
  end

  def supports_attachment_content_type?(content_type)
    accept_patterns = attachment_accept.to_s.split(",")
    return false if accept_patterns.blank?
    return true if accept_patterns.include?("*/*")

    accept_patterns.any? do |pattern|
      pattern.end_with?("/*") ? content_type.to_s.start_with?(pattern.delete_suffix("*")) : pattern == content_type.to_s
    end
  end

  def attachment_input_modalities
    modalities = model_input_modalities & ATTACHMENT_MODALITIES
    return modalities if modalities.any?

    supports_capability?("vision") ? ["image"] : []
  end

  def model_input_modalities
    return [] unless modalities.is_a?(Hash)

    Array(modalities["input"] || modalities[:input]).compact_blank.map(&:to_s)
  end

  class << self
    private

    def from_llm_attributes(model_info)
      attrs = super
      attrs[:capabilities] = enrich_capabilities(attrs[:capabilities], model_info.metadata)
      attrs
    end

    def enrich_capabilities(capabilities, metadata)
      enriched = Array(capabilities).dup
      enriched << "temperature" if metadata[:temperature] == true || metadata["temperature"] == true
      enriched << "open_weights" if metadata[:open_weights] == true || metadata["open_weights"] == true
      enriched.uniq
    end
  end
end
