# frozen_string_literal: true

module RagSteps
  module ChunkerConfigurable
    extend ActiveSupport::Concern

    MAX_CHUNK_SIZE = 50_000
    MAX_CHUNK_OVERLAP = 10_000

    included do
      attribute :chunk_size, :integer, default: 1000
      attribute :chunk_overlap, :integer, default: 200

      validates :chunk_size, presence: true,
                             numericality: {
                               only_integer: true,
                               greater_than: 0,
                               less_than_or_equal_to: MAX_CHUNK_SIZE,
                             }
      validates :chunk_overlap, presence: true,
                                numericality: {
                                  only_integer: true,
                                  greater_than_or_equal_to: 0,
                                  less_than_or_equal_to: MAX_CHUNK_OVERLAP,
                                }
      validate :overlap_must_be_less_than_size
    end

    def execute(documents, context)
      Rag::Steps::ChunkerExecutor.new(self, context).call(documents)
    end

    def validate_configuration!
      raise "Chunk size must be positive" unless chunk_size&.positive?
    end

    private

    def overlap_must_be_less_than_size
      return if chunk_overlap.blank? || chunk_size.blank?
      return if chunk_overlap < chunk_size

      errors.add(:chunk_overlap, "must be less than chunk size")
    end
  end
end
