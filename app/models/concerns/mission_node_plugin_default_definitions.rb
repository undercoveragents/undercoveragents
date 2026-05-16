# frozen_string_literal: true

module MissionNodePluginDefaultDefinitions
  ALL = [
    {
      key: "input", class_name: "Missions::Nodes::Input",
      label: "Input", icon: "fa-solid fa-right-to-bracket", color: "#10b981",
      category: :input_output, description: "Receives input fields from an API call", singleton: true,
    },
    {
      key: "output", class_name: "Missions::Nodes::Output",
      label: "Output", icon: "fa-solid fa-arrow-right-from-bracket", color: "#ec4899",
      category: :input_output, description: "Selects variables to output from the mission",
    },
    {
      key: "llm", class_name: "Missions::Nodes::Llm",
      label: "Generate Text", icon: "fa-solid fa-brain", color: "#6366f1",
      category: :llm, description: "Generates text using a language model",
    },
    {
      key: "agent", class_name: "Missions::Nodes::Agent",
      label: "Agent", icon: "fa-solid fa-user-secret", color: "#4f46e5",
      category: :llm, description: "Invokes an AI agent",
    },
    {
      key: "generate_image", class_name: "Missions::Nodes::GenerateImage",
      label: "Generate Image", icon: "fa-solid fa-image", color: "#a855f7",
      category: :llm, description: "Generates an image using an AI model",
    },
    {
      key: "mission", class_name: "Missions::Nodes::SubMission",
      label: "Mission", icon: "fa-solid fa-diagram-project", color: "#8b5cf6",
      category: :node, description: "Calls another mission as a sub-workflow",
    },
    {
      key: "condition", class_name: "Missions::Nodes::Condition",
      label: "Condition", icon: "fa-solid fa-code-branch", color: "#f97316",
      category: :control, description: "Branches flow based on a condition expression",
    },
    {
      key: "switch", class_name: "Missions::Nodes::Switch",
      label: "Switch", icon: "fa-solid fa-arrows-split-up-and-left", color: "#e11d48",
      category: :control, description: "Routes flow to different paths based on a value",
    },
    {
      key: "iterator", class_name: "Missions::Nodes::Iterator",
      label: "Iterator", icon: "fa-solid fa-repeat", color: "#0ea5e9",
      category: :control, description: "Iterates over a collection",
    },
    {
      key: "loop", class_name: "Missions::Nodes::Loop",
      label: "Loop", icon: "fa-solid fa-arrows-rotate", color: "#14b8a6",
      category: :control, description: "Repeats while a condition is met",
    },
    {
      key: "set_variable", class_name: "Missions::Nodes::SetVariable",
      label: "Set Variable", icon: "fa-solid fa-equals", color: "#84cc16",
      category: :control, description: "Sets variables for downstream nodes",
    },
    {
      key: "aggregate", class_name: "Missions::Nodes::Aggregate",
      label: "Aggregate", icon: "fa-solid fa-calculator", color: "#7c3aed",
      category: :control, description: "Reduces an array using an aggregation operation",
    },
    {
      key: "sort", class_name: "Missions::Nodes::Sort",
      label: "Sort", icon: "fa-solid fa-arrow-down-a-z", color: "#2563eb",
      category: :control, description: "Sorts an array",
    },
    {
      key: "unique", class_name: "Missions::Nodes::Unique",
      label: "Remove Duplicates", icon: "fa-solid fa-clone", color: "#0891b2",
      category: :control, description: "Removes duplicate items from an array",
    },
    {
      key: "limit", class_name: "Missions::Nodes::Limit",
      label: "Limit", icon: "fa-solid fa-scissors", color: "#ca8a04",
      category: :control, description: "Takes a subset of items from an array",
    },
    {
      key: "http_request", class_name: "Missions::Nodes::HttpRequest",
      label: "HTTP Request", icon: "fa-solid fa-globe", color: "#0284c7",
      category: :node, description: "Makes an HTTP request to an external API",
    },
    {
      key: "code", class_name: "Missions::Nodes::Code",
      label: "Code", icon: "fa-solid fa-code", color: "#ea580c",
      category: :node, description: "Last-resort custom Ruby when built-in nodes cannot express the logic",
    },
    {
      key: "text_template", class_name: "Missions::Nodes::TextTemplate",
      label: "Text Template", icon: "fa-solid fa-file-lines", color: "#7c3aed",
      category: :node, description: "Composes text using a template with variable interpolation",
    },
    {
      key: "json_extract", class_name: "Missions::Nodes::JsonExtract",
      label: "JSON Extract", icon: "fa-solid fa-file-code", color: "#059669",
      category: :node, description: "Parses JSON objects or arrays and extracts nested values by path",
    },
    {
      key: "delay", class_name: "Missions::Nodes::Delay",
      label: "Delay", icon: "fa-solid fa-clock", color: "#d97706",
      category: :control, description: "Pauses execution for a specified duration",
    },
    {
      key: "filter", class_name: "Missions::Nodes::Filter",
      label: "Filter", icon: "fa-solid fa-filter", color: "#0d9488",
      category: :control, description: "Filters array items based on an expression",
    },
    {
      key: "write_file", class_name: "Missions::Nodes::WriteFile",
      label: "Write File", icon: "fa-solid fa-file-export", color: "#0891b2",
      category: :node, description: "Writes content to a file",
    },
  ].freeze
end
