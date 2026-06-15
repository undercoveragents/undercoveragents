# frozen_string_literal: true

# == Schema Information
#
# Table name: tenants
# Database name: primary
#
#  id          :bigint           not null, primary key
#  description :text
#  name        :string           not null
#  slug        :string           not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
# Indexes
#
#  index_tenants_on_name  (name) UNIQUE
#  index_tenants_on_slug  (slug) UNIQUE
#
class Tenant < ApplicationRecord
  extend FriendlyId

  DEFAULT_NAME = "Default Tenant"
  DEFAULT_DESCRIPTION = "Default tenant for the application workspace."
  ADMIN_PASSWORD_LENGTH = 20
  PASSWORD_UPPERCASE = ("A".."Z").to_a.freeze
  PASSWORD_LOWERCASE = ("a".."z").to_a.freeze
  PASSWORD_DIGITS = ("0".."9").to_a.freeze
  PASSWORD_SPECIALS = ["!", "@", "#", "$", "%", "^", "&", "*", "-", "_"].freeze
  PASSWORD_CHARACTERS = (PASSWORD_UPPERCASE + PASSWORD_LOWERCASE + PASSWORD_DIGITS + PASSWORD_SPECIALS).freeze

  ProvisionedAdmin = Data.define(:user, :password)

  attr_accessor :admin_email

  friendly_id :name, use: :slugged

  has_many :clients, dependent: :restrict_with_error
  has_many :channels, dependent: :restrict_with_error
  has_many :chats, dependent: :nullify
  has_many :connectors, dependent: :restrict_with_error
  has_many :cost_limits, dependent: :destroy
  has_many :api_clients, dependent: :restrict_with_error
  has_many :users, dependent: :restrict_with_error
  has_many :operations, dependent: :destroy
  has_one :system_preference, dependent: :destroy

  has_many :agents, through: :operations
  has_many :missions, through: :operations
  has_many :tools, through: :operations
  has_many :skill_catalogs, through: :operations
  has_many :rag_flows, through: :operations

  scope :ordered, -> { order(:name) }
  validates :name, presence: true, uniqueness: { case_sensitive: false }, length: { maximum: 120 }
  validates :description, length: { maximum: 500 }

  def self.default_tenant
    ordered.first || find_or_create_by!(name: DEFAULT_NAME) do |tenant|
      tenant.description = DEFAULT_DESCRIPTION
    end
  end

  def headquarter_operation
    operations.find_by(name: Operation::HEADQUARTER_NAME)
  end

  def default_operation
    operations.find_by(name: Operation::DEFAULT_NAME)
  end

  def ensure_core_resources!
    Operation.transaction do
      operations.find_or_create_by!(name: Operation::HEADQUARTER_NAME) do |operation|
        operation.description = "System operation containing built-in agents and tools."
        operation.icon = "fa-solid fa-building-shield"
        operation.system = true
      end

      operations.find_or_create_by!(name: Operation::DEFAULT_NAME) do |operation|
        operation.description = "Default workspace for your agents, missions, tools, and RAGs."
        operation.icon = "fa-solid fa-briefcase"
        operation.system = false
      end
    end

    self
  end

  def create_initial_admin!
    create_initial_admin_with_email!(email: admin_email)
  end

  def create_initial_admin_with_email!(email:)
    password = self.class.generate_admin_password(length: ADMIN_PASSWORD_LENGTH)
    user = build_initial_admin(email:, password:)
    user.save!

    ProvisionedAdmin.new(user:, password:)
  end

  def build_initial_admin(email:, password: self.class.generate_admin_password(length: ADMIN_PASSWORD_LENGTH))
    User.new(tenant: self, email:, password:, role: :admin, status: :active)
  end

  def purge!
    self.class.transaction do
      purge_primary_relations!
      system_preference&.destroy!
      purge_remaining_relations!
      destroy!
    end
  end

  def destroyable?
    users.none? &&
      connectors.none? &&
      channels.none? &&
      clients.none? &&
      api_clients.none? &&
      operations.all?(&:destroyable?)
  end

  def default_tenant?
    persisted? && id == self.class.default_tenant.id
  end

  def should_generate_new_friendly_id?
    name_changed? || slug.blank?
  end

  class << self
    def generate_admin_password(length: ADMIN_PASSWORD_LENGTH)
      required_characters = [
        random_character(PASSWORD_UPPERCASE),
        random_character(PASSWORD_LOWERCASE),
        random_character(PASSWORD_DIGITS),
        random_character(PASSWORD_SPECIALS),
      ]
      remaining_characters = Array.new(length - required_characters.length) { random_character(PASSWORD_CHARACTERS) }

      shuffle_characters(required_characters + remaining_characters)
    end

    private

    def random_character(characters)
      characters[SecureRandom.random_number(characters.length)]
    end

    def shuffle_characters(characters)
      shuffled = characters.dup

      (shuffled.length - 1).downto(1) do |index|
        swap_index = SecureRandom.random_number(index + 1)
        shuffled[index], shuffled[swap_index] = shuffled[swap_index], shuffled[index]
      end

      shuffled.join
    end
  end

  private

  def destroy_records!(relation)
    relation.reorder(nil).find_each(&:destroy!)
  end

  def purge_primary_relations!
    [
      tenant_test_suites,
      tenant_chats,
      channels,
      clients,
      skill_catalogs,
      rag_flows,
      tools,
      agents,
      missions,
      api_clients,
    ].each { |relation| destroy_records!(relation) }
  end

  def purge_remaining_relations!
    [connectors, users, operations].each { |relation| destroy_records!(relation) }
  end

  def tenant_test_suites
    TestSuite.where(agent_id: agents.select(:id))
             .or(TestSuite.where(mission_id: missions.select(:id)))
             .distinct
  end

  def tenant_chats
    base_scope = Chat.where(user_id: users.select(:id))
                     .or(Chat.where(agent_id: agents.select(:id)))
                     .or(Chat.where(mission_id: missions.select(:id)))

    Chat.where(id: base_scope.select(:id))
        .or(Chat.where(parent_chat_id: base_scope.select(:id)))
        .distinct
  end
end
