# frozen_string_literal: true

module Costs
  class Period
    Result = Data.define(:range, :label, :starts_at, :ends_at)
    PERIOD_START_METHODS = {
      "day" => :beginning_of_day,
      "week" => :beginning_of_week,
      "month" => :beginning_of_month,
      "quarter" => :beginning_of_quarter,
      "year" => :beginning_of_year,
    }.freeze
    ROLLING_DURATIONS = {
      "rolling_7_days" => 7.days,
      "rolling_30_days" => 30.days,
    }.freeze

    def self.resolve(period, now: Time.current)
      new(period, now:).resolve
    end

    def initialize(period, now: Time.current)
      @period = period.to_s
      @now = now
    end

    def resolve
      starts_at = period_start
      return Result.new(range: nil, label: "All time", starts_at: nil, ends_at: nil) unless starts_at

      Result.new(range: starts_at..@now, label:, starts_at:, ends_at: @now)
    end

    private

    def period_start
      method_name = PERIOD_START_METHODS[@period]
      return @now.public_send(method_name) if method_name

      duration = ROLLING_DURATIONS[@period]
      @now - duration if duration
    end

    def label
      {
        "day" => "Today",
        "week" => "This week",
        "month" => "This month",
        "quarter" => "This quarter",
        "year" => "This year",
        "rolling_7_days" => "Rolling 7 days",
        "rolling_30_days" => "Rolling 30 days",
      }.fetch(@period, "All time")
    end
  end
end
