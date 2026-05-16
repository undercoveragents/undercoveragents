# frozen_string_literal: true

require "rails_helper"

RSpec.describe UndercoverAgents::PluginSystem::Configurator do
  let(:configurator_class) do
    Class.new do
      include UndercoverAgents::PluginSystem::Configurator

      attribute :name, :string
      attribute :value, :integer, default: 42

      validates :name, presence: true

      def self.name
        "TestConfigurator"
      end
    end
  end

  describe "#to_configuration" do
    it "returns a compact hash of attributes" do
      instance = configurator_class.new(name: "test", value: 10)
      expect(instance.to_configuration).to include("name" => "test", "value" => 10)
    end

    it "excludes nil values" do
      instance = configurator_class.new(name: "test", value: nil)
      config = instance.to_configuration
      expect(config).to include("name" => "test")
      expect(config).not_to have_key("value")
    end
  end

  describe "#persisted?" do
    it "returns false" do
      instance = configurator_class.new(name: "x")
      expect(instance.persisted?).to be(false)
    end
  end

  describe "#new_record?" do
    it "returns true" do
      instance = configurator_class.new(name: "x")
      expect(instance.new_record?).to be(true)
    end
  end

  describe "ActiveModel integrations" do
    it "supports validations" do
      instance = configurator_class.new(name: nil)
      expect(instance).not_to be_valid
      expect(instance.errors[:name]).to be_present
    end
  end
end
