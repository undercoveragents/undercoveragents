# frozen_string_literal: true

module TestSuiteMetricsHelper
  def test_result_score_display(result)
    return "—" unless result.score

    percentage = (result.score * 100).round(0)
    color = score_color(result.score)
    content_tag(:span, "#{percentage}%", class: "font-semibold #{color}")
  end

  def test_run_pass_rate_display(run)
    return "—" if run.total_count.zero?

    rate = run.pass_rate
    color = score_color(rate / 100.0)
    content_tag(:span, "#{rate}%", class: "font-semibold #{color}")
  end

  def test_run_duration_display(run)
    return "—" unless run.duration_ms

    seconds = run.duration_ms / 1000.0
    return "#{seconds.round(1)}s" if seconds < 60

    minutes = (seconds / 60).floor
    remaining = (seconds % 60).round(0)
    "#{minutes}m #{remaining}s"
  end

  def test_result_duration_display(result)
    return "—" unless result.duration_ms

    "#{(result.duration_ms / 1000.0).round(1)}s"
  end

  def test_run_cost_display(run, cost: nil)
    cost = run.calculate_cost if cost.nil?
    return "—" if cost.zero?

    format("$%.6f", cost)
  end

  def test_run_input_tokens_display(run)
    tokens = run.total_input_tokens
    return "—" if tokens.zero?

    number_with_delimiter(tokens)
  end

  def test_run_output_tokens_display(run)
    tokens = run.total_output_tokens
    return "—" if tokens.zero?

    number_with_delimiter(tokens)
  end

  def test_result_cost_display(result)
    cost = result.calculate_cost
    return "—" if cost.zero?

    format("$%.6f", cost)
  end

  def test_result_input_tokens_display(result)
    tokens = result.input_tokens
    return "—" if tokens.zero?

    number_with_delimiter(tokens)
  end

  def test_result_output_tokens_display(result)
    tokens = result.output_tokens
    return "—" if tokens.zero?

    number_with_delimiter(tokens)
  end

  def test_result_agent_breakdown_display(result)
    format_breakdown(
      input_tokens: result.agent_input_tokens,
      output_tokens: result.agent_output_tokens,
      cost: result.agent_cost,
    )
  end

  def test_result_evaluator_breakdown_display(result)
    format_breakdown(
      input_tokens: result.evaluator_input_tokens,
      output_tokens: result.evaluator_output_tokens,
      cost: result.evaluator_cost,
    )
  end

  def test_run_agent_breakdown_display(run)
    format_breakdown(
      input_tokens: run.agent_input_tokens,
      output_tokens: run.agent_output_tokens,
      cost: run.agent_cost,
    )
  end

  def test_run_evaluator_breakdown_display(run)
    format_breakdown(
      input_tokens: run.evaluator_input_tokens,
      output_tokens: run.evaluator_output_tokens,
      cost: run.evaluator_cost,
    )
  end

  def test_run_tokens_display(run)
    "In: #{test_run_input_tokens_display(run)} • Out: #{test_run_output_tokens_display(run)}"
  end

  def test_result_tokens_display(result)
    "In: #{test_result_input_tokens_display(result)} • Out: #{test_result_output_tokens_display(result)}"
  end

  private

  def format_breakdown(input_tokens:, output_tokens:, cost:)
    input_display = input_tokens.zero? ? "—" : number_with_delimiter(input_tokens)
    output_display = output_tokens.zero? ? "—" : number_with_delimiter(output_tokens)
    cost_display = cost.zero? ? "—" : format("$%.6f", cost)
    "In: #{input_display} • Out: #{output_display} • Cost: #{cost_display}"
  end

  def score_color(score)
    case score
    when 0.8..1.0 then "text-green-500"
    when 0.5..0.8 then "text-amber-500"
    else "text-red-500"
    end
  end
end
