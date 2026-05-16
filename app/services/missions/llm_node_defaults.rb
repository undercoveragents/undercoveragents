# frozen_string_literal: true

module Missions
  module LlmNodeDefaults
    module_function

    def apply(type:, data:, **_options)
      normalized = data.deep_stringify_keys
      return normalized unless type.to_s == "llm"

      normalized["llm_config_source"] = Missions::LlmNodeRuntimeConfig.source_for(normalized)
      normalized
    end
  end
end
