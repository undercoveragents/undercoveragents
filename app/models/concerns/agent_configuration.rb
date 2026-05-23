# frozen_string_literal: true

# Provides JSONB-backed configuration accessors, validations, and
# convenience helpers for the Agent model.
module AgentConfiguration
  extend ActiveSupport::Concern
  include AgentLlmConfiguration
  include AgentLinkConfiguration
  include AgentConfigurationValidations

  def self.extended(base)
    base.extend AgentLlmConfiguration
    base.extend AgentLinkConfiguration
  end

  TEMPERATURE_RANGE = (0.0..2.0)
  THINKING_EFFORTS = Llm::ChatOptions::THINKING_EFFORTS
  RESPONSE_FORMATS = ["text", "json_object", "json_schema"].freeze
  DEFAULT_TEMPERATURE = 0.7
  DEFAULT_AGENT_TYPE = "general"
  DEFAULT_LLM_CONFIG_SOURCE = "agent"
  DEFAULT_RESPONSE_FORMAT = "text"
  LLM_CONFIG_SOURCES = ["agent", "system_preference", "runtime"].freeze

  # ── Scalar accessors ──

  def description
    configuration["description"]
  end

  def description=(value)
    self.configuration = (configuration || {}).merge("description" => value)
  end

  def instructions
    configuration["instructions"]
  end

  def instructions=(value)
    self.configuration = (configuration || {}).merge("instructions" => value)
  end

  def agent_type
    configuration["agent_type"].presence || DEFAULT_AGENT_TYPE
  end

  def agent_type=(value)
    self.configuration = (configuration || {}).merge("agent_type" => value.presence)
  end

  def enabled?
    configuration["enabled"] != false
  end
  alias enabled enabled?

  def enabled=(value)
    self.configuration = (configuration || {}).merge("enabled" => ActiveModel::Type::Boolean.new.cast(value))
  end

  def selectable?
    configuration["selectable"] != false
  end
  alias selectable selectable?

  def selectable=(value)
    self.configuration = (configuration || {}).merge("selectable" => ActiveModel::Type::Boolean.new.cast(value))
  end

  def builtin
    ActiveModel::Type::Boolean.new.cast(configuration["builtin"])
  end
  alias builtin? builtin

  def builtin=(value)
    self.configuration = (configuration || {}).merge("builtin" => ActiveModel::Type::Boolean.new.cast(value))
  end

  def builtin_key
    configuration["builtin_key"].presence
  end

  def builtin_key=(value)
    self.configuration = (configuration || {}).merge("builtin_key" => value.presence)
  end

  def builtin_source
    configuration["builtin_source"].presence
  end

  def builtin_source=(value)
    self.configuration = (configuration || {}).merge("builtin_source" => value.presence)
  end
end
