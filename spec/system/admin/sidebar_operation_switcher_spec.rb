# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin sidebar operation switcher", :js do
  let!(:tenant) { create(:tenant).tap(&:ensure_core_resources!) }
  let!(:user) { create(:user, :admin, tenant:) }
  let!(:operation) { create(:operation, tenant:, name: "Ops Beta", icon: "fa-solid fa-satellite") }

  before do
    create(:model, model_id: "gpt-4.1", provider: "openai")
    create(:system_preference, :configured, tenant:)
  end

  it "updates the outer sidebar while keeping Agent Alpha mounted", :aggregate_failures do
    open_admin_root
    mark_agent_alpha_frame

    switch_to_operation

    expect(page).to have_css(".sidebar-operation-name", text: "Ops Beta")
    expect(page).to have_no_css(".sidebar-operation-dropdown.is-open", visible: :all)
    expect(page).to have_current_path(admin_root_path(operation: operation.slug), ignore_query: false)
    expect_agent_alpha_frame_to_remain_mounted

    open_operation_manager

    expect(page).to have_current_path(admin_operations_path, ignore_query: true)
    expect(page).to have_css(".sidebar-link.active", text: "Operations")
    expect(page).to have_no_css(".sidebar-operation-dropdown.is-open", visible: :all)
    expect_agent_alpha_frame_to_remain_mounted
  end

  def open_admin_root
    visit tenant_login_path(tenant)
    fill_in "Email", with: user.email
    fill_in "Password", with: "Password123!"
    click_button "Sign In"

    expect(page).to have_current_path(admin_root_path, ignore_query: true)
    click_button nil, title: "Agent Alpha"
    expect(page).to have_css("#admin-agent-alpha-frame", visible: :all)
  end

  def mark_agent_alpha_frame
    page.execute_script(
      "document.querySelector('#admin-agent-alpha-frame').dataset.persistenceProbe = 'mounted'",
    )
  end

  def switch_to_operation
    within(".sidebar-operation") do
      find(".sidebar-operation-btn").click
      expect(page).to have_css(".sidebar-operation-dropdown.is-open", visible: :all)
      click_button "Ops Beta"
    end
  end

  def open_operation_manager
    within(".sidebar-operation") do
      find(".sidebar-operation-btn").click
      click_link "Manage"
    end
  end

  def expect_agent_alpha_frame_to_remain_mounted
    probe = page.evaluate_script(
      "document.querySelector('#admin-agent-alpha-frame')?.dataset.persistenceProbe",
    )

    expect(probe).to eq("mounted")
  end
end
