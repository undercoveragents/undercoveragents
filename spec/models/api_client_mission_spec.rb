# frozen_string_literal: true

# == Schema Information
#
# Table name: api_client_missions
# Database name: primary
#
#  id            :bigint           not null, primary key
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  api_client_id :bigint           not null
#  mission_id    :bigint           not null
#
# Indexes
#
#  index_api_client_missions_on_api_client_id                 (api_client_id)
#  index_api_client_missions_on_api_client_id_and_mission_id  (api_client_id,mission_id) UNIQUE
#  index_api_client_missions_on_mission_id                    (mission_id)
#
# Foreign Keys
#
#  fk_rails_...  (api_client_id => api_clients.id)
#  fk_rails_...  (mission_id => missions.id)
#
require "rails_helper"

RSpec.describe ApiClientMission do
  describe "associations" do
    it { is_expected.to belong_to(:api_client) }
    it { is_expected.to belong_to(:mission) }
  end

  describe "validations" do
    subject { create(:api_client_mission) }

    it { is_expected.to validate_uniqueness_of(:mission_id).scoped_to(:api_client_id) }
  end
end
