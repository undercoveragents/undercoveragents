# frozen_string_literal: true

# == Schema Information
#
# Table name: automation_triggers
# Database name: primary
#
#  id                      :bigint           not null, primary key
#  cron_expression         :string
#  enabled                 :boolean          default(TRUE), not null
#  last_error              :text
#  last_result_record_type :string
#  last_triggered_at       :datetime
#  name                    :string           not null
#  next_run_at             :datetime
#  payload                 :jsonb            not null
#  schedulable_type        :string           not null
#  timezone                :string           default("UTC"), not null
#  trigger_type            :string           not null
#  webhook_secret_digest   :string
#  webhook_secret_prefix   :string
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  last_result_record_id   :bigint
#  operation_id            :bigint           not null
#  schedulable_id          :bigint           not null
#
# Indexes
#
#  index_automation_triggers_on_last_result_record    (last_result_record_type,last_result_record_id)
#  index_automation_triggers_on_operation_id          (operation_id)
#  index_automation_triggers_on_schedulable           (schedulable_type,schedulable_id)
#  index_automation_triggers_on_schedulable_and_name  (schedulable_type,schedulable_id,name) UNIQUE
#  index_automation_triggers_on_schedule_state        (trigger_type,enabled,next_run_at)
#
# Foreign Keys
#
#  fk_rails_...  (operation_id => operations.id)
#
class AutomationTrigger < ApplicationRecord
  WEBHOOK_SECRET_HEADER = "X-UndercoverAgents-Webhook-Secret"
  WEBHOOK_SECRET_PREFIX = "atw_"
  WEBHOOK_SECRET_BYTE_LENGTH = 32
  SUPPORTED_SCHEDULABLE_TYPES = {
    "Mission" => "Mission",
    "RagFlow" => "RAG Flow",
  }.freeze

  attr_reader :raw_webhook_secret

  enum :trigger_type, { schedule: "schedule", webhook: "webhook" }, validate: true, prefix: :trigger

  belongs_to :operation
  belongs_to :schedulable, polymorphic: true
  belongs_to :last_result_record, polymorphic: true, optional: true

  scope :ordered, -> { order(:name) }
  scope :enabled, -> { where(enabled: true) }
  scope :due_schedule, lambda { |at = Time.current|
    where(trigger_type: "schedule", enabled: true)
      .where.not(next_run_at: nil)
      .where(next_run_at: ..at)
  }

  validates :name,
            presence: true,
            uniqueness: { scope: [:schedulable_type, :schedulable_id], case_sensitive: false },
            length: { maximum: 120 }
  validates :schedulable_type, inclusion: { in: SUPPORTED_SCHEDULABLE_TYPES.keys }
  validates :timezone, presence: true, if: :trigger_schedule?
  validates :cron_expression, presence: true, if: :trigger_schedule?
  validates :cron_expression, absence: true, unless: :trigger_schedule?
  validates :webhook_secret_prefix, :webhook_secret_digest, presence: true, if: :trigger_webhook?
  validate :payload_must_be_valid
  validate :cron_expression_must_be_valid
  validate :timezone_must_be_valid
  validate :operation_matches_schedulable

  before_validation :sync_operation_from_schedulable
  before_validation :normalize_type_specific_state
  before_validation :ensure_webhook_secret, if: :trigger_webhook?
  before_validation :refresh_next_run_at

  def self.generate_webhook_secret
    raw = SecureRandom.hex(WEBHOOK_SECRET_BYTE_LENGTH)
    raw_secret = "#{WEBHOOK_SECRET_PREFIX}#{raw}"

    {
      raw_secret:,
      prefix: "#{WEBHOOK_SECRET_PREFIX}#{raw[0, 8]}",
      digest: Digest::SHA256.hexdigest(raw_secret),
    }
  end

  def payload
    value = self[:payload]
    value.is_a?(Hash) ? value.deep_stringify_keys : {}
  end

  def payload=(value)
    @payload_error = nil
    @payload_json_input = payload_json_input(value)
    super(normalize_payload(value))
  rescue JSON::ParserError, TypeError, ArgumentError => e
    @payload_error = if e.is_a?(JSON::ParserError)
                       "must be valid JSON"
                     else
                       e.message.presence || "must be a JSON object"
                     end
    super({})
  end

  def payload_json
    return @payload_json_input if defined?(@payload_json_input)

    payload.present? ? JSON.pretty_generate(payload) : ""
  rescue JSON::GeneratorError
    ""
  end

  def cron
    return nil unless trigger_schedule? && cron_expression.present?

    Fugit::Cron.parse("#{cron_expression} #{timezone}")
  end

  def due_for_dispatch?(at: Time.current)
    trigger_schedule? && enabled? && next_run_at.present? && next_run_at <= at
  end

  def advance_next_run_at!(from: next_run_at || Time.current, cutoff: Time.current)
    self.next_run_at = next_future_occurrence(from:, cutoff:)
  end

  def webhook_secret_valid?(raw_secret)
    return false if raw_secret.blank? || webhook_secret_digest.blank?

    digest = Digest::SHA256.hexdigest(raw_secret)
    ActiveSupport::SecurityUtils.secure_compare(webhook_secret_digest, digest)
  end

  def masked_webhook_secret
    return "" if webhook_secret_prefix.blank? || webhook_secret_digest.blank?

    "#{webhook_secret_prefix}#{"*" * 24}#{webhook_secret_digest.last(8)}"
  end

  def regenerate_webhook_secret!
    secret_data = self.class.generate_webhook_secret
    @raw_webhook_secret = secret_data[:raw_secret]
    update!(
      webhook_secret_prefix: secret_data[:prefix],
      webhook_secret_digest: secret_data[:digest],
    )
    @raw_webhook_secret
  end

  def schedulable_label
    SUPPORTED_SCHEDULABLE_TYPES.fetch(schedulable_type, schedulable_type.to_s)
  end

  private

  def sync_operation_from_schedulable
    self.operation ||= schedulable.operation if schedulable.respond_to?(:operation)
  end

  def normalize_type_specific_state
    self.timezone = timezone.presence || "UTC"

    if trigger_schedule?
      self.webhook_secret_prefix = nil
      self.webhook_secret_digest = nil
      return
    end

    self.cron_expression = nil
    self.next_run_at = nil
  end

  def ensure_webhook_secret
    return if webhook_secret_digest.present? && webhook_secret_prefix.present?

    secret_data = self.class.generate_webhook_secret
    @raw_webhook_secret = secret_data[:raw_secret]
    self.webhook_secret_prefix = secret_data[:prefix]
    self.webhook_secret_digest = secret_data[:digest]
  end

  def refresh_next_run_at
    return unless trigger_schedule?
    return disable_schedule! unless enabled?
    return unless refresh_schedule_timing?

    self.next_run_at = next_future_occurrence(from: Time.current)
  end

  def next_future_occurrence(from:, cutoff: Time.current)
    scheduled_at = next_occurrence_after(from)
    scheduled_at = next_occurrence_after(scheduled_at + 1.second) while scheduled_at.present? && scheduled_at <= cutoff
    scheduled_at
  end

  def next_occurrence_after(reference_time)
    parsed = cron
    return if parsed.blank?

    time = parsed.next_time(reference_time)
    fugit_time_to_zone(time)
  end

  def fugit_time_to_zone(time)
    return if time.blank?

    converted = time.respond_to?(:utc) ? time.utc : time
    converted.in_time_zone(timezone)
  end

  def normalize_payload(value)
    case value
    when nil
      {}
    when String
      stripped = value.strip
      stripped.present? ? parse_payload_json(stripped) : {}
    when ActionController::Parameters
      value.to_unsafe_h.deep_stringify_keys
    when Hash
      value.deep_stringify_keys
    else
      raise TypeError, "must be a JSON object"
    end
  end

  def parse_payload_json(value)
    parsed = JSON.parse(value)
    raise TypeError, "must be a JSON object" unless parsed.is_a?(Hash)

    parsed.deep_stringify_keys
  end

  def payload_json_input(value)
    return "" if value.blank?

    if value.is_a?(String)
      stripped = value.strip
      return "" if stripped.blank?

      return JSON.pretty_generate(parse_payload_json(stripped))
    end

    return "" if value.blank?

    JSON.pretty_generate(normalize_payload(value))
  rescue JSON::ParserError, TypeError, ArgumentError, JSON::GeneratorError
    value.to_s
  end

  def payload_must_be_valid
    return if @payload_error.blank?

    errors.add(:payload, @payload_error)
  end

  def cron_expression_must_be_valid
    return unless trigger_schedule?
    return if cron_expression.blank?
    return if cron.present?

    errors.add(:cron_expression, "must be a valid cron expression")
  end

  def disable_schedule!
    self.next_run_at = nil
  end

  def refresh_schedule_timing?
    new_record? ||
      will_save_change_to_cron_expression? ||
      will_save_change_to_timezone? ||
      will_save_change_to_enabled? ||
      will_save_change_to_trigger_type?
  end

  def timezone_must_be_valid
    return unless trigger_schedule?
    return if timezone.blank?
    return if Time.find_zone(timezone).present?

    errors.add(:timezone, "must be a valid IANA timezone")
  end

  def operation_matches_schedulable
    return unless operation && schedulable.respond_to?(:operation)
    return if schedulable.operation == operation

    errors.add(:operation, "must match the scheduled record's operation")
  end
end
