# frozen_string_literal: true

FactoryBot.modify do
  factory :channel do
    trait :telegram do
      channel_type { Channels::Telegram.key }
      configuration do
        {
          "welcome_message" => Channels::Telegram::DEFAULT_WELCOME_MESSAGE,
          "max_history_messages" => Channels::Telegram::DEFAULT_MAX_HISTORY,
          "streaming_enabled" => true,
        }
      end
      connector { association(:connector, :telegram, tenant:) }
    end
  end
end

FactoryBot.define do
  factory :telegram_link_request, class: "Channels::TelegramLinkRequest" do
    channel { association(:channel, :telegram) }
    user { association(:user, tenant: channel.tenant) }
    token_digest { Digest::SHA256.hexdigest(SecureRandom.alphanumeric(24)) }
  end
end
