# frozen_string_literal: true

# Compatibility wrapper for legacy references.
#
# ToolPlugin is the canonical registry/protocol.
module ToolType
  extend ActiveSupport::Concern
  include ToolPlugin

  Result = ToolPlugin::Result

  class << self
    delegate :resolve, :filter_type, :type_keys, :type_options, to: ToolPlugin
  end
end
