# frozen_string_literal: true

require "rails_helper"

RSpec.describe AutomatableRecordContext do
  controller(ApplicationController) do
    include AutomatableRecordContext # rubocop:disable RSpec/DescribedClass

    skip_before_action :require_authentication
    before_action :set_schedulable

    def index
      head :ok
    end
  end

  let(:tenant) { create(:tenant).tap(&:ensure_core_resources!) }
  let(:mission) { create(:mission, operation: tenant.default_operation) }
  let(:rag_flow) { create(:rag_flow, operation: tenant.default_operation) }

  before do
    routes.draw { get "index" => "anonymous#index" }
    allow(controller).to receive(:current_tenant).and_return(tenant)
  end

  it "resolves missions and adopts their operation" do
    get :index, params: { mission_id: mission.slug }

    expect(response).to have_http_status(:ok)
    expect(controller.instance_variable_get(:@schedulable)).to eq(mission)
    expect(session[:current_operation_id]).to eq(mission.operation_id)
  end

  it "resolves rag flows and adopts their operation" do
    get :index, params: { rag_flow_id: rag_flow.slug }

    expect(response).to have_http_status(:ok)
    expect(controller.instance_variable_get(:@schedulable)).to eq(rag_flow)
    expect(session[:current_operation_id]).to eq(rag_flow.operation_id)
  end

  it "raises when no supported automation target is present" do
    expect { get :index }.to raise_error(ActionController::RoutingError, "Unknown automation target")
  end
end
