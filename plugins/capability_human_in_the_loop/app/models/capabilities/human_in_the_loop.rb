# frozen_string_literal: true

module Capabilities
  class HumanInTheLoop
    include UndercoverAgents::PluginSystem::Configurator
    include CapabilityPlugin

    PLUGIN_ROOT = Pathname.new(__dir__).join("..", "..", "..").expand_path.freeze
    VIEW_PATH = PLUGIN_ROOT.join("app/views").to_s.freeze
    TOOL_RUNTIME_NAME = "ask_user_questions"
    TOOL_DISPLAY_NAME = "Ask User Questions"
    TOOL_ICON = "fa-solid fa-circle-question"

    DEFAULT_MAX_QUESTIONS_PER_CALL = 3
    DEFAULT_MAX_OPTIONS_PER_QUESTION = 6
    ABSOLUTE_MAX_QUESTIONS_PER_CALL = 6
    ABSOLUTE_MAX_OPTIONS_PER_QUESTION = 8

    attribute :max_questions_per_call, :integer, default: DEFAULT_MAX_QUESTIONS_PER_CALL
    attribute :max_options_per_question, :integer, default: DEFAULT_MAX_OPTIONS_PER_QUESTION

    key "human_in_the_loop"
    label "Human in the Loop"
    icon "fa-solid fa-circle-question"
    description "Lets an agent ask focused clarification questions in-chat, " \
                "wait for the user's answers, and resume automatically."

    validates :max_questions_per_call,
              numericality: {
                only_integer: true,
                greater_than: 0,
                less_than_or_equal_to: ABSOLUTE_MAX_QUESTIONS_PER_CALL,
              }
    validates :max_options_per_question,
              numericality: {
                only_integer: true,
                greater_than: 0,
                less_than_or_equal_to: ABSOLUTE_MAX_OPTIONS_PER_QUESTION,
              }

    def self.view_path = VIEW_PATH

    def self.permitted_params(raw)
      raw.permit(:max_questions_per_call, :max_options_per_question)
    end

    def self.agent_designer_fields
      [
        {
          name: "max_questions_per_call",
          type: "integer",
          default: DEFAULT_MAX_QUESTIONS_PER_CALL,
          description: "Maximum number of clarification questions in one tool call.",
        },
        {
          name: "max_options_per_question",
          type: "integer",
          default: DEFAULT_MAX_OPTIONS_PER_QUESTION,
          description: "Maximum number of suggested options per clarification question.",
        },
      ]
    end

    def tools_for(agent:, parent_chat: nil)
      return [] if parent_chat&.user.blank?

      [Capabilities::HumanInTheLoop::AskUserQuestionsTool.for_agent(agent, chat: parent_chat, capability: self)]
    end

    def system_prompt_addition_for(agent:, user: nil)
      return nil unless agent && user

      <<~TEXT
        <human_in_the_loop>
        You can ask the user focused clarification questions with the `ask_user_questions` tool.
        Use it only when the missing information blocks a correct answer, approval, or next step.
        Ask all required clarifications in one call when possible.
        Each tool call may include up to #{max_questions_per_call} questions, and each question may include up to #{max_options_per_question} answer options.
        Pass `questions` as an array of objects with `prompt` and `options`, for example `{ prompt: "What should I look up?", options: ["Customers", "Invoices"] }`.
        Do not collapse the question text and options into a single prose string.
        If you can think of more than #{max_options_per_question} options, keep only the best #{max_options_per_question}; the widget already provides a custom answer field for anything else.
        The widget always gives the user a custom answer field in addition to the listed options.
        When the user answers the widget, you will receive a normal user message that starts with `Clarification answers:`. Treat that message as the tool's returned answers.
        If those answers still leave a blocking ambiguity, call `ask_user_questions` again instead of asking a plain-text follow-up question.
        Never ask a blocking clarification in plain assistant text while this tool is available.
        After calling the tool, stop and wait for the user's next message with their answers before continuing.
        </human_in_the_loop>
      TEXT
    end

    def summary
      "#{max_questions_per_call} questions max · #{max_options_per_question} options/question"
    end
  end
end
