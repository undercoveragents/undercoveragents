# frozen_string_literal: true

module Missions
  module Nodes
    # Node: Code — executes sandboxed Ruby when built-in nodes cannot express the logic.
    class Code
      include MissionNodePlugin

      DESIGNER_INSTRUCTIONS = <<~'INSTRUCTIONS'.strip.freeze
        ## Code (type: "code")
        Last-resort node. Executes a sandboxed Ruby code snippet. 10-second timeout.

        Do not use `code` for plain JSON parsing/extraction (`json_extract`), string composition
        (`text_template`), scalar formulas or renames (`set_variable`), or basic collection
        transforms already covered by `filter`, `aggregate`, `sort`, `unique`, or `limit`.

        ### Configuration
        ```json
        {
          "code": "items = var('items')\nitems.select { |i| i['score'] > 0.5 }",
          "output_variables": [
            {"name": "filtered_count", "description": "Number of filtered items"}
          ]
        }
        ```
        - `code` (required): Ruby code to execute. The return value of the last expression becomes the `result` output.
        - `output_variables` (optional): Array of output variable definitions. Each entry has:
          - `name` (required): Variable name (lowercase, underscores)
          - `description` (optional): Human-readable description
          The code must call `set("name", value)` for each declared output variable.

        ### Accessing Variables
        Use `var("variable_name")` to read upstream variables. Example:
        ```ruby
        name = var("user_name")
        count = var("item_count").to_i
        "Hello #{name}, you have #{count} items"
        ```

        ### Setting Output Variables
        Use `set("name", value)` to define output variables. Example:
        ```ruby
        items = var("items")
        filtered = items.select { |i| i["score"] > 0.5 }
        set("filtered_count", filtered.size)
        set("high_scores", filtered)
        filtered
        ```

        Design-time tools only discover custom code outputs that are declared in
        `output_variables`. If the code calls `set("name", value)` for a downstream-facing
        output, add the same `name` to `output_variables` too.

        Scoped upstream variables can be read with dot syntax exactly as listed by
        `list_node_variables`, for example `var("writer.response")`.

        ### Sandbox Restrictions
        Prohibited: File, IO, Dir, system, exec, eval, require, send, Thread, Process, Socket.
        Only safe Ruby operations are allowed (string manipulation, math, array/hash ops).

        ### Output Ports
        - `default`: Output

        ### Output Variables
        - `result` (any): Return value of the code (last expression)
        - Plus any variables defined via `output_variables` config and set via `set()` in the code.

        ### Writing Code
        When asked to write or modify code for a code node, write the Ruby yourself only after
        confirming a dedicated node cannot express the behavior.
        Use exact upstream variable names, keep `output_variables` aligned with every
        downstream-facing `set()` call, respect the sandbox restrictions above, and apply the
        final code with `apply_flow_patch` (`update_nodes`).
      INSTRUCTIONS

      class << self
        def node_type = "code"
        def node_label = "Code"
        def node_icon = "fa-solid fa-code"
        def node_color = "#ea580c"
        def node_category = :node
        def node_description = "Last-resort custom Ruby when built-in nodes cannot express the logic"

        def field_contracts
          [
            field_contract(
              key: "code",
              value_type: :string,
              description: "Ruby code to execute",
              required: true,
            ),
            field_contract(
              key: "output_variables",
              value_type: :array,
              description: "Declared output variables the code may set",
            ),
          ]
        end

        def dynamic_output_variables(node_data)
          parse_output_variables(node_data["output_variables"]).filter_map do |output_variable|
            name = output_variable["name"].presence
            next unless name

            {
              name:,
              type: :any,
              description: output_variable["description"].presence || "Code output variable",
            }
          end
        end

        def extract_variables(data, label, variables, seen)
          parse_output_variables(data["output_variables"]).each do |ov|
            name = ov["name"]
            next if name.blank?

            MissionNodePlugin.add_variable(
              variables, seen, name, "code_output", label,
              ov["description"].presence || "Code output variable",
            )
          end
        end

        def variable_schema
          Missions::VariableSchema.new(
            outputs: [
              { name: "result", type: :any, description: "Return value of the code" },
              { name: "*", type: :any, description: "Dynamic — each defined output variable" },
            ],
          )
        end

        def designer_instructions = DESIGNER_INSTRUCTIONS

        private

        def parse_output_variables(output_variables)
          case output_variables
          when Array
            output_variables
          when String
            JSON.parse(output_variables)
          else
            []
          end
        rescue JSON::ParserError
          []
        end
      end

      register_node!

      EXECUTION_TIMEOUT = 10 # seconds
      PROHIBITED_CONSTANTS = [
        "File", "IO", "Dir", "FileUtils", "Kernel", "System", "Open3",
        "Pathname", "Process", "Socket", "TCPSocket", "TCPServer", "UDPSocket",
        "ObjectSpace", "GC", "Thread", "Fiber", "Ractor",
      ].freeze

      def output_ports = [{ key: "default", label: "Output" }]

      def execute(context)
        node_data = context.get_variable("_current_node_data") || {}
        code = node_data["code"].to_s

        return NodeResult.new(status: :failure, output: "No code provided") if code.blank?
        return NodeResult.new(status: :failure, output: "Code contains prohibited operations") if unsafe_code?(code)

        result, extra_vars = execute_sandboxed(context, code)
        NodeResult.new(status: :success, output: result.to_s, variables: extra_vars.merge("result" => result))
      rescue ScriptError, StandardError => e
        NodeResult.new(status: :failure, output: "Code execution error: #{e.message}")
      end

      private

      def unsafe_code?(code)
        PROHIBITED_CONSTANTS.any? { |c| code.match?(/\b#{c}\b/) } ||
          code.match?(
            /`|system\s*\(|exec\s*\(|%x|eval\s*\(|send\s*\(|__send__|public_send|
            require|load\s*\(|const_get|const_set|class_eval|module_eval|instance_eval\s*\(|
            define_method|remove_method|undef_method|method\s*\(|binding/x,
          )
      end

      def execute_sandboxed(context, code)
        sandbox = Sandbox.new(context)

        result = Timeout.timeout(EXECUTION_TIMEOUT) do
          sandbox.instance_eval(code, "(mission_code)", 1)
        end

        [result, sandbox.output_variables]
      end

      class Sandbox
        attr_reader :variables

        def initialize(context)
          @variables = {}
          @output_variables = {}
          populate_variables(context)
        end

        def var(name)
          key = name.to_s
          @variables[key] || @variables[qualified_key(key)] || @variables[normalize_key(key)]
        end

        def set(name, value)
          @output_variables[name.to_s] = value
          @variables[name.to_s] = value
        end

        def output_variables = @output_variables.dup

        private

        def qualified_key(name)
          return unless name.include?(".")

          node_name, variable_name = name.split(".", 2)
          "#{normalize_key(node_name)}.#{normalize_key(variable_name)}"
        end

        def normalize_key(name)
          name.to_s.downcase.gsub(/[^a-z0-9_]/, "_")
        end

        def populate_variables(context)
          context.variables.each do |key, value|
            next if key.start_with?("_")

            @variables[key] = value
          end

          context.node_variables.each do |node_name, values|
            values.each do |variable_name, value|
              @variables["#{node_name}.#{variable_name}"] = value
            end
          end
        end
      end
    end
  end
end
