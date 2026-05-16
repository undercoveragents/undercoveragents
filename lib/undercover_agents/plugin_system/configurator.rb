# frozen_string_literal: true

module UndercoverAgents
  module PluginSystem
    # Base concern for plugin configurator models (ActiveModel-backed).
    # Replaces the AR-backed steppable pattern with a JSONB-backed configuration
    # object that responds to the same protocol interface.
    #
    # Usage in a plugin model:
    #   class RagSteps::FixedSizeChunker
    #     include UndercoverAgents::PluginSystem::Configurator
    #     include RagStepPlugin
    #
    #     attribute :chunk_size, :integer, default: 1000
    #     attribute :chunk_overlap, :integer, default: 200
    #     ...
    #   end
    module Configurator
      extend ActiveSupport::Concern

      included do
        include ActiveModel::Model
        include ActiveModel::Attributes
        include ActiveModel::Validations
        include ActiveModel::Validations::Callbacks
      end

      # Serialize this configurator's attributes back to a hash
      # suitable for storing in the JSONB configuration column.
      def to_configuration
        attributes.compact
      end

      # Provides a "new_record?" for form compatibility
      def new_record?
        true
      end
    end
  end
end
