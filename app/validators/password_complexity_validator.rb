# frozen_string_literal: true

class PasswordComplexityValidator < ActiveModel::EachValidator
  REQUIREMENTS = [
    { pattern: /[A-Z]/, message: "must include at least one uppercase letter" },
    { pattern: /[a-z]/, message: "must include at least one lowercase letter" },
    { pattern: /[0-9]/, message: "must include at least one digit" },
    { pattern: /[^A-Za-z0-9]/, message: "must include at least one special character" },
  ].freeze

  def validate_each(record, attribute, value)
    return if value.blank?

    REQUIREMENTS.each do |req|
      record.errors.add(attribute, req[:message]) unless value.match?(req[:pattern])
    end
  end
end
