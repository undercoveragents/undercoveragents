# frozen_string_literal: true

module TestSuites
  module AgentAlphaFixtureFlowData
    private

    def benchmark_flow_data
      {
        "nodes" => [benchmark_input_node, benchmark_output_node],
        "edges" => [benchmark_input_output_edge],
      }
    end

    def benchmark_input_node
      {
        "id" => "input_1",
        "type" => "input",
        "position" => { "x" => 0, "y" => 100 },
        "data" => {
          "label" => "Input",
          "icon" => "fa-solid fa-right-to-bracket",
          "color" => "#0891b2",
          "fields" => [
            { "variable_name" => "ticket_text", "field_type" => "string", "required" => true },
            { "variable_name" => "customer_email", "field_type" => "string", "required" => false },
          ],
        },
      }
    end

    def benchmark_output_node
      {
        "id" => "output_1",
        "type" => "output",
        "position" => { "x" => 220, "y" => 100 },
        "data" => {
          "label" => "Output",
          "icon" => "fa-solid fa-flag-checkered",
          "color" => "#16a34a",
          "status" => "completed",
          "selected_variables" => ["ticket_text"],
        },
      }
    end

    def benchmark_input_output_edge
      {
        "id" => "e-input-output",
        "source" => "input_1",
        "target" => "output_1",
      }
    end
  end
end
