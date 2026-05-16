# frozen_string_literal: true

# == Schema Information
#
# Table name: tools
# Database name: primary
#
#  id            :bigint           not null, primary key
#  configuration :jsonb            not null
#  description   :text
#  enabled       :boolean          default(TRUE), not null
#  name          :string           not null
#  slug          :string           not null
#  tool_type     :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  operation_id  :bigint           not null
#
# Indexes
#
#  index_tools_on_enabled                (enabled)
#  index_tools_on_operation_id           (operation_id)
#  index_tools_on_operation_id_and_name  (operation_id,name) UNIQUE
#  index_tools_on_slug                   (slug) UNIQUE
#  index_tools_on_tool_type              (tool_type)
#
# Foreign Keys
#
#  fk_rails_...  (operation_id => operations.id)
#
class Tool < ApplicationRecord
  extend FriendlyId
  include Turbo::Broadcastable

  friendly_id :name, use: :slugged

  belongs_to :operation

  scope :enabled, -> { where(enabled: true) }
  scope :disabled, -> { where(enabled: false) }
  scope :by_type, lambda { |type|
    normalized = ToolPlugin.filter_type(type)
    normalized ? where(tool_type: normalized) : none
  }
  scope :ordered, -> { order(:name) }
  validates :tool_type, presence: true
  validate :tool_type_registered

  validates :name, presence: true, uniqueness: { scope: :operation_id, case_sensitive: false }, length: { maximum: 100 }
  validates :description, length: { maximum: 500 }
  before_validation :ensure_configuration
  before_validation :validate_configurator
  before_save :apply_configurator_before_save

  # Configure amoeba for deep cloning.
  # JSONB configuration is copied naturally.
  amoeba do
    enable
    prepend name: "Copy of "
  end

  def configurator
    return @configurator if @configurator && @configurator_built_for_type == tool_type

    @configurator = build_configurator
  end

  def configurator=(value)
    @configurator = value
    @configurator_built_for_type = tool_type
  end

  def configuration=(value)
    super
    @configurator = nil
    @configurator_built_for_type = nil
  end

  def reload(*)
    @configurator = nil
    @configurator_built_for_type = nil
    super
  end

  # :nocov:
  def method_missing(method_name, ...)
    if configurator.respond_to?(method_name)
      configurator.public_send(method_name, ...)
    else
      super
    end
  end

  def respond_to_missing?(method_name, include_private = false)
    configurator.respond_to?(method_name, include_private) || super
  end
  # :nocov:

  def type_label
    ToolPlugin.label_for(tool_type) || tool_type.to_s.humanize
  end

  def type_icon
    ToolPlugin.icon_for(tool_type) || "fa-solid fa-wrench"
  end

  # Compatibility API for legacy code paths.
  def toolable
    configurator
  end

  def toolable=(value)
    return if value.nil?

    resolved_type = ToolPlugin.key_for_class_name(value.class.name)
    resolved_type ||= value.class.type_key if value.class.respond_to?(:type_key)

    self.tool_type = resolved_type
    self.configurator = value
  end

  # :nocov:
  def toolable_type
    configurator&.class&.name
  end

  def toolable_id
    return unless configuration.is_a?(Hash)

    configuration["record_id"] || configuration[:record_id]
  end
  # :nocov:

  def should_generate_new_friendly_id?
    name_changed? || slug.blank?
  end

  private

  # :nocov:
  def build_configurator
    @configurator_built_for_type = tool_type
    klass = ToolPlugin.resolve(tool_type)
    return nil unless klass

    build_configurator_from(klass)
  rescue StandardError
    nil
  end

  def build_configurator_from(klass)
    if klass < ApplicationRecord
      build_record_configurator(klass)
    elsif klass.respond_to?(:new)
      build_struct_configurator(klass)
    end
  end

  def build_record_configurator(klass)
    record_id = configuration_value(:record_id)
    return nil if record_id.blank?

    klass.find_by(id: record_id)
  end

  def build_struct_configurator(klass)
    cfg = klass.new((configuration || {}).symbolize_keys.except(:record_id))
    cfg._tool_record = self if cfg.respond_to?(:_tool_record=)
    cfg
  end
  # :nocov:

  def tool_type_registered
    return if tool_type.blank?
    return if ToolPlugin.type_keys.include?(tool_type)

    errors.add(:tool_type, "is not a registered tool type")
  end

  def ensure_configuration
    self.configuration = {} unless configuration.is_a?(Hash)
  end

  def validate_configurator
    return unless configurator
    return if configurator.respond_to?(:persisted?) && configurator.persisted?
    return if configurator.valid?

    configurator.errors.each do |error|
      errors.add(error.attribute, error.message)
    end
  end

  def apply_configurator_before_save
    cfg = configurator
    return unless cfg

    if cfg.is_a?(ApplicationRecord)
      self.configuration = { "record_id" => cfg.id }
    elsif cfg.respond_to?(:to_configuration)
      self.configuration = cfg.to_configuration
    end

    cfg._tool_record = self if cfg.respond_to?(:_tool_record=)

    @configurator = cfg
    @configurator_built_for_type = tool_type
  end

  # :nocov:
  def configuration_value(key)
    return nil unless configuration.is_a?(Hash)

    configuration[key.to_s] || configuration[key.to_sym]
  end
  # :nocov:
end
