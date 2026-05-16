# frozen_string_literal: true

require "rails_helper"
require "support/mission_flow_builder"

RSpec.describe Missions::Runner do
  describe "workflow contract" do
    it "executes a kitchen-sink workflow end to end" do
      nested_mission = create(:mission, name: "Nested Enrichment", flow_data: build_nested_sub_mission_flow)
      mission = create(:mission, flow_data: build_kitchen_sink_flow(nested_mission))

      run = described_class.new(mission).execute(variables: { "input" => "start" })
      nested_run = MissionRun.where(mission: nested_mission).order(created_at: :desc).first

      expect_outer_contract(run)
      expect_nested_contract(nested_run)
    end

    def build_kitchen_sink_flow(nested_mission)
      MissionFlowBuilder.build do |flow_builder|
        build_outer_nodes(flow_builder, nested_mission)
        build_outer_edges(flow_builder)
      end
    end

    def build_outer_nodes(flow_builder, nested_mission)
      build_outer_entry_nodes(flow_builder)
      build_data_branch_nodes(flow_builder)
      build_nested_branch_nodes(flow_builder, nested_mission)
      build_outer_exit_nodes(flow_builder)
    end

    def build_outer_entry_nodes(flow_builder)
      add_node_specs(
        flow_builder,
        [
          ["input", { type: "input", name: "input" }],
          ["seed", { type: "set_variable", name: "seed_state", assignments: outer_seed_assignments }],
          ["gate", { type: "condition", name: "entry_gate", expression: "routing_enabled = 1" }],
          [
            "router",
            { type: "switch", name: "route_by_tier", expression: "tier", cases: { "premium" => "premium" } },
          ],
          ["fanout", { type: "set_variable", name: "fanout_seed", assignments: { "fanout_started" => "true" } }],
        ],
      )
    end

    def build_data_branch_nodes(flow_builder) # rubocop:disable Metrics/MethodLength
      add_node_specs(
        flow_builder,
        [
          ["dedupe", { type: "unique", name: "remove_duplicates", collection: "numbers" }],
          [
            "filter",
            {
              type: "filter",
              name: "keep_large_numbers",
              collection: "remove_duplicates.unique",
              expression: "item >= 2",
            },
          ],
          [
            "sort",
            { type: "sort", name: "sort_descending", collection: "keep_large_numbers.matches", direction: "desc" },
          ],
          [
            "limit",
            { type: "limit", name: "take_window", collection: "sort_descending.sorted", count: "3", offset: "1" },
          ],
          ["iter", { type: "iterator", name: "numbers_iter", collection: "take_window.items" }],
          [
            "iter_body",
            {
              type: "set_variable",
              name: "capture_weighted_value",
              assignments: { "outer_item" => "item", "weighted_value" => "item * 2 + index" },
            },
          ],
          [
            "sum",
            {
              type: "aggregate",
              name: "sum_weighted",
              collection: "numbers_iter.results",
              operation: "sum",
              field: "weighted_value",
            },
          ],
          [
            "hot",
            {
              type: "set_variable",
              name: "hot_label",
              assignments: {
                "final_data_score" => "sum_weighted.result",
                "final_data_label" => "hot",
                "branch_a_ready" => "true",
              },
            },
          ],
        ],
      )
    end

    def build_nested_branch_nodes(flow_builder, nested_mission) # rubocop:disable Metrics/MethodLength
      add_node_specs(
        flow_builder,
        [
          ["loop", { type: "loop", name: "retry_loop", condition: "attempts < 3", max_iterations: "5" }],
          [
            "loop_body",
            { type: "set_variable", name: "increment_attempts", assignments: { "attempts" => "attempts + 1" } },
          ],
          [
            "sub",
            {
              type: "mission",
              name: "nested_enrichment",
              mission_id: nested_mission.id.to_s,
              input_variables: { "nested_matrix" => "{{matrix_payload}}", "nested_bonus" => "{{attempts}}" },
            },
          ],
          [
            "branch_b_complete",
            { type: "set_variable", name: "branch_b_complete", assignments: { "branch_b_ready" => "true" } },
          ],
        ],
      )
    end

    def build_outer_exit_nodes(flow_builder) # rubocop:disable Metrics/MethodLength
      add_node_specs(
        flow_builder,
        [
          [
            "rollup",
            {
              type: "set_variable",
              name: "final_rollup",
              assignments: {
                "final_score" => "final_data_score + final_nested_total + attempts",
                "final_signature" => "{{final_data_label}}-{{final_nested_label}}",
              },
            },
          ],
          [
            "payload",
            {
              type: "text_template",
              name: "result_payload",
              template: %({"score": {{final_score}}, "signature": "{{final_signature}}", "rows": {{nested_row_count}}}),
            },
          ],
          [
            "extract",
            {
              type: "json_extract",
              name: "summary_extract",
              source: "{{result_payload.text}}",
              extractions: { "score_value" => "score", "signature_value" => "signature", "rows_value" => "rows" },
            },
          ],
          ["output", { type: "output", name: "output", selected_variables: outer_selected_variables }],
        ],
      )
    end

    def build_outer_edges(flow_builder)
      flow_builder.edge("input", "seed")
      flow_builder.edge("seed", "gate")
      flow_builder.edge("gate", "router", source_handle: "true")
      flow_builder.edge("router", "fanout", source_handle: "premium")
      flow_builder.edge("fanout", "dedupe")
      flow_builder.edge("dedupe", "filter")
      flow_builder.edge("filter", "sort", source_handle: "match")
      flow_builder.edge("sort", "limit")
      flow_builder.edge("limit", "iter")
      flow_builder.edge("iter", "iter_body", source_handle: "loop")
      flow_builder.edge("iter", "sum", source_handle: "done")
      flow_builder.edge("sum", "hot")
      flow_builder.edge("hot", "loop")
      flow_builder.edge("loop", "loop_body", source_handle: "loop")
      flow_builder.edge("loop", "sub", source_handle: "done")
      flow_builder.edge("sub", "branch_b_complete")
      flow_builder.edge("branch_b_complete", "rollup")
      flow_builder.edge("rollup", "payload")
      flow_builder.edge("payload", "extract")
      flow_builder.edge("extract", "output")
    end

    def build_nested_sub_mission_flow
      MissionFlowBuilder.build do |flow_builder|
        build_nested_sub_mission_nodes(flow_builder)
        build_nested_sub_mission_edges(flow_builder)
      end
    end

    def build_nested_sub_mission_nodes(flow_builder) # rubocop:disable Metrics/MethodLength
      add_node_specs(
        flow_builder,
        [
          ["input", { type: "input", name: "nested_input", fields: nested_input_fields }],
          ["rows_iter", { type: "iterator", name: "rows_iter", collection: "nested_matrix" }],
          [
            "row_context",
            {
              type: "set_variable",
              name: "capture_row_context",
              assignments: { "nested_row_index" => "index", "nested_row_payload" => "{{item}}" },
            },
          ],
          ["cells_iter", { type: "iterator", name: "cells_iter", collection: "nested_row_payload" }],
          [
            "cell_value",
            {
              type: "set_variable",
              name: "capture_weighted_cell",
              assignments: { "nested_weighted_cell" => "{{item}}" },
            },
          ],
          [
            "sum_row",
            {
              type: "aggregate",
              name: "sum_row_weights",
              collection: "cells_iter.results",
              operation: "sum",
              field: "nested_weighted_cell",
            },
          ],
          [
            "row_finalizer",
            {
              type: "set_variable",
              name: "row_finalizer",
              assignments: { "nested_row_total" => "sum_row_weights.result" },
            },
          ],
          [
            "sum_rows",
            {
              type: "aggregate",
              name: "sum_rows",
              collection: "rows_iter.results",
              operation: "sum",
              field: "nested_row_total",
            },
          ],
          ["label_gate", { type: "condition", name: "nested_total_gate", expression: "sum_rows.result > 20" }],
          [
            "dense",
            {
              type: "set_variable",
              name: "dense_label",
              assignments: {
                "final_nested_total" => "sum_rows.result + nested_bonus",
                "final_nested_label" => "dense",
                "nested_row_count" => "sum_rows.count",
                "nested_finalize_ready" => "true",
              },
            },
          ],
          ["output", { type: "output", name: "output", selected_variables: nested_selected_variables }],
        ],
      )
    end

    def build_nested_sub_mission_edges(flow_builder)
      flow_builder.edge("input", "rows_iter")
      flow_builder.edge("rows_iter", "row_context", source_handle: "loop")
      flow_builder.edge("row_context", "cells_iter")
      flow_builder.edge("cells_iter", "cell_value", source_handle: "loop")
      flow_builder.edge("cells_iter", "sum_row", source_handle: "done")
      flow_builder.edge("sum_row", "row_finalizer")
      flow_builder.edge("rows_iter", "sum_rows", source_handle: "done")
      flow_builder.edge("sum_rows", "label_gate")
      flow_builder.edge("label_gate", "dense", source_handle: "true")
      flow_builder.edge("dense", "output")
    end

    def expect_outer_contract(run) # rubocop:disable Metrics/MethodLength
      expect(run).to be_completed
      expect(run.variables).to include(
        "fanout_started" => true,
        "branch_a_ready" => true,
        "branch_b_ready" => true,
        "attempts" => 3,
        "final_data_score" => 23,
        "final_data_label" => "hot",
        "final_nested_total" => "27.0",
        "final_nested_label" => "dense",
        "nested_row_count" => 3,
        "final_score" => "53.0",
        "final_signature" => "hot-dense",
        "score_value" => 53.0,
        "signature_value" => "hot-dense",
        "rows_value" => 3,
      )
      expect_outer_node_variables(run)
      expect_outer_execution_counts(run)
      expect(run.node_executions.map(&:node_type)).to include(
        "condition", "switch", "unique", "filter", "sort", "limit", "iterator",
        "aggregate", "loop", "mission", "text_template", "json_extract", "output",
      )
    end

    def expect_outer_node_variables(run)
      expect(run.execution_state.dig("node_variables", "numbers_iter", "results")).to eq(
        [
          { "outer_item" => 5, "weighted_value" => 10 },
          { "outer_item" => 3, "weighted_value" => 7 },
          { "outer_item" => 2, "weighted_value" => 6 },
        ],
      )
      expect(run.execution_state.dig("node_variables", "sum_weighted", "result")).to eq(23)
      expect(run.execution_state.dig("node_variables", "result_payload", "text")).to eq(
        '{"score": 53.0, "signature": "hot-dense", "rows": 3}',
      )
    end

    def expect_outer_execution_counts(run)
      expect(run.node_executions.count { |execution| execution.node_id == "iter_body" }).to eq(3)
      expect(run.node_executions.count { |execution| execution.node_id == "loop_body" }).to eq(3)
      expect(run.node_executions.count { |execution| execution.node_id == "rollup" }).to eq(1)
    end

    def expect_nested_contract(run)
      expect(run).to be_present
      expect(run).to be_completed
      expect(run.variables).to include(
        "final_nested_total" => "27.0",
        "final_nested_label" => "dense",
        "nested_row_count" => 3,
        "nested_finalize_ready" => true,
      )
      expect_nested_node_variables(run)
      expect_nested_execution_counts(run)
    end

    def expect_nested_node_variables(run)
      expect(run.execution_state.dig("node_variables", "rows_iter", "results")).to eq(
        [
          { "nested_row_total" => 8 },
          { "nested_row_total" => 10 },
          { "nested_row_total" => 6 },
        ],
      )
      expect(run.execution_state.dig("node_variables", "sum_rows", "result")).to eq(24)
    end

    def expect_nested_execution_counts(run)
      expect(run.node_executions.count { |execution| execution.node_id == "row_context" }).to eq(3)
      expect(run.node_executions.count { |execution| execution.node_id == "cell_value" }).to eq(6)
      expect(run.node_executions.count { |execution| execution.node_id == "rows_iter" }).to eq(2)
    end

    def outer_seed_assignments
      {
        "routing_enabled" => "1",
        "tier" => "premium",
        "numbers" => "[5,3,8,3,2,8,1]",
        "attempts" => "0",
        "matrix_payload" => "[[5,3],[8,2],[1,5]]",
      }
    end

    def outer_selected_variables
      [
        "fanout_started",
        "branch_a_ready",
        "branch_b_ready",
        "attempts",
        "final_data_score",
        "final_data_label",
        "final_nested_total",
        "final_nested_label",
        "nested_row_count",
        "final_score",
        "final_signature",
        "score_value",
        "signature_value",
        "rows_value",
      ]
    end

    def nested_input_fields
      [
        { "variable_name" => "nested_matrix", "field_type" => "json", "required" => true },
        { "variable_name" => "nested_bonus", "field_type" => "number", "required" => true },
      ]
    end

    def nested_selected_variables
      ["final_nested_total", "final_nested_label", "nested_row_count", "nested_finalize_ready"]
    end

    def add_node_specs(flow_builder, specs)
      specs.each do |id, config|
        flow_builder.node(id, **config)
      end
    end
  end
end
