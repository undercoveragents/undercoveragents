# frozen_string_literal: true

# Builds a Tools::RagFlow JSONB configurator (ActiveModel, not AR).
# `create` also generates a backing Tool AR record with _tool_record set.
FactoryBot.define do
  factory :tools_rag_flow, class: "Tools::RagFlow" do
    skip_create

    transient do
      tool_name { Faker::Lorem.unique.words(number: 3).join(" ").titleize }
    end

    rag_flow factory: [:rag_flow, :with_steps]
    distance_method { "cosine" }
    max_distance { 0.8 }
    results_limit { 10 }
    custom_instructions { nil }

    initialize_with { new(attributes.except(:tool_name)) }

    after(:create) do |rag_flow_cfg, evaluator|
      tool = Tool.new(
        tool_type: "rag_flow",
        name: evaluator.tool_name,
        operation: OperationFactoryHelper.default_operation,
      )
      tool.configurator = rag_flow_cfg
      tool.save!
      rag_flow_cfg._tool_record = tool
    end
  end
end
