# frozen_string_literal: true

require "rails_helper"

RSpec.describe TestSuites::EvaluationService do
  let(:llm_connector) { create(:connector, :llm_provider, :enabled) }
  let(:agent) { create(:agent, llm_connector:) }
  let(:test_suite) do
    create(:test_suite, agent:,
                        evaluation_llm_connector: llm_connector,
                        evaluation_model_id: "gpt-4.1-mini",
                        evaluation_temperature: 0.3,)
  end

  let(:llm_chat_double) { double("RubyLLM::Chat").as_null_object } # rubocop:disable RSpec/VerifiedDoubles

  before do
    create(:model, model_id: "gpt-4.1-mini") unless Model.exists?(model_id: "gpt-4.1-mini")
    allow_any_instance_of(Chat).to receive(:with_model).and_return(nil) # rubocop:disable RSpec/AnyInstance
    allow_any_instance_of(Chat).to receive(:with_temperature).and_return(nil) # rubocop:disable RSpec/AnyInstance
    allow_any_instance_of(Chat).to receive(:context=) # rubocop:disable RSpec/AnyInstance
    allow_any_instance_of(Chat).to receive(:to_llm).and_return(llm_chat_double) # rubocop:disable RSpec/AnyInstance
  end

  describe ".call" do
    let(:valid_json_response) do
      '{"score": 0.85, "analysis": "The answer closely matches the expected output."}'
    end

    let(:llm_response) { instance_double(RubyLLM::Message, content: valid_json_response) }

    before do
      allow_any_instance_of(Chat).to receive(:ask).and_return(llm_response) # rubocop:disable RSpec/AnyInstance
    end

    it "creates a system chat for the evaluation" do
      expect do
        described_class.call(
          prompt: "What is 2+2?",
          expected: "4",
          actual: "Four",
          test_suite:,
        )
      end.to change(Chat, :count).by(1)

      chat = Chat.last
      expect(chat.execution_context).to eq("system")
    end

    it "returns evaluation result with score, passed, and analysis" do
      result = described_class.call(
        prompt: "What is 2+2?",
        expected: "4",
        actual: "Four",
        test_suite:,
      )

      expect(result[:score]).to eq(0.85)
      expect(result[:passed]).to be true
      expect(result[:analysis]).to include("closely matches")
    end

    it "links to parent_chat when provided" do
      parent = create(:chat, :test_context)
      described_class.call(
        prompt: "What is 2+2?",
        expected: "4",
        actual: "Four",
        test_suite:,
        context: { parent_chat: parent },
      )

      chat = Chat.last
      expect(chat.parent_chat).to eq(parent)
    end

    context "when score is below threshold" do
      let(:low_score_response) do
        '{"score": 0.3, "analysis": "The answer does not match."}'
      end
      let(:llm_response) { instance_double(RubyLLM::Message, content: low_score_response) }

      it "returns passed: false" do
        result = described_class.call(
          prompt: "What is 2+2?",
          expected: "4",
          actual: "The answer is 42",
          test_suite:,
        )

        expect(result[:passed]).to be false
        expect(result[:score]).to eq(0.3)
      end
    end

    context "when response includes markdown code fences" do
      let(:fenced_response) do
        "```json\n{\"score\": 0.9, \"analysis\": \"Great match\"}\n```"
      end
      let(:llm_response) { instance_double(RubyLLM::Message, content: fenced_response) }

      it "strips code fences and parses JSON" do
        result = described_class.call(
          prompt: "test", expected: "test", actual: "test", test_suite:,
        )

        expect(result[:score]).to eq(0.9)
        expect(result[:analysis]).to eq("Great match")
      end
    end

    context "when response is invalid JSON" do
      let(:llm_response) { instance_double(RubyLLM::Message, content: "not json at all") }

      before { allow(Rails.logger).to receive(:error) }

      it "returns a failed result with parse error" do
        result = described_class.call(
          prompt: "test", expected: "test", actual: "test", test_suite:,
        )

        expect(result[:passed]).to be false
        expect(result[:score]).to eq(0.0)
        expect(result[:analysis]).to include("Failed to parse")
      end
    end

    context "when LLM call raises an error" do
      before do
        allow_any_instance_of(Chat).to receive(:ask).and_raise(StandardError, "API timeout") # rubocop:disable RSpec/AnyInstance
        allow(Rails.logger).to receive(:error)
      end

      it "returns a failed result with error message" do
        result = described_class.call(
          prompt: "test", expected: "test", actual: "test", test_suite:,
        )

        expect(result[:passed]).to be false
        expect(result[:score]).to eq(0.0)
        expect(result[:analysis]).to include("Evaluation failed")
      end

      it "logs the error" do
        described_class.call(prompt: "test", expected: "test", actual: "test", test_suite:)
        expect(Rails.logger).to have_received(:error).with(/Evaluation failed/)
      end
    end

    context "when score is out of range" do
      let(:clamped_response) do
        '{"score": 1.5, "analysis": "Overshot"}'
      end
      let(:llm_response) { instance_double(RubyLLM::Message, content: clamped_response) }

      it "clamps score to 0.0..1.0" do
        result = described_class.call(
          prompt: "test", expected: "test", actual: "test", test_suite:,
        )

        expect(result[:score]).to eq(1.0)
      end
    end
  end
end
