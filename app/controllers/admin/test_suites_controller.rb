# frozen_string_literal: true

module Admin
  class TestSuitesController < BaseController
    before_action :ensure_builtin_test_suites!, only: [:index]
    before_action :set_test_suite, only: [:show, :edit, :update, :destroy, :run_suite]

    def index
      authorize TestSuite
      @test_suites = tenant_scoped_test_suites.ordered.to_a
      preload_test_suite_targets(@test_suites)
      preload_test_suite_runs(@test_suites)
      preload_test_case_counts(@test_suites)
    end

    def show
      authorize @test_suite
      @test_cases = @test_suite.test_cases.ordered
      @latest_run = @test_suite.latest_run
      @runs = @test_suite.test_suite_runs.recent.limit(10)
    end

    def new
      @test_suite = TestSuite.new(suite_type: params[:suite_type] || "agent")
      authorize @test_suite
      load_form_data
    end

    def edit
      authorize @test_suite
      load_form_data
    end

    def create
      @test_suite = TestSuite.new(test_suite_params)
      authorize @test_suite

      if @test_suite.save
        redirect_to admin_test_suite_path(@test_suite),
                    notice: t("test_suites.created")
      else
        load_form_data
        render :new, status: :unprocessable_content
      end
    end

    def update
      authorize @test_suite

      if @test_suite.update(test_suite_params)
        redirect_to admin_test_suite_path(@test_suite),
                    notice: t("test_suites.updated")
      else
        load_form_data
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      authorize @test_suite
      @test_suite.destroy!
      redirect_to admin_test_suites_path,
                  notice: t("test_suites.deleted"), status: :see_other
    end

    def run_suite
      authorize @test_suite, :run?

      unless @test_suite.can_run?
        redirect_to admin_test_suite_path(@test_suite),
                    alert: t("test_suites.cannot_run")
        return
      end

      run = TestSuites::CreateRunService.call(@test_suite, user: current_user)
      run.update!(status: :running, started_at: Time.current)
      TestSuiteExecutionJob.perform_later(run.id, tenant_id: test_suite_tenant_id(@test_suite))

      redirect_to admin_test_suite_test_suite_run_path(@test_suite, run)
    end

    private

    def set_test_suite
      @test_suite = tenant_scoped_test_suites.friendly.find(params.expect(:id))
    end

    def ensure_builtin_test_suites!
      BuiltinTestSuites::Synchronizer.ensure_present!(tenant: current_tenant) if current_operation&.headquarter?
    end

    def test_suite_tenant_id(test_suite)
      test_suite.agent&.operation&.tenant_id || test_suite.mission&.operation&.tenant_id
    end

    def test_suite_params
      permitted = [:name, :description, :suite_type]

      if params.dig(:test_suite, :suite_type) == "agent" || @test_suite&.agent?
        permitted += [:agent_id, :evaluation_llm_connector_id,
                      :evaluation_model_id, :evaluation_temperature,]
      else
        permitted << :mission_id
      end

      params.expect(test_suite: permitted)
    end

    def preload_test_case_counts(test_suites)
      return if test_suites.empty?

      counts = TestCase.where(test_suite_id: test_suites.map(&:id)).group(:test_suite_id).count

      test_suites.each do |test_suite|
        test_suite.test_case_count = counts.fetch(test_suite.id, 0)
      end
    end

    def preload_test_suite_targets(test_suites)
      agent_suites, mission_suites = test_suites.partition(&:agent?)

      preload_records(agent_suites, :agent)
      preload_records(mission_suites, :mission)
    end

    def preload_test_suite_runs(test_suites)
      preload_records(test_suites, :test_suite_runs)
    end

    def preload_records(records, associations)
      ActiveRecord::Associations::Preloader.new(
        records:,
        associations:,
      ).call
    end

    def load_form_data
      @available_agents = scoped_agents.enabled.selectable.ordered
      @available_missions = scoped_missions.order(:name)
      @available_llm_connectors = scoped_connectors.llm_providers.enabled.ordered
      load_evaluation_models
    end

    def load_evaluation_models
      provider_connector = @test_suite.evaluation_llm_connector
      provider = provider_connector.provider if provider_connector&.connector_type == "llm_provider"
      @evaluation_models = if provider.present?
                             Model.where(provider:).order(:name).select(:model_id, :name, :provider)
                           else
                             Model.none
                           end
    end
  end
end
