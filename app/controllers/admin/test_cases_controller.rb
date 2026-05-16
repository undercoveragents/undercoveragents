# frozen_string_literal: true

module Admin
  class TestCasesController < BaseController
    before_action :set_test_suite
    before_action :set_test_case, only: [:update, :destroy]

    def create
      @test_case = @test_suite.test_cases.build(test_case_params)
      authorize_suite!

      if @test_case.save
        respond_to do |format|
          format.turbo_stream { render turbo_stream: create_success_streams }
          format.html { redirect_to suite_path, notice: t("test_cases.created") }
        end
      else
        respond_to do |format|
          format.turbo_stream { render turbo_stream: create_error_stream }
          format.html { redirect_to suite_path, alert: @test_case.errors.full_messages.join(", ") }
        end
      end
    end

    def update
      authorize_suite!

      if @test_case.update(test_case_params)
        respond_to do |format|
          format.turbo_stream { render turbo_stream: update_success_stream }
          format.html { redirect_to suite_path, notice: t("test_cases.updated") }
        end
      else
        respond_to do |format|
          format.turbo_stream { render turbo_stream: update_error_stream }
          format.html { redirect_to suite_path, alert: @test_case.errors.full_messages.join(", ") }
        end
      end
    end

    def destroy
      authorize_suite!
      @test_case.destroy!

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace("test-cases-list",
                                 partial: "test_suites/test_cases_list",
                                 locals: view_locals(test_cases: @test_suite.reload.test_cases.ordered),),
            turbo_stream.replace("test-cases-count",
                                 partial: "test_suites/test_cases_count",
                                 locals: { test_suite: @test_suite.reload },),
          ]
        end
        format.html do
          redirect_to suite_path, notice: t("test_cases.deleted"), status: :see_other
        end
      end
    end

    private

    def suite_path
      admin_test_suite_path(@test_suite)
    end

    def view_locals(extra = {})
      { test_suite: @test_suite }.merge(extra)
    end

    def create_success_streams
      [
        turbo_stream.replace("test-cases-list",
                             partial: "test_suites/test_cases_list",
                             locals: view_locals(test_cases: @test_suite.reload.test_cases.ordered),),
        turbo_stream.replace("test-case-form",
                             partial: "test_suites/test_case_form",
                             locals: view_locals(test_case: @test_suite.test_cases.build),),
        turbo_stream.replace("test-cases-count",
                             partial: "test_suites/test_cases_count",
                             locals: { test_suite: @test_suite.reload },),
      ]
    end

    def create_error_stream
      turbo_stream.replace("test-case-form",
                           partial: "test_suites/test_case_form",
                           locals: view_locals(test_case: @test_case),)
    end

    def update_success_stream
      turbo_stream.replace("test-case-#{@test_case.id}",
                           partial: "test_suites/test_case_row",
                           locals: view_locals(test_case: @test_case),)
    end

    def update_error_stream
      turbo_stream.replace("test-case-#{@test_case.id}",
                           partial: "test_suites/test_case_edit",
                           locals: view_locals(test_case: @test_case),)
    end

    def set_test_suite
      @test_suite = tenant_scoped_test_suites.friendly.find(params.expect(:test_suite_id))
    end

    def set_test_case
      @test_case = @test_suite.test_cases.find(params.expect(:id))
    end

    def test_case_params
      if @test_suite.mission?
        mission_test_case_params
      else
        agent_test_case_params
      end
    end

    def agent_test_case_params
      permitted = [
        :name,
        :prompt,
        :expected_answer,
        :match_type,
        :position,
        :scenario_key,
        :category,
        :complexity,
        :fixture_key,
        :expected_child_builtin_key,
      ]
      raw = params.expect(test_case: permitted)
      raw[:disallow_child_chats] = boolean_param(params.dig(:test_case, :disallow_child_chats))
      raw[:expected_tool_names] = parse_list_param(params.dig(:test_case, :expected_tool_names))
      raw[:required_keywords] = parse_list_param(params.dig(:test_case, :required_keywords))
      raw[:forbidden_keywords] = parse_list_param(params.dig(:test_case, :forbidden_keywords))
      raw
    end

    def mission_test_case_params
      permitted = [:name, :expected_status, :match_type, :position]
      raw = params.expect(test_case: permitted)
      raw[:input_variables] = parse_json_param(params.dig(:test_case, :input_variables))
      raw[:expected_variables] = parse_json_param(params.dig(:test_case, :expected_variables))
      raw
    end

    def parse_json_param(value)
      return {} if value.blank?

      JSON.parse(value)
    rescue JSON::ParserError
      {}
    end

    def parse_list_param(value)
      return [] if value.blank?
      return value.map { |item| item.to_s.strip }.compact_blank if value.is_a?(Array)

      value.to_s.lines.flat_map { |line| line.split(",") }.map(&:strip).compact_blank
    end

    def boolean_param(value)
      ActiveModel::Type::Boolean.new.cast(value) || false
    end

    def authorize_suite!
      authorize @test_suite, :update?
    end
  end
end
