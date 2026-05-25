# frozen_string_literal: true

require "rails_helper"

RSpec.describe CostAnalysisPresenter do
  let(:tenant) { create(:tenant).tap(&:ensure_core_resources!) }
  let(:operation) { tenant.default_operation }
  let(:model_record) { create(:model, model_id: "model-a") }
  let(:other_model) { create(:model, model_id: "model-b") }

  def create_costed_message(cost:, **attributes)
    execution_context = attributes.fetch(:execution_context)
    user = attributes.fetch(:user)
    agent = attributes.fetch(:agent)
    message_model = attributes.fetch(:message_model)
    chat_model = attributes.fetch(:chat_model, message_model)
    chat = create(
      :chat,
      tenant:,
      operation:,
      user:,
      agent:,
      model: chat_model,
      execution_context:,
      title: "#{execution_context} chat",
    )

    create(:message, chat:, model: message_model).tap do |message|
      message.update_columns(cost_usd: cost, cost_calculated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def seed_filter_dataset
    selected_user = create(:user, tenant:, email: "selected@example.com")
    selected_agent = create(:agent, operation:, name: "Selected agent")
    dataset = { selected_user:, selected_agent: }

    filter_dataset_rows(selected_user:, selected_agent:).each do |row|
      message = create_costed_message(**row.except(:key))
      dataset[:selected_message] = message if row[:key] == :selected_message
    end

    dataset
  end

  def filter_dataset_rows(selected_user:, selected_agent:)
    other_user = create(:user, tenant:, email: "other@example.com")
    other_agent = create(:agent, operation:, name: "Other agent")

    [
      filter_row(key: :selected_message, cost: "4.25", execution_context: "application", user: selected_user,
                 agent: selected_agent, message_model: model_record,),
      filter_row(cost: "2.00", execution_context: "system", user: selected_user, agent: selected_agent,
                 message_model: model_record,),
      filter_row(cost: "3.00", execution_context: "application", user: other_user, agent: selected_agent,
                 message_model: model_record,),
      filter_row(cost: "5.00", execution_context: "application", user: selected_user, agent: other_agent,
                 message_model: model_record,),
      filter_row(cost: "6.00", execution_context: "application", user: selected_user, agent: selected_agent,
                 message_model: other_model,),
    ]
  end

  def filter_row(cost:, key: nil, **attributes)
    {
      key:,
      cost: BigDecimal(cost),
      **attributes,
    }.compact
  end

  it "applies execution context, user, agent, and model filters to the message scope", :aggregate_failures do
    dataset = seed_filter_dataset

    presenter = described_class.new(
      tenant:,
      operation:,
      period: "rolling_30_days",
      filters: described_class::FilterSet.new(
        execution_context: "application",
        user: dataset.fetch(:selected_user),
        agent: dataset.fetch(:selected_agent),
        model: model_record,
      ),
    )

    expect(presenter.summary.total_cost).to eq(BigDecimal("4.25"))
    expect(presenter.recent_expensive_messages.map(&:id)).to contain_exactly(dataset.fetch(:selected_message).id)
    expect(presenter.cost_by_day.values).to eq([BigDecimal("4.25")])
    expect(presenter.dimension_groups.fetch("execution_context").map(&:key)).to eq(["application"])
  end
end
