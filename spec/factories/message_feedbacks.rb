# frozen_string_literal: true

# == Schema Information
#
# Table name: message_feedbacks
# Database name: primary
#
#  id         :bigint           not null, primary key
#  category   :string
#  comment    :text
#  value      :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  chat_id    :bigint           not null
#  message_id :bigint           not null
#  user_id    :bigint           not null
#
# Indexes
#
#  index_message_feedbacks_on_chat_id                 (chat_id)
#  index_message_feedbacks_on_message_id              (message_id)
#  index_message_feedbacks_on_message_id_and_user_id  (message_id,user_id) UNIQUE
#  index_message_feedbacks_on_user_id                 (user_id)
#  index_message_feedbacks_on_value                   (value)
#
# Foreign Keys
#
#  fk_rails_...  (chat_id => chats.id)
#  fk_rails_...  (message_id => messages.id)
#  fk_rails_...  (user_id => users.id)
#
FactoryBot.define do
  factory :message_feedback do
    message { association(:message, :assistant) }
    chat { message.chat }
    user { message.chat.user || association(:user) }
    value { "positive" }
    category { nil }
    comment { nil }

    trait :negative do
      value { "negative" }
      category { "incorrect" }
      comment { "The answer was incorrect." }
    end
  end
end
