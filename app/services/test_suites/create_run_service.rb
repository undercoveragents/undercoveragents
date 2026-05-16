# frozen_string_literal: true

module TestSuites
  class CreateRunService
    def self.call(test_suite, test_cases: nil, user: nil)
      new(test_suite, test_cases:, user:).call
    end

    def initialize(test_suite, test_cases: nil, user: nil)
      @test_suite = test_suite
      @test_cases = selected_test_cases(test_cases)
      @user = user
    end

    def call
      run = nil

      ActiveRecord::Base.transaction do
        run = @test_suite.test_suite_runs.create!(
          status: :pending,
          total_count: @test_cases.size,
          user: @user,
        )

        @test_cases.each do |test_case|
          run.test_case_results.create!(
            test_case:,
            status: :pending,
          )
        end
      end

      run
    end

    private

    def selected_test_cases(test_cases)
      return @test_suite.test_cases.ordered.to_a if test_cases.blank?

      records = Array(test_cases).compact.sort_by(&:position)
      return records if records.all? { |test_case| test_case.test_suite_id == @test_suite.id }

      raise ArgumentError, "All selected test cases must belong to test suite '#{@test_suite.name}'."
    end
  end
end
