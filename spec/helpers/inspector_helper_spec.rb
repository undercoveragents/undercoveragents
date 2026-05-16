# frozen_string_literal: true

require "rails_helper"

RSpec.describe InspectorHelper do
  describe "#inspector_role_icon" do
    it "returns gear icon for system" do
      expect(helper.inspector_role_icon("system")).to eq("fa-solid fa-gear")
    end

    it "returns user icon for user" do
      expect(helper.inspector_role_icon("user")).to eq("fa-solid fa-user")
    end

    it "returns robot icon for assistant" do
      expect(helper.inspector_role_icon("assistant")).to eq("fa-solid fa-user-secret")
    end

    it "returns wrench icon for tool" do
      expect(helper.inspector_role_icon("tool")).to eq("fa-solid fa-wrench")
    end

    it "returns question icon for unknown role" do
      expect(helper.inspector_role_icon("unknown")).to eq("fa-solid fa-circle-question")
    end
  end

  describe "#inspector_role_color_class" do
    it "returns correct class for each role" do
      expect(helper.inspector_role_color_class("system")).to eq("inspector-role-system")
      expect(helper.inspector_role_color_class("user")).to eq("inspector-role-user")
      expect(helper.inspector_role_color_class("assistant")).to eq("inspector-role-assistant")
      expect(helper.inspector_role_color_class("tool")).to eq("inspector-role-tool")
    end

    it "returns default class for unknown role" do
      expect(helper.inspector_role_color_class("unknown")).to eq("inspector-role-default")
    end
  end

  describe "#inspector_execution_context_badge" do
    it "returns brand badge for playground" do
      expect(helper.inspector_execution_context_badge("playground")).to eq("badge-brand")
    end

    it "returns warning badge for test" do
      expect(helper.inspector_execution_context_badge("test")).to eq("badge-warning")
    end

    it "returns neutral badge for system" do
      expect(helper.inspector_execution_context_badge("system")).to eq("badge-neutral")
    end

    it "returns success badge for user" do
      expect(helper.inspector_execution_context_badge("user")).to eq("badge-success")
    end

    it "returns info badge for mission" do
      expect(helper.inspector_execution_context_badge("mission")).to eq("badge-info")
    end

    it "returns secondary badge for unknown context" do
      expect(helper.inspector_execution_context_badge("unknown")).to eq("badge-secondary")
    end

    it "converts symbol to string" do
      expect(helper.inspector_execution_context_badge(:playground)).to eq("badge-brand")
    end
  end

  describe "#inspector_status_badge" do
    it "returns success badge for idle" do
      expect(helper.inspector_status_badge("idle")).to eq("badge-success")
    end

    it "returns brand badge for streaming" do
      expect(helper.inspector_status_badge("streaming")).to eq("badge-brand")
    end

    it "returns warning badge for cancelled" do
      expect(helper.inspector_status_badge("cancelled")).to eq("badge-warning")
    end

    it "returns neutral badge for unknown status" do
      expect(helper.inspector_status_badge("unknown")).to eq("badge-neutral")
    end
  end

  describe "#inspector_format_cost" do
    it "returns dash for nil cost" do
      expect(helper.inspector_format_cost(nil)).to eq("—")
    end

    it "returns dash for zero cost" do
      expect(helper.inspector_format_cost(0)).to eq("—")
    end

    it "formats cost with 6 decimal places" do
      expect(helper.inspector_format_cost(0.000525)).to eq("$0.000525")
    end
  end

  describe "#inspector_format_tokens" do
    it "returns dash for nil" do
      expect(helper.inspector_format_tokens(nil)).to eq("—")
    end

    it "returns dash for zero" do
      expect(helper.inspector_format_tokens(0)).to eq("—")
    end

    it "formats token counts with delimiters" do
      expect(helper.inspector_format_tokens(1500)).to eq("1,500")
    end
  end

  describe "#inspector_format_duration" do
    it "returns dash for nil" do
      expect(helper.inspector_format_duration(nil)).to eq("—")
    end

    it "returns dash for zero" do
      expect(helper.inspector_format_duration(0)).to eq("—")
    end

    it "formats durations under 1 second in milliseconds" do
      expect(helper.inspector_format_duration(450)).to eq("450ms")
    end

    it "formats durations of 1 second or more in seconds" do
      expect(helper.inspector_format_duration(2500)).to eq("2.50s")
    end

    it "formats durations of exactly 1 second" do
      expect(helper.inspector_format_duration(1000)).to eq("1.00s")
    end

    it "formats durations of 1 minute or more with minutes and seconds" do
      expect(helper.inspector_format_duration(65_000)).to eq("1m 5.0s")
    end

    it "formats large durations correctly" do
      expect(helper.inspector_format_duration(125_500)).to eq("2m 5.5s")
    end
  end

  describe "#inspector_token_summary" do
    it "includes input tokens when positive" do
      message = build(:message, input_tokens: 500, output_tokens: 0, cached_tokens: 0)
      expect(helper.inspector_token_summary(message)).to eq("500in")
    end

    it "includes output tokens when positive" do
      message = build(:message, input_tokens: 0, output_tokens: 200, cached_tokens: 0)
      expect(helper.inspector_token_summary(message)).to eq("200out")
    end

    it "includes cached tokens when positive" do
      message = build(:message, input_tokens: 0, output_tokens: 0, cached_tokens: 50)
      expect(helper.inspector_token_summary(message)).to eq("50cached")
    end

    it "joins multiple token types with separator" do
      message = build(:message, input_tokens: 500, output_tokens: 200, cached_tokens: 50)
      expect(helper.inspector_token_summary(message)).to eq("500in / 200out / 50cached")
    end

    it "returns empty string when all tokens are zero" do
      message = build(:message, input_tokens: 0, output_tokens: 0, cached_tokens: 0)
      expect(helper.inspector_token_summary(message)).to eq("")
    end

    it "handles nil token values" do
      message = build(:message, input_tokens: nil, output_tokens: nil, cached_tokens: nil)
      expect(helper.inspector_token_summary(message)).to eq("")
    end
  end

  describe "#inspector_content_preview" do
    it "returns dash for blank content" do
      expect(helper.inspector_content_preview(nil)).to eq("—")
      expect(helper.inspector_content_preview("")).to eq("—")
    end

    it "truncates long content" do
      long_text = "a" * 200
      result = helper.inspector_content_preview(long_text)
      expect(result.length).to be <= 120
    end
  end

  describe "#inspector_child_chat_cost" do
    it "sums message costs for a child chat" do
      chat = create(:chat)
      model_record = create(:model, model_id: "gpt-4.1", provider: "openai")
      create(:message, :assistant, chat:, model: model_record, input_tokens: 100, output_tokens: 50)
      chat.reload
      result = helper.inspector_child_chat_cost(chat)
      expect(result).to be_a(Numeric)
    end

    it "returns zero for chat with no messages" do
      chat = create(:chat)
      expect(helper.inspector_child_chat_cost(chat)).to eq(0)
    end
  end

  describe "#inspector_child_chat_tokens" do
    it "sums input and output tokens" do
      chat = create(:chat)
      create(:message, :assistant, chat:, input_tokens: 100, output_tokens: 50)
      create(:message, :user, chat:, input_tokens: 200, output_tokens: 0)
      chat.reload
      result = helper.inspector_child_chat_tokens(chat)
      expect(result[:input]).to eq(300)
      expect(result[:output]).to eq(50)
    end

    it "returns zeros for chat with no messages" do
      chat = create(:chat)
      result = helper.inspector_child_chat_tokens(chat)
      expect(result[:input]).to eq(0)
      expect(result[:output]).to eq(0)
    end
  end

  describe "#inspector_chat_header_meta" do
    before do
      helper.singleton_class.include(InspectorChatHeaderHelper)
    end

    let(:rich_chat_model) { double(model_id: "gpt-4.1") }
    let(:rich_chat) do
      double(
        status: "streaming",
        execution_context: "playground",
        child_chats: double(any?: true),
        model: rich_chat_model,
      )
    end

    let(:rich_chat_html) do
      helper.inspector_chat_header_meta(
        rich_chat,
        total_cost: 0.123456,
        token_totals: { input: 1200, output: 34 },
      ).join
    end

    it "includes the base and cost badges when optional pricing data exists" do
      expect(rich_chat_html).to include("streaming")
      expect(rich_chat_html).to include("playground")
      expect(rich_chat_html).to include("0.123456 (incl. children)")
    end

    it "includes the token and model badges when optional runtime data exists" do
      expect(rich_chat_html).to include("1,200")
      expect(rich_chat_html).to include("34")
      expect(rich_chat_html).to include("gpt-4.1")
    end

    it "omits the child-chat suffix when cost exists without child chats" do
      chat = double(
        status: "streaming",
        execution_context: "playground",
        child_chats: double(any?: false),
        model: nil,
      )

      html = helper.inspector_chat_header_meta(chat, total_cost: 0.123456, token_totals: { input: 0, output: 0 }).join

      expect(html).to include("0.123456")
      expect(html).not_to include("(incl. children)")
    end

    it "skips the cost badge when total cost is nil" do
      chat = double(
        status: "idle",
        execution_context: "system",
        child_chats: double(any?: false),
        model: nil,
      )

      html = helper.inspector_chat_header_meta(chat, total_cost: nil, token_totals: { input: 0, output: 0 }).join

      expect(html).not_to include("fa-dollar-sign")
    end

    it "returns only the base badges when optional data is absent" do
      chat = double(
        status: "idle",
        execution_context: "system",
        child_chats: double(any?: false),
        model: nil,
      )

      meta = helper.inspector_chat_header_meta(chat, total_cost: 0, token_totals: { input: 0, output: 0 })
      html = meta.join

      expect(html).to include("idle")
      expect(html).to include("system")
      expect(html).not_to include("fa-dollar-sign")
      expect(html).not_to include("fa-arrow-down")
      expect(html).not_to include("fa-microchip")
    end
  end

  describe "#inspector_filter_active?" do
    it "returns true when id filter is present" do
      expect(helper.inspector_filter_active?({ q: { id_eq: "42" } })).to be(true)
    end

    it "returns true when title filter is present" do
      expect(helper.inspector_filter_active?({ q: { title_cont: "test" } })).to be(true)
    end

    it "returns true when root_only is set" do
      expect(helper.inspector_filter_active?({ q: { parent_chat_id_null: "1" } })).to be(true)
    end

    it "returns false when no filters are set" do
      expect(helper.inspector_filter_active?({})).to be(false)
    end

    it "returns false when q is empty" do
      expect(helper.inspector_filter_active?({ q: {} })).to be(false)
    end

    it "returns false when filters are blank" do
      expect(helper.inspector_filter_active?({ q: { id_eq: "", title_cont: "" } })).to be(false)
    end

    it "returns false when only sort param is present" do
      expect(helper.inspector_filter_active?({ q: { s: "id asc" } })).to be(false)
    end
  end
end
