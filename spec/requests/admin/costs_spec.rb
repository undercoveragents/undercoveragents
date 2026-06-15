# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin cost analysis" do
  let(:tenant) { default_tenant }
  let(:operation) { default_operation }
  let(:model_record) { create(:model) }
  let(:agent) { create(:agent, operation:, name: "Primary agent") }
  let(:user) { create(:user, tenant:, email: "costs@example.com") }

  before do
    chat = create(
      :chat,
      tenant:,
      operation:,
      model: model_record,
      agent:,
      user:,
      title: "Application spend",
      execution_context: :application,
    )
    create(:message, chat:, model: model_record).update_columns( # rubocop:disable Rails/SkipsModelValidations
      cost_usd: 4.25,
      cost_calculated_at: Time.current,
    )
  end

  it "renders the cost dashboard" do
    get admin_costs_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Cost Analysis", "Filters", "Total spend", "Spend over time")
    expect(response.body).to include("Execution context", "User", "Agent", "Model")
  end

  it "renders the cost dashboard filtered by operation" do
    get admin_costs_path, params: { operation: operation.slug, period: "not-a-period" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(operation.name)
  end

  it "filters the dashboard by additional query filters" do
    system_chat = create(
      :chat,
      tenant:,
      operation:,
      model: model_record,
      agent:,
      user:,
      title: "System spend",
      execution_context: :system,
    )
    create(:message, chat: system_chat, model: model_record).update_columns( # rubocop:disable Rails/SkipsModelValidations
      cost_usd: 9.5,
      cost_calculated_at: Time.current,
    )

    get admin_costs_path, params: {
      operation: operation.slug,
      execution_context: "application",
      user_id: user.id,
      agent_id: agent.id,
      model_id: model_record.id,
    }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Application spend")
    expect(response.body).not_to include("System spend")
  end

  it "ignores invalid execution context filters" do
    system_chat = create(
      :chat,
      tenant:,
      operation:,
      model: model_record,
      agent:,
      user:,
      title: "System spend",
      execution_context: :system,
    )
    create(:message, chat: system_chat, model: model_record).update_columns( # rubocop:disable Rails/SkipsModelValidations
      cost_usd: 9.5,
      cost_calculated_at: Time.current,
    )

    get admin_costs_path, params: { execution_context: "not-a-context" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Application spend")
    expect(response.body).to include("System spend")
  end

  it "renders cost limit index, new, edit, and show pages" do
    limit = create(:cost_limit, tenant:, name: "Visible cap")

    get admin_cost_limits_path
    expect(response.body).to include("Visible cap")

    get new_admin_cost_limit_path
    expect(response.body).to include("New Cost Limit")

    get edit_admin_cost_limit_path(limit)
    expect(response.body).to include("Edit Cost Limit")

    get admin_cost_limit_path(limit)
    expect(response.body).to include("Visible cap")
  end

  it "creates and toggles a limit" do
    post admin_cost_limits_path, params: {
      cost_limit: {
        name: "Default workspace cap",
        target_type: "operation",
        operation_id: operation.id,
        period: "month",
        amount_usd: "25.00",
        warning_threshold_percent: "80",
        enforcement_mode: "hard_stop",
        enabled: "1",
      },
    }

    limit = CostLimit.find_by!(name: "Default workspace cap")
    expect(response).to redirect_to(admin_cost_limit_path(limit))

    patch toggle_admin_cost_limit_path(limit)
    expect(limit.reload.enabled?).to be(false)

    patch toggle_admin_cost_limit_path(limit)
    expect(limit.reload.enabled?).to be(true)
  end

  it "updates and deletes a limit" do
    limit = create(:cost_limit, :for_operation, tenant:, operation:, name: "Default workspace cap")

    patch admin_cost_limit_path(limit), params: {
      cost_limit: {
        name: "Default workspace warning",
        amount_usd: "50.00",
        warning_threshold_percent: "90",
      },
    }
    expect(limit.reload).to have_attributes(name: "Default workspace warning", amount_usd: BigDecimal("50.0"))

    delete admin_cost_limit_path(limit)
    expect(CostLimit.exists?(limit.id)).to be(false)
  end

  it "renders validation errors for invalid create and update" do
    post admin_cost_limits_path, params: {
      cost_limit: {
        name: "",
        target_type: "tenant",
        period: "month",
        amount_usd: "-1",
      },
    }
    expect(response).to have_http_status(:unprocessable_content)

    limit = create(:cost_limit, tenant:)
    patch admin_cost_limit_path(limit), params: { cost_limit: { amount_usd: "-1" } }
    expect(response).to have_http_status(:unprocessable_content)
  end
end
