# frozen_string_literal: true

module PageEmptyStateHelper
  PageEmptyStateComponent = Data.define(:title, :body, :actions)

  def render_page_empty_state(title:, body:, &)
    actions = capture(&) if block_given?
    empty_state = PageEmptyStateComponent.new(title:, body:, actions:)

    render partial: "shared/page_empty_state", locals: { empty_state: }
  end
end
