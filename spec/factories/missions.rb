# frozen_string_literal: true

# == Schema Information
#
# Table name: missions
# Database name: primary
#
#  id                :bigint           not null, primary key
#  description       :text
#  flow_data         :jsonb            not null
#  flow_redo_history :jsonb            not null
#  flow_undo_history :jsonb            not null
#  name              :string           not null
#  slug              :string
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  operation_id      :bigint           not null
#
# Indexes
#
#  index_missions_on_name          (name)
#  index_missions_on_operation_id  (operation_id)
#  index_missions_on_slug          (slug) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (operation_id => operations.id)
#
FactoryBot.define do
  factory :mission do
    operation { OperationFactoryHelper.default_operation }
    sequence(:name) { |n| "Mission #{n}" }
    description { "A test mission" }
    flow_data { { "nodes" => [], "edges" => [] } }
  end
end
