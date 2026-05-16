# frozen_string_literal: true

module ChatReferences
  module ReferenceFormatter
    module_function

    def prompt_identifier(reference)
      reference = reference.to_h.stringify_keys
      reference["prompt_text"].presence || derived_prompt_identifier(reference)
    end

    private_class_method def derived_prompt_identifier(reference)
      type = reference["type"].to_s.downcase.presence
      id = reference["id"].presence
      return unless type && id

      "#{type} id: #{id}"
    end
  end
end
