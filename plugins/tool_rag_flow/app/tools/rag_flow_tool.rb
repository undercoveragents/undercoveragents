# frozen_string_literal: true

# RubyLLM tool that performs RAG queries against the vector store
# managed by an RagFlow.
#
# Unlike RagQueryTool (which requires manual table/field configuration),
# this tool extracts all connection and schema information from the
# linked RagFlow's storage and embedding steps.
#
# Usage:
#   tool_record = Tool.rag_flows.enabled.find(id)
#   tool = RagFlowTool.for_tool(tool_record)
#   chat.with_tool(tool)
#   chat.ask("Find documents about machine learning")
#
class RagFlowTool < RubyLLM::Tool
  include RagToolBehavior

  def self.for_tool(tool_record)
    raise ArgumentError, "Expected a RAG tool" unless tool_record.toolable.is_a?(Tools::RagFlow)

    new(tool_record)
  end

  def initialize(tool_record)
    super()
    @tool_record = tool_record
  end

  private

  def tool_name_prefix
    "rag_flow"
  end
end
