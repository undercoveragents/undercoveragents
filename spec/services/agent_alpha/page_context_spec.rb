# frozen_string_literal: true

require "rails_helper"

RSpec.describe AgentAlpha::PageContext do
  def build_controller(**attributes)
    request_class = Struct.new(:fullpath)
    controller_class = Class.new do
      attr_reader :controller_name, :controller_path, :action_name, :request, :params

      def initialize(attributes, request_class)
        @controller_name = attributes.fetch(:controller_name)
        @controller_path = attributes.fetch(:controller_path)
        @action_name = attributes.fetch(:action_name)
        @request = request_class.new(attributes.fetch(:request_path))
        @params = ActionController::Parameters.new(attributes.fetch(:params))
        @current_user = attributes[:current_user]
        @current_tenant = attributes[:current_tenant]
        @current_operation = attributes[:current_operation]
      end

      private

      attr_reader :current_user, :current_tenant, :current_operation
    end

    controller_class.new(attributes, request_class)
  end

  def build_users_controller(user:, tenant:, operation: nil)
    build_controller(
      controller_name: "users",
      controller_path: "admin/users",
      action_name: "new",
      request_path: "/admin/users/new",
      params: { "controller" => "admin/users", "action" => "new" },
      current_user: user,
      current_tenant: tenant,
      current_operation: operation,
    )
  end

  def build_run_controller(run:, user:, tenant:)
    build_controller(
      controller_name: "runs",
      controller_path: "admin/mission_control/runs",
      action_name: "show",
      request_path: "/admin/mission_control/runs/#{run.id}",
      params: {
        "controller" => "admin/mission_control/runs",
        "action" => "show",
        "id" => run.id,
        "operation" => tenant.default_operation.slug,
      },
      current_user: user,
      current_tenant: tenant,
      current_operation: tenant.default_operation,
    )
  end

  def build_skill_preview_controller(user:, tenant:)
    build_controller(
      controller_name: "skills",
      controller_path: "admin/skills",
      action_name: "show",
      request_path: "/admin/skill_catalogs/catalog-1/skills/skill-1?view=preview&chat_id=33",
      params: {
        "controller" => "admin/skills",
        "action" => "show",
        "skill_catalog_id" => "catalog-1",
        "id" => "skill-1",
        "view" => "preview",
        "chat_id" => "33",
        "operation" => tenant.default_operation.slug,
      },
      current_user: user,
      current_tenant: tenant,
      current_operation: tenant.default_operation,
    )
  end

  describe ".issue_for" do
    it "returns nil when the controller has no current user" do
      controller = build_users_controller(user: nil, tenant: nil)

      expect(described_class.issue_for(controller)).to be_nil
    end

    it "signs a token even when the controller has no current tenant" do
      tenant = create(:tenant).tap(&:ensure_core_resources!)
      user = create(:user, :admin, tenant:)
      controller = build_users_controller(user:, tenant: nil)

      expect(described_class.issue_for(controller)).to be_present
    end
  end

  describe ".verify" do
    let(:tenant) { create(:tenant).tap(&:ensure_core_resources!) }
    let(:user) { create(:user, :admin, tenant:) }

    it "returns nil when the verifier payload is not a hash" do
      token = described_class.verifier.generate("invalid", purpose: described_class::PURPOSE)

      expect(described_class.verify(token, user:, tenant:)).to be_nil
    end

    it "accepts tokens that were intentionally issued without a tenant id" do
      token = described_class.verifier.generate(
        {
          "user_id" => user.id,
          "tenant_id" => nil,
          "payload" => {},
        },
        purpose: described_class::PURPOSE,
      )

      expect(described_class.verify(token, user:, tenant: nil)).to include("reference_trigger" => "#")
    end

    it "normalizes references and rejects tokens for the wrong user or tenant" do
      token = described_class.verifier.generate(
        {
          "user_id" => user.id,
          "tenant_id" => tenant.id,
          "payload" => {
            "references" => [123, { label: "Policy Mission", type: "Mission" }],
          },
        },
        purpose: described_class::PURPOSE,
      )

      expect(described_class.verify(token, user:, tenant:)).to include(
        "references" => [hash_including("label" => "Policy Mission", "type" => "Mission")],
        "reference_trigger" => "#",
      )

      other_user = create(:user, :admin, tenant:)
      other_tenant = create(:tenant).tap(&:ensure_core_resources!)

      expect(described_class.verify(token, user: other_user, tenant:)).to be_nil
      expect(described_class.verify(token, user:, tenant: other_tenant)).to be_nil
    end

    it "returns nil when normalize_payload receives a non-hash payload" do
      expect(described_class.normalize_payload("invalid")).to be_nil
    end
  end

  describe "#build" do
    let(:tenant) { create(:tenant).tap(&:ensure_core_resources!) }
    let(:user) { create(:user, :admin, tenant:) }

    it "falls back to controller naming when the candidate object is not context-serializable" do
      controller = build_users_controller(user:, tenant:)
      controller.instance_variable_set(:@user, "draft-user")

      payload = described_class.new(controller).build

      expect(payload).to include(
        "page" => hash_including("name" => "New User"),
        "reference_trigger" => "#",
      )
      expect(payload).not_to have_key("current_object")
      expect(payload).not_to have_key("operation")
    end

    it "ignores blank candidate objects" do
      controller = build_users_controller(user:, tenant:)
      controller.instance_variable_set(:@user, "")

      expect(described_class.new(controller).build).not_to have_key("current_object")
    end

    it "formats mission runs with the mission name when they are the selected object" do
      mission = create(:mission, name: "Policy Mission", operation: tenant.default_operation)
      run = create(:mission_run, mission:)
      controller = build_run_controller(run:, user:, tenant:)
      controller.instance_variable_set(:@run, run)

      payload = described_class.new(controller).build

      expect(payload).to include(
        "current_object" => hash_including("label" => "Policy Mission run ##{run.id}"),
        "operation" => hash_including("name" => tenant.default_operation.name),
      )
    end

    it "returns nil for mission runs without a mission" do
      context = described_class.new(build_users_controller(user:, tenant:))

      expect(context.send(:mission_run_label, MissionRun.new)).to be_nil
    end

    it "keeps nested resource ids and preview params in the page payload" do
      payload = described_class.new(build_skill_preview_controller(user:, tenant:)).build

      expect(payload).to include(
        "page" => hash_including(
          "params" => hash_including(
            "skill_catalog_id" => "catalog-1",
            "id" => "skill-1",
            "view" => "preview",
            "chat_id" => "33",
            "operation" => tenant.default_operation.slug,
          ),
        ),
      )
    end
  end
end
