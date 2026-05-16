# frozen_string_literal: true

require "rails_helper"

RSpec.describe UndercoverAgents::RubyLlmDebugLogging do
  describe ".capture_chat_request" do
    let(:capture_request_kwargs) do
      {
        provider:,
        model:,
        messages:,
        tools: { widget_lookup: tool },
        temperature: 0.4,
        params: { api_key: "secret", top_p: 0.9 },
        headers: { authorization: "Bearer test" },
        schema: { type: "object" },
        thinking: { effort: "medium" },
        tool_prefs: { choice: "auto" },
        streaming: true,
      }
    end
    let(:provider) { instance_double(RubyLLM::Provider, slug: "openai") }
    let(:log_dir) { Dir.mktmpdir }
    let(:log_path) { Pathname.new(File.join(log_dir, "llm.log")) }
    let(:chat_log_path) { Pathname.new(File.join(log_dir, "llm_chat_123.log")) }
    let(:model) { Struct.new(:id, :provider).new("gpt-4.1", "openai") }
    let(:provider_payload) do
      {
        payload: {
          messages: [
            { role: "system", content: "System instructions" },
            { role: "user", content: "User prompt" },
          ],
          tools: [
            {
              function: {
                name: "widget_lookup",
                description: "Lists available widgets",
              },
            },
          ],
        },
        normalized_temperature: 0.4,
      }
    end
    let(:tool) do
      Class.new(RubyLLM::Tool) do
        description "Lists available widgets"
        param :query, desc: "Optional widget filter"

        def name
          "widget_lookup"
        end

        def execute(query: nil)
          query
        end
      end.new
    end
    let(:messages) do
      [
        Struct.new(:role, :content, :tool_call_id, :tool_calls, keyword_init: true).new(
          role: :system,
          content: "System instructions",
        ),
        Struct.new(:role, :content, :tool_call_id, :tool_calls, keyword_init: true).new(
          role: :user,
          content: "User prompt",
        ),
      ]
    end

    after do
      FileUtils.rm_rf(log_dir)
    end

    def capture_chat_request
      described_class.capture_chat_request(**capture_request_kwargs) { provider_payload }
    end

    it "writes a readable request dump when enabled" do
      stub_const("UndercoverAgents::RubyLlmDebugLogging::ENABLED", true)
      stub_const("UndercoverAgents::RubyLlmDebugLogging::LOG_PATH", log_path)

      capture_chat_request

      content = File.read(log_path)

      expect(content).to include(
        "kind=chat provider=openai model=gpt-4.1",
        "streaming=true",
        "System instructions",
        "User prompt",
        "widget_lookup",
        "[FILTERED]",
      )
      expect(content).not_to include("Bearer test")
      expect(content).not_to include("api_key\": \"secret\"")
    end

    it "writes to a chat-specific log file when a current chat is present" do
      stub_const("UndercoverAgents::RubyLlmDebugLogging::ENABLED", true)
      stub_const("UndercoverAgents::RubyLlmDebugLogging::LOG_PATH", log_path)
      Current.chat = build_stubbed(:chat, id: 123)

      capture_chat_request

      expect(File.exist?(chat_log_path)).to be(true)
      expect(File.exist?(log_path)).to be(false)
      expect(File.read(chat_log_path)).to include("chat_id=123")
    end

    it "does nothing when disabled" do
      stub_const("UndercoverAgents::RubyLlmDebugLogging::ENABLED", false)
      stub_const("UndercoverAgents::RubyLlmDebugLogging::LOG_PATH", log_path)

      described_class.capture_chat_request(
        provider:,
        model:,
        messages:,
        tools: {},
        temperature: nil,
        params: {},
        headers: {},
        schema: nil,
        thinking: nil,
        tool_prefs: {},
        streaming: false,
      ) do
        raise "should not build payload"
      end

      expect(File.exist?(log_path)).to be(false)
    end
  end

  describe "ProviderPatch#paint" do
    let(:image_options) do
      {
        with: ["source.png"],
        mask: "mask.png",
        params: { quality: "high" },
      }
    end
    let(:provider_class) do
      Class.new do
        def slug = "openai"

        def render_image_payload(prompt, model:, size:, **options)
          { prompt:, model:, size:, **options }
        end

        def paint(prompt, model:, size:, **options)
          { prompt:, model:, size:, **options }
        end
      end
    end
    let(:provider) do
      provider_class.prepend(described_class::ProviderPatch)
      provider_class.new
    end
    let(:expected_result) do
      {
        prompt: "Prompt",
        model: "gpt-image-1",
        size: "1024x1024",
        **image_options,
      }
    end

    it "forwards image kwargs introduced by RubyLLM image generation" do
      result = provider.paint("Prompt", model: "gpt-image-1", size: "1024x1024", **image_options)

      expect(result).to eq(expected_result)
    end
  end

  describe "provider patch wiring" do
    it "prepends the logger patch into RubyLLM::Provider" do
      expect(RubyLLM::Provider.ancestors).to include(described_class::ProviderPatch)
    end
  end
end
