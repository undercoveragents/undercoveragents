# frozen_string_literal: true

namespace :costs do
  desc "Backfill chat cost attribution and message cost snapshots"
  task backfill: :environment do
    say = ->(message) { puts "[costs:backfill] #{message}" }
    result = Costs::Backfill.call(say:)
    say.call(
      "Done (processed #{result.processed_chats} chats / #{result.processed_messages} messages, " \
      "updated #{result.updated_chats} chats / #{result.updated_messages} messages)",
    )
  end
end
