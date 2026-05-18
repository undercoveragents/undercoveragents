# frozen_string_literal: true

require "rails_helper"

RSpec.describe ToolType do
  # Use Tools::RagQuery as a minimal concrete toolable that includes ToolType
  # and relies on the default implementations for most methods.
  let(:rag_query) { create(:tools_rag_query) }

  describe ".resolve" do
    it "returns the class for a valid type key" do
      expect(described_class.resolve("sql_query")).to eq(Tools::SqlQuery)
    end

    it "returns nil for an unknown type key" do
      expect(described_class.resolve("unknown")).to be_nil
    end
  end

  describe ".filter_type" do
    it "returns the type key for a valid key" do
      expect(described_class.filter_type("sql_query")).to eq("sql_query")
    end

    it "maps class names to type keys" do
      expect(described_class.filter_type("Tools::SqlQuery")).to eq("sql_query")
    end

    it "returns nil for an unknown key" do
      expect(described_class.filter_type("unknown")).to be_nil
    end
  end

  describe ".type_keys" do
    it "includes known registered type keys" do
      expect(described_class.type_keys).to include("sql_query", "mcp_server", "rag_query", "rag_flow")
    end
  end

  describe ".type_options" do
    it "returns [label, key] pairs for each type" do
      options = described_class.type_options
      keys = options.map(&:last)
      expect(keys).to include("sql_query", "mcp_server", "rag_query", "rag_flow")
    end
  end

  describe "default instance methods" do
    # Use the RagQuery toolable for testing defaults since it overrides fewer methods
    # than SqlQuery. We test ToolType defaults directly where RagQuery does not override.

    describe "#visibility_available? (based on schema_discovered? for rag_query)" do
      it "returns false when schema is not discovered" do
        expect(rag_query.visibility_available?).to be(false)
      end

      it "returns true when schema is discovered" do
        rag_query.update!(
          schema_discovered_at: Time.current,
          discovered_schema: { "objects" => [] },
        )
        expect(rag_query.reload.visibility_available?).to be(true)
      end
    end

    describe "#form_partial_path" do
      it "returns the type-specific form partial path" do
        expect(rag_query.form_partial_path).to eq("tools/rag_queries/form")
      end
    end

    describe "#show_partial_path" do
      it "returns the type-specific show partial path" do
        expect(rag_query.show_partial_path).to eq("tools/rag_queries/show")
      end
    end

    describe "#edit_visibility_partial_path" do
      it "returns the type-specific visibility partial path" do
        expect(rag_query.edit_visibility_partial_path).to eq("tools/rag_queries/edit_visibility")
      end
    end

    describe "ToolType::Result" do
      it "is a Data class with success? and message" do
        result = described_class::Result.new(success?: false, message: "Discovery not supported")
        expect(result.success?).to be(false)
        expect(result.message).to eq("Discovery not supported")
      end

      it "supports successful results" do
        result = described_class::Result.new(success?: true, message: "Done")
        expect(result.success?).to be(true)
      end
    end

    describe "#update_visibility! (default raises NotImplementedError)" do
      it "raises NotImplementedError because RagQuery does not override it" do
        expect { rag_query.update_visibility!({}) }.to raise_error(NotImplementedError)
      end
    end

    describe "#perform_discovery! (default)" do
      it "returns a failure Result with not-supported message via a bare toolable" do
        stub_class = Class.new do
          include ToolType

          def self.type_key = "stub_no_discovery"
          def self.type_label = "Stub"
        end

        instance = stub_class.new
        result = instance.perform_discovery!
        expect(result.success?).to be(false)
        expect(result.message).to include("Discovery not supported")
      end
    end

    describe "#visibility_available? (default)" do
      it "returns false on a bare toolable that does not override visibility_available?" do
        stub_class = Class.new do
          include ToolType

          def self.type_key = "stub_no_visibility"
          def self.type_label = "Stub"
        end

        expect(stub_class.new.visibility_available?).to be(false)
      end
    end
  end
end
