# frozen_string_literal: true

require "rails_helper"

RSpec.describe Missions::ExecutionContext do
  let(:run) { create(:mission_run, mission: create(:mission)) }
  let(:ctx) { described_class.new(mission_run: run) }

  describe "#set_variable / #get_variable" do
    it "stores and retrieves a simple variable" do
      ctx.set_variable("score", 42)

      expect(ctx.get_variable("score")).to eq(42)
    end

    it "normalizes variable keys" do
      ctx.set_variable("My Score", 10)

      expect(ctx.get_variable("my_score")).to eq(10)
    end
  end

  describe "#evaluate!" do
    it "returns the result for a valid expression" do
      ctx.set_variable("x", 10)

      expect(ctx.evaluate!("x * 2")).to eq(20)
    end

    it "raises ExpressionError for an invalid expression" do
      expect { ctx.evaluate!("1 / 0") }
        .to raise_error(Missions::ExpressionError, /Failed to evaluate/)
    end
  end

  describe "#evaluate" do
    it "returns nil when the calculator raises Dentaku::Error" do
      allow(ctx.calculator).to receive(:evaluate).and_raise(Dentaku::Error, "eval error")

      expect(ctx.evaluate("some_expr")).to be_nil
    end

    it "evaluates qualified node variables without persisting flat aliases" do
      ctx.set_node_variables("summarizer", { "response" => "hello" })

      expect(ctx.evaluate("summarizer.response")).to eq("hello")
      expect(ctx.variables).not_to have_key("summarizer__response")
    end

    it "evaluates dot-syntax expressions after translation" do
      ctx.set_node_variables("counter", { "value" => 5 })

      expect(ctx.evaluate("counter.value + 10")).to eq(15)
    end

    it "supports direct string comparison against node-scoped variables" do
      ctx.set_node_variables("llm", { "response" => "true" })

      expect(ctx.evaluate("llm.response == 'true'"))
        .to be(true)
    end

    it "supports direct JSON string access with DIG" do
      ctx.set_node_variables("http_request", { "response_body" => '{"status":"ok"}' })

      expect(ctx.evaluate("DIG(http_request.response_body, 'status') == 'ok'"))
        .to be(true)
    end

    it "supports CONCAT for string assembly with node-scoped variables" do
      ctx.set_node_variables("sum_top_two", { "result" => 16 })
      ctx.set_node_variables("count_matches", { "result" => 4 })

      expression = <<~FORMULA.squish
        CONCAT('top_two_sum=', STR(sum_top_two.result), ', match_count=', STR(count_matches.result))
      FORMULA

      expect(ctx.evaluate(expression)).to eq("top_two_sum=16, match_count=4")
    end

    it "evaluates dot-syntax against hash-valued runtime helpers" do
      ctx.set_runtime_variable(
        "item",
        {
          "title" => "Detailed test payload",
          "meta" => { "score" => 0.9 },
        },
      )

      expect(ctx.evaluate("item.title == 'Detailed test payload'"))
        .to be(true)
      expect(ctx.evaluate("item.meta.score > 0.5"))
        .to be(true)
    end

    it "returns non-string expressions unchanged during backend translation" do
      expect(ctx.send(:dentaku_translate, 42)).to eq(42)
    end
  end

  describe "#set_node_variables / #get_variable (dot-syntax)" do
    it "stores and retrieves variables with dot-syntax" do
      ctx.set_node_variables("my_llm", { "response" => "output text" })

      expect(ctx.get_variable("my_llm.response")).to eq("output text")
    end

    it "does not expose node variables as flat double-underscore aliases" do
      ctx.set_node_variables("writer", { "response" => "draft" })

      expect(ctx.get_variable("writer__response")).to be_nil
      expect(ctx.variables).not_to have_key("writer__response")
    end

    it "normalizes node name and variable name" do
      ctx.set_node_variables("My LLM", { "Response" => "hello" })

      expect(ctx.get_variable("my_llm.response")).to eq("hello")
    end

    it "does not conflict with flat variables of the same name" do
      ctx.set_variable("response", "flat value")
      ctx.set_node_variables("writer", { "response" => "scoped value" })

      expect(ctx.get_variable("response")).to eq("flat value")
      expect(ctx.get_variable("writer.response")).to eq("scoped value")
    end
  end

  describe "#interpolate" do
    it "replaces {{node_name.variable_name}} with node-scoped values" do
      ctx.set_node_variables("summarizer", { "response" => "summary text" })

      expect(ctx.interpolate("Result: {{summarizer.response}}"))
        .to eq("Result: summary text")
    end

    it "preserves unresolved dot-syntax references" do
      expect(ctx.interpolate("{{unknown.var}}"))
        .to eq("{{unknown.var}}")
    end

    it "returns the value unchanged when template is not a String" do
      expect(ctx.interpolate(42)).to eq(42)
      expect(ctx.interpolate(nil)).to be_nil
      expect(ctx.interpolate([:a, :b])).to eq([:a, :b])
    end

    it "replaces simple {{variable}} references" do
      ctx.set_variable("name", "world")

      expect(ctx.interpolate("Hello {{name}}"))
        .to eq("Hello world")
    end

    it "serializes hash values as JSON" do
      ctx.set_variable("data", { "a" => 1, "b" => "two" })

      result = ctx.interpolate("Result: {{data}}")

      expect(result).to include('"a":1')
      expect(result).to include('"b":"two"')
    end

    it "serializes array values as JSON" do
      ctx.set_variable("items", [1, 2, 3])

      expect(ctx.interpolate("List: {{items}}"))
        .to eq("List: [1,2,3]")
    end

    it "injects boolean-like string values as raw formula text" do
      ctx.set_node_variables("llm", { "response" => "true" })

      interpolated = ctx.interpolate("{{llm.response}} == 'true'")

      expect(interpolated).to eq("true == 'true'")
      expect(ctx.evaluate(interpolated)).to be(false)
    end

    it "injects JSON string values as raw text that DIG cannot parse safely" do
      ctx.set_node_variables("http_request", { "response_body" => '{"status":"ok"}' })

      interpolated = ctx.interpolate("DIG({{http_request.response_body}}, 'status') == 'ok'")

      expect(interpolated).to eq(%q(DIG({"status":"ok"}, 'status') == 'ok'))
      expect(ctx.evaluate(interpolated)).to be_nil
    end
  end

  describe "custom formula helpers" do
    it "converts numeric values to strings with STR" do
      expect(ctx.evaluate("STR(42)")).to eq("42")
    end

    it "accepts LENGTH as a compatibility alias for LEN" do
      expect(ctx.evaluate("LENGTH('hello')")).to eq(5)
      expect(ctx.evaluate("LENGTH(42)")).to eq(2)
    end

    it "converts booleans to strings with STR" do
      expect(ctx.evaluate("STR(true)")).to eq("true")
    end

    it "digs into a JSON object by string keys" do
      ctx.set_variable("data", '{"user":{"name":"Alice"}}')

      expect(ctx.evaluate("DIG(data, 'user', 'name')")).to eq("Alice")
    end

    it "digs into a JSON array by integer index" do
      ctx.set_variable("data", '{"items":["a","b","c"]}')

      expect(ctx.evaluate("DIG(data, 'items', 1)")).to eq("b")
    end

    it "digs into nested structures" do
      ctx.set_variable("data", '{"a":{"b":[10,20,30]}}')

      expect(ctx.evaluate("DIG(data, 'a', 'b', 2)")).to eq(30)
    end

    it "returns nil for missing DIG keys" do
      ctx.set_variable("data", '{"a":1}')

      expect(ctx.evaluate("DIG(data, 'missing')")).to be_nil
    end
  end

  describe "#store_node_output" do
    it "stores expression-compatible output only in node_outputs" do
      ctx.store_node_output("node1", "text output")

      expect(ctx.get_node_output("node1")).to eq("text output")
      expect(ctx.get_variable("node_node1_output")).to be_nil
      expect(ctx.variables).not_to have_key("node_node1_output")
    end

    it "stores non-expression-compatible output without synthesizing a shared variable" do
      hash_output = { "key" => "value" }

      ctx.store_node_output("node2", hash_output)

      expect(ctx.get_node_output("node2")).to eq(hash_output)
      expect(ctx.get_variable("node_node2_output")).to be_nil
      expect(ctx.variables).not_to have_key("node_node2_output")
    end
  end

  describe "#get_node_output" do
    it "returns nil for an unknown node id" do
      expect(ctx.get_node_output("nonexistent")).to be_nil
    end
  end

  describe "loop runtime helpers" do
    it "clears the active loop scalar when no node id is provided" do
      ctx.set_runtime_variable("_loop_iteration", 4)

      ctx.clear_loop_iteration(nil)

      expect(ctx.get_variable("_loop_iteration")).to be_nil
    end
  end

  describe "#to_h" do
    it "serializes nil started_at and finished_at as nil in the execution log" do
      exec = Missions::NodeExecution.new(
        node_id: "n1",
        node_type: "output",
        status: :success,
        output: "hi",
        next_port: "default",
        started_at: nil,
        finished_at: nil,
        error: nil,
      )
      ctx.log_execution(exec)

      log_entry = ctx.to_h.fetch("execution_log").first

      expect(log_entry["started_at"]).to be_nil
      expect(log_entry["finished_at"]).to be_nil
    end

    it "includes node_variables in serialized state" do
      ctx.set_node_variables("writer", { "response" => "draft" })

      expect(ctx.to_h["node_variables"])
        .to eq({ "writer" => { "response" => "draft" } })
    end

    it "includes scheduler frontiers and execution count in serialized state" do
      ctx.sync_scheduler_frontier(
        "frontier-1",
        ready_items: [{ "node_id" => "n1", "incoming_edge_id" => "e1", "runtime_state" => { "item" => 1 } }],
        active_item: { "node_id" => "n2", "incoming_edge_id" => "e2", "runtime_state" => { "item" => 2 } },
      )
      ctx.execution_count_value = 7

      expect(ctx.to_h["scheduler_frontiers"]).to eq(
        {
          "frontier-1" => {
            "ready" => [{ "node_id" => "n1", "incoming_edge_id" => "e1", "runtime_state" => { "item" => 1 } }],
            "active" => { "node_id" => "n2", "incoming_edge_id" => "e2", "runtime_state" => { "item" => 2 } },
          },
        },
      )
      expect(ctx.to_h["execution_count"]).to eq(7)
    end

    it "serializes frontier items from symbol keys and missing optional fields" do
      ctx.sync_scheduler_frontier(
        "frontier-1",
        ready_items: [{ node_id: :n1, runtime_state: { item: 1 } }],
      )

      expect(ctx.to_h.dig("scheduler_frontiers", "frontier-1", "ready")).to eq(
        [{ "node_id" => "n1", "incoming_edge_id" => nil, "runtime_state" => { "item" => 1 } }],
      )
    end

    it "serializes frontier items that expose hash access without to_h" do
      data = { node_id: :n1, runtime_state: { item: 1 } }
      frontier_item = Object.new
      frontier_item.define_singleton_method(:key?) { |key| data.key?(key) }
      frontier_item.define_singleton_method(:[]) { |key| data[key] }

      ctx.sync_scheduler_frontier("frontier-1", ready_items: [frontier_item])

      expect(ctx.to_h.dig("scheduler_frontiers", "frontier-1", "ready")).to eq(
        [{ "node_id" => "n1", "incoming_edge_id" => nil, "runtime_state" => { "item" => 1 } }],
      )
    end
  end

  describe ".restore" do
    let(:nil_field_state) do
      {
        "variables" => {},
        "node_outputs" => {},
        "execution_log" => [
          {
            "node_id" => "n1",
            "node_type" => "set_variable",
            "status" => nil,
            "output" => "v",
            "next_port" => "default",
            "started_at" => nil,
            "finished_at" => nil,
            "error" => nil,
          },
        ],
      }
    end

    it "handles nil status, started_at, and finished_at in execution log entries" do
      restored = described_class.restore(mission_run: run, state: nil_field_state)
      log = restored.execution_log.first

      expect(restored.execution_log.size).to eq(1)
      expect(log.status).to be_nil
      expect(log.started_at).to be_nil
      expect(log.finished_at).to be_nil
    end

    it "restores node_variables and makes them accessible via dot-syntax" do
      state = {
        "variables" => {},
        "node_variables" => { "writer" => { "response" => "saved" } },
        "node_outputs" => {},
        "execution_log" => [],
      }

      restored = described_class.restore(mission_run: run, state:)

      expect(restored.get_variable("writer.response")).to eq("saved")
    end

    it "round-trips variables and node variables from serialized state" do
      ctx.set_variable("x", 42)
      ctx.set_node_variables("writer", { "response" => "draft" })

      restored = described_class.restore(mission_run: run, state: ctx.to_h)

      expect(restored.get_variable("x")).to eq(42)
      expect(restored.get_variable("writer.response")).to eq("draft")
    end

    it "round-trips scheduler frontiers and execution count from serialized state" do
      ctx.sync_scheduler_frontier(
        "frontier-1",
        ready_items: [{ "node_id" => "n1", "incoming_edge_id" => "e1", "runtime_state" => { "item" => 1 } }],
        active_item: { "node_id" => "n2", "incoming_edge_id" => "e2", "runtime_state" => { "item" => 2 } },
      )
      ctx.execution_count_value = 9

      restored = described_class.restore(mission_run: run, state: ctx.to_h)

      expect(restored.scheduler_frontiers).to eq(
        {
          "frontier-1" => {
            "ready" => [{ "node_id" => "n1", "incoming_edge_id" => "e1", "runtime_state" => { "item" => 1 } }],
            "active" => { "node_id" => "n2", "incoming_edge_id" => "e2", "runtime_state" => { "item" => 2 } },
          },
        },
      )
      expect(restored.execution_count_value).to eq(9)
    end

    it "round-trips runtime node states from serialized state" do
      ctx.set_node_state("branch_a", :disabled, node_type: "set_variable")

      restored = described_class.restore(mission_run: run, state: ctx.to_h)

      expect(restored.get_node_state("branch_a"))
        .to eq({ "status" => "disabled", "node_type" => "set_variable" })
    end
  end

  describe ".json_dig" do
    it "handles string JSON input" do
      expect(described_class.json_dig('{"a":1}', "a")).to eq(1)
    end

    it "handles non-string input by serializing to JSON" do
      expect(described_class.json_dig({ "a" => 1 }, "a")).to eq(1)
    end

    it "returns nil for invalid JSON" do
      expect(described_class.json_dig("not json", "a")).to be_nil
    end

    it "uses integer indices for arrays" do
      expect(described_class.json_dig("[10,20,30]", 1)).to eq(20)
    end
  end

  describe "#merge_variables" do
    it "merges a hash of variables" do
      ctx.merge_variables("a" => 1, "b" => 2)

      expect(ctx.get_variable("a")).to eq(1)
      expect(ctx.get_variable("b")).to eq(2)
    end
  end

  describe "#variables" do
    it "returns a copy of the persisted variable set" do
      ctx.set_variable("x", 1)

      variables = ctx.variables
      variables["x"] = 99

      expect(ctx.get_variable("x")).to eq(1)
    end
  end

  describe "concurrent access" do
    it "handles concurrent set_variable calls without errors" do
      Async do
        Array.new(10) do |i|
          Async { ctx.set_variable("var_#{i}", i) }
        end.each(&:wait)
      end

      10.times do |i|
        expect(ctx.get_variable("var_#{i}")).to eq(i)
      end
    end

    it "handles concurrent store_node_output calls without errors" do
      Async do
        Array.new(10) do |i|
          Async { ctx.store_node_output("node_#{i}", "output_#{i}") }
        end.each(&:wait)
      end

      10.times do |i|
        expect(ctx.get_node_output("node_#{i}")).to eq("output_#{i}")
      end
    end
  end

  describe "runtime helper variables" do
    it "can persist a runtime helper into persisted variables" do
      ctx.set_runtime_variable("item", "apple", persist: true)

      expect(ctx.get_variable("item")).to eq("apple")
      expect(ctx.variables["item"]).to eq("apple")
    end

    it "shadows persisted helper values within the current branch only" do
      ctx.set_variable("total", 99)
      ctx.set_runtime_variable("total", 3)

      expect(ctx.get_variable("total")).to eq(3)
      expect(ctx.variables["total"]).to eq(99)
    end

    it "keeps branch-local helpers out of persisted variables" do
      ctx.set_runtime_variable("item", "apple")
      ctx.current_input = "done"

      expect(ctx.current_input).to eq("done")
      expect(ctx.variables).not_to have_key("item")
      expect(ctx.variables).not_to have_key("_current_input_payload")
      expect(ctx.to_h.fetch("variables", {})).not_to have_key("item")
      expect(ctx.to_h.fetch("variables", {})).not_to have_key("_current_input_payload")
    end

    it "can clear the current branch input" do
      ctx.current_input = "done"

      ctx.clear_current_input

      expect(ctx.current_input_present?).to be(false)
      expect(ctx.current_input).to be_nil
    end

    it "does not expose current input through exported or expression runtime variables" do
      ctx.current_input = "done"
      ctx.set_runtime_variable("item", "apple")

      expect(ctx.send(:exported_runtime_variables)).to eq({})
      expect(ctx.send(:runtime_expression_variables)).to eq({ "item" => "apple" })
    end

    it "can inherit nil runtime state outside async tasks" do
      ctx.inherit_runtime_state(nil)

      expect(ctx.snapshot_runtime_state).to eq({})
    end

    it "clears runtime state outside async tasks" do
      ctx.set_runtime_variable("item", "apple")

      ctx.clear_runtime_state_for_current_task

      expect(ctx.snapshot_runtime_state).to eq({})
    end

    it "clears async runtime state even when no task store exists yet" do
      Async do
        ctx.clear_runtime_state_for_current_task

        expect(ctx.snapshot_runtime_state).to eq({})
      end.wait
    end
  end
end
