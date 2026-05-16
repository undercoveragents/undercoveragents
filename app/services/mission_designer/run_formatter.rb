# frozen_string_literal: true

module MissionDesigner
  class RunFormatter
    DEFAULT_RECENT_LIMIT = 5
    MAX_RECENT_LIMIT = 10
    FULL_VALUE_LIMIT = 4_000
    SUMMARY_TIMELINE_LIMIT = 5
    VALUE_PREVIEW_LIMIT = 240

    def initialize(mission:)
      @mission = mission
    end

    def format_run(run, detail: nil)
      state = Missions::DebugRunState.new(mission:, run:)
      full = full_detail?(detail)
      parts = []

      append_overview(parts, run, state)
      append_error(parts, run)
      append_value_section(parts, "Trigger Data", run.trigger_data, full:)
      append_value_section(parts, "Visible Variables", state.variables, full:)
      append_value_section(parts, "Output Meta", output_meta(run), full:) if output_meta(run).present?
      append_value_section(parts, "Node Outputs", state.node_outputs, full:) if full
      append_execution_log(parts, state.execution_log, full:)

      parts.join("\n")
    end

    def format_recent_runs(runs, limit: nil)
      selected_runs = Array(runs).first(normalize_limit(limit))
      return "No mission runs found for '#{mission.name}'." if selected_runs.empty?

      parts = ["## Recent Mission Runs (#{selected_runs.size})"]
      selected_runs.each do |run|
        parts << format_recent_run_line(run)
      end
      parts.join("\n")
    end

    private

    attr_reader :mission

    def append_overview(parts, run, state)
      parts << "## Mission Run"
      overview_lines(run, state).each { |line| parts << line }
    end

    def append_error(parts, run)
      return if run.error.blank?

      parts << ""
      parts << "## Error"
      parts << render_value(run.error, full: true)
    end

    def append_value_section(parts, title, value, full:)
      parts << ""
      parts << "## #{title}"
      parts << render_value(value, full:)
    end

    def overview_lines(run, state)
      stats = execution_stats(state.execution_log)

      [
        "- mission: #{mission.name} (id: #{mission.id}, slug: `#{mission.slug}`)",
        "- run_id: `#{run.id}`",
        "- status: #{run.status}",
        "- created_at: #{format_time(run.created_at)}",
        "- started_at: #{format_time(run.started_at)}",
        "- completed_at: #{format_time(run.completed_at)}",
        "- duration_ms: #{format_duration_ms(run)}",
        "- current_node_id: #{run.current_node_id.presence || "-"}",
        "- execution_steps: #{stats[:total]}",
        "- successful_steps: #{stats[:success]}",
        "- failed_steps: #{stats[:failure]}",
        "- skipped_steps: #{stats[:skip]}",
      ]
    end

    def append_execution_log(parts, execution_log, full:)
      parts << ""
      parts << "## Execution Log (#{execution_log.size})"
      return parts << "No node executions recorded." if execution_log.empty?

      full ? append_full_execution_log(parts, execution_log) : append_summary_execution_log(parts, execution_log)
    end

    def append_full_execution_log(parts, execution_log)
      execution_log.each_with_index do |entry, index|
        parts.concat(full_execution_log_lines(entry, index + 1))
      end
    end

    def append_summary_execution_log(parts, execution_log)
      visible_entries = execution_log.last(SUMMARY_TIMELINE_LIMIT)
      omitted_count = execution_log.size - visible_entries.size

      visible_entries.each_with_index do |entry, index|
        absolute_index = execution_log.size - visible_entries.size + index + 1
        parts << summary_execution_log_line(entry, absolute_index)
      end

      parts << "- earlier_steps_omitted: #{omitted_count}" if omitted_count.positive?
    end

    def append_labeled_value(parts, label, value, full:)
      rendered = render_value(value, full:)
      if rendered.include?("\n")
        parts << "- #{label}:"
        rendered.each_line { |line| parts << "  #{line.rstrip}" }
      else
        parts << "- #{label}: #{rendered}"
      end
    end

    def full_execution_log_lines(entry, step_number)
      lines = [
        "",
        "### Step #{step_number}",
        "- node: #{entry["node_label"].presence || entry["node_id"]} [#{entry["node_type"]}]",
        "- node_id: `#{entry["node_id"]}`",
        "- status: #{entry["status"]}",
        "- next_port: #{entry["next_port"].presence || "-"}",
        "- duration_ms: #{entry["duration_ms"] || "-"}",
        "- started_at: #{entry["started_at"].presence || "-"}",
        "- finished_at: #{entry["finished_at"].presence || "-"}",
      ]

      append_labeled_value(lines, "input", entry["input"], full: true)
      append_labeled_value(lines, "output", entry["output"], full: true)
      append_labeled_value(lines, "error", entry["error"], full: true) if entry["error"].present?
      lines
    end

    def summary_execution_log_line(entry, absolute_index)
      [
        "- step #{absolute_index}: #{entry["node_label"].presence || entry["node_id"]} [#{entry["node_type"]}]",
        "status=#{entry["status"]}",
        presence_segment("next", entry["next_port"]),
        presence_segment("duration_ms", entry["duration_ms"]),
        preview_segment("input", entry["input"]),
        preview_segment("output", entry["output"]),
        preview_segment("error", entry["error"]),
      ].compact.join(" ")
    end

    def presence_segment(label, value)
      return if value.blank?

      "#{label}=#{value}"
    end

    def preview_segment(label, value)
      return if blank_value?(value)

      "#{label}=#{preview_value(value)}"
    end

    def render_value(value, full:)
      return "None." if blank_value?(value)

      text = stringify_value(value)
      return truncate_text(text, FULL_VALUE_LIMIT) if full

      truncate_text(text.gsub(/\s+/, " ").strip, VALUE_PREVIEW_LIMIT)
    end

    def preview_value(value)
      render_value(value, full: false)
    end

    def stringify_value(value)
      case value
      when Hash, Array
        JSON.pretty_generate(value)
      else
        value.to_s
      end
    end

    def truncate_text(text, limit)
      return text if text.length <= limit

      "#{text[0, limit - 15]}... (truncated)"
    end

    def format_recent_run_line(run)
      execution_count = Array(run.execution_state&.[]("execution_log")).size
      line = "- run_id=`#{run.id}` status=#{run.status} created_at=#{format_time(run.created_at)}"
      line << " duration_ms=#{format_duration_ms(run)}"
      line << " steps=#{execution_count}"
      line << " current_node=#{run.current_node_id}" if run.current_node_id.present?
      line << " error=#{preview_value(run.error)}" if run.error.present?
      line
    end

    def execution_stats(execution_log)
      counts = execution_log.each_with_object(Hash.new(0)) do |entry, tally|
        tally[entry["status"].to_s] += 1
        tally[:total] += 1
      end

      {
        total: counts[:total],
        success: counts["success"],
        failure: counts["failure"],
        skip: counts["skip"],
      }
    end

    def output_meta(run)
      run.variables.is_a?(Hash) ? run.variables["_output_meta"] : nil
    end

    def format_time(value)
      value&.iso8601(3) || "-"
    end

    def format_duration_ms(run)
      return "-" unless run.duration

      (run.duration * 1000).round(1).to_s
    end

    def normalize_limit(limit)
      parsed = Integer(limit || DEFAULT_RECENT_LIMIT, exception: false) || DEFAULT_RECENT_LIMIT
      parsed.clamp(1, MAX_RECENT_LIMIT)
    end

    def full_detail?(detail)
      detail.to_s == "full"
    end

    def blank_value?(value)
      value.nil? || (value.respond_to?(:empty?) && value.empty?)
    end
  end
end
