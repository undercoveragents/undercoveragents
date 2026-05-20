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
require "rails_helper"

RSpec.describe MissionTrigger do
  include ActiveSupport::Testing::TimeHelpers

  subject(:mission_trigger) { build(:mission_trigger) }

  let(:mission) { create(:mission) }

  describe "associations" do
    it { is_expected.to belong_to(:mission) }
    it { is_expected.to belong_to(:last_mission_run).class_name("MissionRun").optional }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_length_of(:name).is_at_most(120) }

    it "validates case-insensitive name uniqueness per mission" do
      create(:mission_trigger, mission:, name: "Daily Sync")

      duplicate = build(:mission_trigger, mission:, name: "daily sync")

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:name]).to include("has already been taken")
    end
  end

  describe "enums" do
    it do
      expect(mission_trigger).to define_enum_for(:trigger_type)
        .with_values(schedule: "schedule", webhook: "webhook")
        .backed_by_column_of_type(:string)
        .with_prefix(:trigger)
    end
  end

  describe "schedule behavior" do
    before do
      travel_to(Time.find_zone!("UTC").parse("2026-05-20 06:15:00"))
    end

    it "calculates the next run from the cron expression and timezone" do
      trigger = create(
        :mission_trigger,
        :schedule,
        cron_expression: "0 9 * * *",
        timezone: "Europe/Rome",
      )

      expect(trigger.next_run_at).to eq(Time.find_zone!("Europe/Rome").parse("2026-05-20 09:00:00"))
    end

    it "advances the next run to a future occurrence" do
      trigger = create(:mission_trigger, :schedule, cron_expression: "*/15 * * * *")
      trigger.update_columns(next_run_at: Time.find_zone!("UTC").parse("2026-05-20 08:15:00")) # rubocop:disable Rails/SkipsModelValidations

      trigger.advance_next_run_at!(
        from: trigger.next_run_at,
        cutoff: Time.find_zone!("UTC").parse("2026-05-20 08:15:00"),
      )

      expect(trigger.next_run_at).to eq(Time.find_zone!("UTC").parse("2026-05-20 08:30:00"))
    end

    it "skips overdue occurrences until the next future run" do
      trigger = create(:mission_trigger, :schedule, cron_expression: "*/15 * * * *")
      trigger.update_columns(next_run_at: Time.find_zone!("UTC").parse("2026-05-20 08:00:00")) # rubocop:disable Rails/SkipsModelValidations

      trigger.advance_next_run_at!(
        from: trigger.next_run_at,
        cutoff: Time.find_zone!("UTC").parse("2026-05-20 08:15:00"),
      )

      expect(trigger.next_run_at).to eq(Time.find_zone!("UTC").parse("2026-05-20 08:30:00"))
    end

    it "rejects invalid cron expressions" do
      trigger = build(:mission_trigger, :schedule, cron_expression: "not a cron")

      expect(trigger).not_to be_valid
      expect(trigger.errors[:cron_expression]).to include("must be a valid cron expression")
    end

    it "skips cron format validation when the cron expression is blank" do
      trigger = build(:mission_trigger, :schedule, cron_expression: nil)

      trigger.validate

      expect(trigger.errors[:cron_expression]).to include("can't be blank")
    end

    it "adds a timezone validation error for invalid IANA names" do
      trigger = build(:mission_trigger, :schedule, timezone: "Mars/Olympus")

      expect(trigger).not_to be_valid
      expect(trigger.errors[:timezone]).to include("must be a valid IANA timezone")
    end

    it "clears next_run_at when a schedule is disabled" do
      trigger = create(:mission_trigger, :schedule, cron_expression: "0 * * * *")

      trigger.update!(enabled: false)

      expect(trigger.next_run_at).to be_nil
    end

    it "returns nil for cron when the trigger is not a schedule" do
      trigger = build(:mission_trigger, :webhook)

      expect(trigger.cron).to be_nil
    end
  end

  describe "payload handling" do
    it "returns an empty hash when the stored payload is not a hash" do
      trigger = described_class.new
      trigger[:payload] = "invalid"

      expect(trigger.payload).to eq({})
    end

    it "accepts JSON strings and exposes them as a hash" do
      trigger = build(:mission_trigger)

      trigger.payload = '{"report":"daily"}'

      expect(trigger.payload).to eq({ "report" => "daily" })
      expect(trigger.payload_json).to include('"report": "daily"')
    end

    it "adds a validation error for invalid JSON" do
      trigger = build(:mission_trigger)

      trigger.payload = "not-json"

      expect(trigger).not_to be_valid
      expect(trigger.errors[:payload]).to include("must be valid JSON")
    end

    it "adds a validation error when the payload is not a JSON object" do
      trigger = build(:mission_trigger)

      trigger.payload = 123

      expect(trigger).not_to be_valid
      expect(trigger.errors[:payload]).to include("must be a JSON object")
    end

    it "accepts action controller parameters" do
      trigger = build(:mission_trigger)

      trigger.payload = ActionController::Parameters.new(report: "daily")

      expect(trigger.payload).to eq({ "report" => "daily" })
    end

    it "normalizes nil payloads to an empty hash" do
      trigger = build(:mission_trigger)

      trigger.payload = nil

      expect(trigger.payload).to eq({})
    end

    it "rejects non-object JSON payloads" do
      trigger = build(:mission_trigger)

      trigger.payload = "[]"

      expect(trigger).not_to be_valid
      expect(trigger.errors[:payload]).to include("must be a JSON object")
    end

    it "returns an empty payload_json when the payload is blank" do
      trigger = described_class.new

      expect(trigger.payload_json).to eq("")
    end

    it "returns an empty payload_json when JSON generation fails" do
      trigger = described_class.new
      allow(trigger).to receive(:payload).and_return({ "report" => "daily" })
      allow(JSON).to receive(:pretty_generate).and_raise(JSON::GeneratorError.new("boom"))

      expect(trigger.payload_json).to eq("")
    end

    it "returns the original input when payload_json_input falls back after generation errors" do
      flaky_payload = Class.new do
        def blank?
          false
        end

        def to_s
          "flaky-payload"
        end
      end.new

      trigger = build(:mission_trigger)

      trigger.payload = flaky_payload

      expect(trigger.payload_json).to eq("flaky-payload")
    end
  end

  describe "webhook secret handling" do
    it "generates a secret for webhook triggers" do
      trigger = create(:mission_trigger, :webhook)

      expect(trigger.webhook_secret_prefix).to start_with("mtw_")
      expect(trigger.webhook_secret_digest).to be_present
    end

    it "regenerates the webhook secret" do
      trigger = create(:mission_trigger, :webhook)
      old_digest = trigger.webhook_secret_digest

      new_secret = trigger.regenerate_webhook_secret!

      expect(new_secret).to start_with("mtw_")
      expect(trigger.reload.webhook_secret_digest).not_to eq(old_digest)
      expect(trigger.webhook_secret_valid?(new_secret)).to be(true)
    end

    it "rejects blank webhook secrets" do
      trigger = create(:mission_trigger, :webhook)

      expect(trigger.webhook_secret_valid?(nil)).to be(false)
    end

    it "returns a masked secret preview when secret fields are present" do
      trigger = create(:mission_trigger, :webhook)

      expect(trigger.masked_webhook_secret).to start_with(trigger.webhook_secret_prefix)
      expect(trigger.masked_webhook_secret).to include("*" * 24)
    end

    it "returns an empty masked secret when the secret is missing" do
      trigger = described_class.new

      expect(trigger.masked_webhook_secret).to eq("")
    end
  end

  describe "sync_mission_compatibility_state" do
    it "skips schedulable_type assignment when type is already set and no mission is given" do
      trigger = build(:mission_trigger, :schedule, cron_expression: "0 * * * *")
      # Stub mission to return nil so condition (schedulable_type.blank? || mission.present?) is false
      allow(trigger).to receive(:mission).and_return(nil)

      trigger.send(:sync_mission_compatibility_state)

      expect(trigger.schedulable_type).to eq("Mission")
    end
  end

  describe "private helpers" do
    it "returns nil when converting a blank fugit time" do
      trigger = build(:mission_trigger, :schedule)

      expect(trigger.send(:fugit_time_to_zone, nil)).to be_nil
    end

    it "converts times that do not expose utc directly" do
      converted_time = Time.find_zone!("UTC").parse("2026-05-20 09:00:00")
      raw_time = Class.new do
        def initialize(converted_time)
          @converted_time = converted_time
        end

        def blank?
          false
        end

        def in_time_zone(_timezone)
          @converted_time
        end
      end.new(converted_time)

      trigger = build(:mission_trigger, :schedule)

      expect(trigger.send(:fugit_time_to_zone, raw_time)).to eq(converted_time)
    end

    it "skips timezone validation when the timezone is blank" do
      trigger = build(:mission_trigger, :schedule)
      trigger.timezone = nil
      trigger.errors.clear

      trigger.send(:timezone_must_be_valid)

      expect(trigger.errors[:timezone]).to be_empty
    end

    it "normalizes blank payload strings to an empty hash" do
      trigger = build(:mission_trigger)

      expect(trigger.send(:normalize_payload, "   ")).to eq({})
    end

    it "returns an empty payload_json_input when a stripped string is blank" do
      blank_string = Class.new(String) do
        def blank?
          false
        end
      end.new("   ")
      trigger = build(:mission_trigger)

      expect(trigger.send(:payload_json_input, blank_string)).to eq("")
    end

    it "returns an empty payload_json_input when a non-string becomes blank later" do
      blank_later = Class.new do
        def initialize
          @blank_checks = 0
        end

        def blank?
          @blank_checks += 1
          @blank_checks > 1
        end
      end.new
      trigger = build(:mission_trigger)

      expect(trigger.send(:payload_json_input, blank_later)).to eq("")
    end
  end
end
