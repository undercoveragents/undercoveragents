# frozen_string_literal: true

FactoryBot.define do
  factory :capabilities_title_generator_standalone, class: "Capabilities::TitleGenerator" do
    max_length { 30 }
    max_turns { 3 }
    llm_config_source { "inherit" }
    temperature { 0.7 }
  end
end
