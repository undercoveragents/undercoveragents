# frozen_string_literal: true

post "channels/telegram/:channel_id/webhook/:token", to: "telegram/webhook#receive", as: :telegram_channel_webhook

scope "/admin", as: :admin do
  resources :connectors, only: [] do
    member do
      post :fetch_bot_info, to: "telegram/admin/connectors#fetch_bot_info"
    end
  end

  resources :channels, only: [] do
    member do
      post :setup_telegram_webhook, to: "telegram/admin/channels#setup_webhook"
    end
  end
end

post "profile/telegram_channels/:channel_id/generate_link_token",
     to: "telegram/profile_links#create",
     as: :generate_telegram_channel_link_token_profile
delete "profile/telegram_channels/:channel_id/unlink",
       to: "telegram/profile_links#destroy",
       as: :unlink_telegram_channel_profile
