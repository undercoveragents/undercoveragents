# frozen_string_literal: true

require "rails_helper"

RSpec.describe Telegram::ProcessMessageJob do
  let(:tenant) { create(:tenant) }
  let(:channel) { create(:channel, :telegram, tenant:) }

  it "processes a message via MessageProcessor" do
    processor = instance_double(Telegram::MessageProcessor, process: nil)
    allow(Telegram::MessageProcessor).to receive(:new).and_return(processor)

    described_class.perform_now(
      telegram_chat_id: 123,
      telegram_user_id: 456,
      telegram_username: "test",
      text: "/help",
      channel_id: channel.id,
    )

    expect(Telegram::MessageProcessor).to have_received(:new).with(
      channel:,
      telegram_chat_id: 123,
      telegram_user_id: 456,
      telegram_username: "test",
      text: "/help",
    )
    expect(processor).to have_received(:process)
  end

  it "handles missing channels gracefully" do
    allow(Rails.logger).to receive(:error)

    expect do
      described_class.perform_now(
        telegram_chat_id: 123,
        telegram_user_id: 456,
        channel_id: 999_999,
        tenant_id: tenant.id,
      )
    end.not_to raise_error

    expect(Rails.logger).to have_received(:error).with(/Channel not found/)
  end

  it "handles unexpected errors and attempts to send error message" do
    allow(Rails.logger).to receive(:error)
    processor = instance_double(Telegram::MessageProcessor)
    job = described_class.new

    allow(Telegram::MessageProcessor).to receive(:new).and_return(processor)
    allow(processor).to receive(:process).and_raise(StandardError, "boom")
    allow(job).to receive(:find_channel).and_return(channel)
    allow(channel.connector).to receive(:send_message)

    job.perform(
      telegram_chat_id: 123,
      telegram_user_id: 456,
      channel_id: channel.id,
      tenant_id: tenant.id,
    )

    expect(Rails.logger).to have_received(:error).with(/Error: boom/)
    expect(channel.connector).to have_received(:send_message)
      .with(123, "Sorry, an error occurred. Please try again later.")
  end

  it "handles send error silently when the fallback notification fails" do
    allow(Rails.logger).to receive(:error)
    processor = instance_double(Telegram::MessageProcessor)
    job = described_class.new

    allow(Telegram::MessageProcessor).to receive(:new).and_return(processor)
    allow(processor).to receive(:process).and_raise(StandardError, "boom")
    allow(job).to receive(:find_channel).and_return(channel)
    allow(channel.connector).to receive(:send_message).and_raise(StandardError, "send failed")

    expect do
      job.perform(
        telegram_chat_id: 123,
        telegram_user_id: 456,
        channel_id: channel.id,
        tenant_id: tenant.id,
      )
    end.not_to raise_error
  end

  it "does not raise when the fallback channel lookup returns nil after an error" do
    allow(Rails.logger).to receive(:error)
    processor = instance_double(Telegram::MessageProcessor)
    job = described_class.new

    allow(Telegram::MessageProcessor).to receive(:new).and_return(processor)
    allow(processor).to receive(:process).and_raise(StandardError, "boom")
    allow(job).to receive(:find_channel).and_return(channel, nil)

    expect do
      job.perform(
        telegram_chat_id: 123,
        telegram_user_id: 456,
        channel_id: channel.id,
        tenant_id: tenant.id,
      )
    end.not_to raise_error
  end

  it "does not raise when the fallback channel has no connector" do
    allow(Rails.logger).to receive(:error)
    processor = instance_double(Telegram::MessageProcessor)
    job = described_class.new
    channel_without_connector = build(:channel, :telegram, tenant:, connector: nil)

    allow(Telegram::MessageProcessor).to receive(:new).and_return(processor)
    allow(processor).to receive(:process).and_raise(StandardError, "boom")
    allow(job).to receive(:find_channel).and_return(channel_without_connector, channel_without_connector)

    expect do
      job.perform(
        telegram_chat_id: 123,
        telegram_user_id: 456,
        channel_id: channel.id,
        tenant_id: tenant.id,
      )
    end.not_to raise_error
  end

  it "does not process a channel outside the provided tenant" do
    allow(Rails.logger).to receive(:error)
    foreign_tenant = create(:tenant)
    allow(Telegram::MessageProcessor).to receive(:new)

    described_class.perform_now(
      telegram_chat_id: 123,
      telegram_user_id: 456,
      channel_id: channel.id,
      tenant_id: foreign_tenant.id,
    )

    expect(Telegram::MessageProcessor).not_to have_received(:new)
    expect(Rails.logger).to have_received(:error).with(/Channel not found/)
  end
end
