# frozen_string_literal: true

module PolicyAuthorizable
  private

  def authorize_policy!(record, query, user:)
    policy_target = record.is_a?(Class) ? record : record.class
    policy_class = "#{policy_target.name}Policy".safe_constantize
    raise ArgumentError, "Missing policy for #{policy_target.name}." unless policy_class

    policy = policy_class.new(user, record)
    return if policy.public_send(query)

    raise Pundit::NotAuthorizedError, (policy.denied_reason(query) || "Not allowed.")
  end
end
