# frozen_string_literal: true

namespace :costs do
  desc "Backfill chat cost attribution and message cost snapshots"
  task backfill: :environment do
    say = ->(message) { puts "[costs:backfill] #{message}" }

    say.call "Backfilling chat tenant/operation attribution"
    Chat.find_each do |chat|
      chat.valid?
      chat.save! if chat.tenant_id_changed? || chat.operation_id_changed?
    end

    say.call "Backfilling message cost snapshots"
    Message.includes(:model, chat: :model).find_each do |message|
      Costs::MessageCostSnapshotter.call(message)
      message.save! if message.changed?
    end

    say.call "Done"
  end
end
