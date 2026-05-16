# frozen_string_literal: true

FactoryBot.define do
  factory :capabilities_human_in_the_loop_standalone, class: "Capabilities::HumanInTheLoop" do
    max_questions_per_call { 3 }
    max_options_per_question { 6 }
  end
end
