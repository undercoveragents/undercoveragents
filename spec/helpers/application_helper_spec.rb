# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicationHelper do
  describe "#temperature_label" do
    it "returns Precise for low temperatures" do
      expect(helper.temperature_label(0.1)).to eq("Precise")
    end

    it "returns Balanced for medium temperatures" do
      expect(helper.temperature_label(0.5)).to eq("Balanced")
    end

    it "returns Creative for higher temperatures" do
      expect(helper.temperature_label(1.0)).to eq("Creative")
    end

    it "returns Experimental for very high temperatures" do
      expect(helper.temperature_label(1.5)).to eq("Experimental")
    end
  end

  describe "#render_connector_form" do
    it "returns nil when connector has no configurator" do
      connector = build(:connector, :sql_database)
      allow(connector).to receive(:configurator).and_return(nil)
      expect(helper.render_connector_form(connector)).to be_nil
    end
  end

  describe "#render_connector_show" do
    it "returns nil when connector has no configurator" do
      connector = build(:connector, :sql_database)
      allow(connector).to receive(:configurator).and_return(nil)
      expect(helper.render_connector_show(connector)).to be_nil
    end
  end

  describe "#render_channel_form" do
    it "returns nil when channel has no configurator" do
      channel = build(:channel, :client)
      allow(channel).to receive(:configurator).and_return(nil)

      expect(helper.render_channel_form(channel)).to be_nil
    end
  end

  describe "#render_channel_show" do
    it "returns nil when channel has no configurator" do
      channel = build(:channel, :client)
      allow(channel).to receive(:configurator).and_return(nil)

      expect(helper.render_channel_show(channel)).to be_nil
    end
  end

  describe "#render_connector_partial" do
    it "returns nil when connector has no configurator" do
      connector = build(:connector, :sql_database)
      allow(connector).to receive(:configurator).and_return(nil)
      expect(helper.render_connector_partial(connector, "show")).to be_nil
    end

    it "renders the named partial when configurator is present" do
      configurator = instance_double(Connectors::SqlDatabase, show_partial_path: "/fake/path")
      connector = build(:connector, :sql_database)
      allow(connector).to receive(:configurator).and_return(configurator)
      allow(helper).to receive(:render).and_return("<section>show content</section>")

      result = helper.render_connector_partial(connector, "show")
      expect(result).to eq("<section>show content</section>")
    end
  end

  describe "#render_capability_form" do
    it "returns nil when capability_config is nil" do
      expect(helper.render_capability_form(nil, capability_record: double)).to be_nil
    end

    it "renders the capability form when capability_config is present" do
      capability_config = instance_double(
        Capabilities::TitleGenerator,
        form_partial_path: "/fake/path",
        form_locals: {},
      )
      capability_record = instance_double(HasCapabilities::CapabilityEntry)

      allow(helper).to receive(:render).and_return("<form></form>")

      result = helper.render_capability_form(capability_config, capability_record:)
      expect(result).to eq("<form></form>")
    end
  end

  describe "#render_plugin_profile_panels" do
    it "returns empty safe string when no plugins provide profile panels" do
      allow(UndercoverAgents::PluginSystem.registry).to receive(:enabled).and_return([])
      result = helper.render_plugin_profile_panels(instance_double(User))
      expect(result).to eq("")
    end

    it "skips plugins with nil root_path" do
      definition = instance_double(UndercoverAgents::PluginSystem::Definition,
                                   root_path: nil,)
      allow(UndercoverAgents::PluginSystem.registry).to receive(:enabled).and_return([definition])
      result = helper.render_plugin_profile_panels(instance_double(User))
      expect(result).to eq("")
    end
  end

  describe "#theme_bootstrap_script_tag" do
    it "renders an inline bootstrap that applies the persisted theme before paint" do
      result = CGI.unescapeHTML(helper.theme_bootstrap_script_tag)

      expect(result).to include(
        "<script",
        "localStorage.getItem(\"theme\")",
        "root.classList.toggle(\"dark\", theme === \"dark\")",
        "root.style.backgroundColor = backgroundColor",
        "root.style.colorScheme = theme",
        "document.cookie = `theme=${theme}; Max-Age=31536000; Path=/; SameSite=Lax`",
        "root.dataset.themeReady = \"true\"",
      )
    end
  end

  describe "theme root helpers" do
    it "renders dark root attributes when the theme cookie is dark" do
      allow(helper).to receive(:cookies).and_return({ theme: "dark" })

      actual_root_state = [
        helper.initial_theme,
        helper.initial_theme_root_class,
        helper.initial_theme_root_data,
      ]
      expected_root_state = [
        "dark",
        "dark",
        { theme: "dark", theme_ready: "false" },
      ]

      expect(actual_root_state).to eq(expected_root_state)

      primer = CGI.unescapeHTML(helper.theme_root_primer_style_tag)
      expect(primer).to include(
        "background-color: #020617",
        "color-scheme: dark",
        "color: #f1f5f9",
        "html[data-theme-ready='false'] body { visibility: hidden; }",
      )
    end

    it "falls back to light when the theme cookie is missing" do
      allow(helper).to receive(:cookies).and_return({})

      actual_root_state = [
        helper.initial_theme,
        helper.initial_theme_root_class,
        helper.initial_theme_root_data,
      ]
      expected_root_state = [
        "light",
        nil,
        { theme: "light", theme_ready: "false" },
      ]

      expect(actual_root_state).to eq(expected_root_state)

      primer = CGI.unescapeHTML(helper.theme_root_primer_style_tag)
      expect(primer).to include(
        "background-color: #f8fafc",
        "color-scheme: light",
        "color: #0f172a",
      )
    end
  end
end
