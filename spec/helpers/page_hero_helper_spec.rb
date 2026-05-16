# frozen_string_literal: true

require "rails_helper"

RSpec.describe PageHeroHelper do
  describe "#build_page_hero" do
    context "with dashboard presentation data" do
      subject(:hero) { helper.build_page_hero(**hero_attributes) }

      let(:hero_attributes) do
        {
          title: ["Progressive disclosure,", " ", "curated for your operation"],
          description: "Keep the base prompt lean.",
          variant: :dashboard,
          theme: :skills,
          eyebrow: { label: "Skills", icon: "fa-solid fa-book-open" },
          back_link: { label: "Back", url: "/admin/skill_catalogs" },
          meta: ["Preview", "Shared"],
          actions: [
            { label: "New", url: "/new", icon: "fa-solid fa-plus", style: :primary },
            { label: "Import", url: "/import", icon: "fa-solid fa-upload" },
            {
              label: "Delete",
              url: "/delete",
              icon: "fa-solid fa-trash",
              style: :danger_outline,
              method: :delete,
              params: { force: true },
              data: { turbo: false },
              title: "Delete now",
              disabled: true,
            },
            { label: "Custom", url: "/custom", style: "btn btn-link", method: :get },
          ],
        }
      end

      it "builds the top-level hero state" do
        expected_root_classes = [
          "page-hero",
          "page-hero--dashboard",
          "page-hero--skills",
          "page-hero--sticky",
          "page-hero--has-panel",
        ].join(" ")

        expect(hero).to have_attributes(
          variant: :dashboard,
          theme: "skills",
          description: "Keep the base prompt lean.",
          meta: ["Preview", "Shared"],
        )
        expect(hero.root_classes).to eq(expected_root_classes)
        expect(hero.eyebrow).to have_attributes(label: "Skills", icon: "fa-solid fa-book-open")
        expect(hero.back_link).to have_attributes(label: "Back", url: "/admin/skill_catalogs")
        expect(hero.title_icon).to be_nil
      end

      it "derives the compact header label and icon from the dashboard eyebrow" do
        expect(hero.header_title).to eq("Skills")
        expect(hero.header_icon).to eq("fa-solid fa-book-open")
      end

      it "tracks visible panel sections" do
        expect(hero.panel?).to be(true)
        expect(hero.actions?).to be(true)
        expect(hero.meta?).to be(true)
      end

      it "normalizes title lines" do
        expect(hero.title_lines).to eq(["Progressive disclosure, curated for your operation"])
      end

      it "keeps delete actions separate and moves the primary action to the end" do
        expect(hero.actions.map(&:label)).to eq(
          [
            "Delete",
            "Import",
            "Custom",
            "New",
          ],
        )
        expect(hero.action_groups.map { |group| group.map(&:label) }).to eq(
          [
            ["Back"],
            ["Delete"],
            ["Import", "Custom"],
            ["New"],
          ],
        )
      end

      it "normalizes action styles and payloads" do
        expect(hero.actions.map(&:button_classes)).to eq(
          [
            "btn btn-danger-outline opacity-50 cursor-not-allowed pointer-events-none",
            "btn btn-secondary",
            "btn btn-link",
            "btn btn-primary",
          ],
        )
        expect(hero.actions.map(&:non_get?)).to eq([true, false, false, false])
        expect(hero.actions.second).to have_attributes(params: {}, data: {})
        expect(hero.actions.first).to have_attributes(
          http_method: :delete,
          params: { force: true },
          data: { turbo: false },
          title: "Delete now",
          disabled: true,
        )
      end
    end

    context "with blank optional fields" do
      subject(:hero) do
        helper.build_page_hero(
          title: ["Edit", "", "Skill"],
          description: " ",
          eyebrow: "",
        )
      end

      it "drops blank optional copy" do
        expect(hero.theme).to be_nil
        expect(hero.eyebrow).to be_nil
        expect(hero.back_link).to be_nil
        expect(hero.description).to be_nil
        expect(hero.title_lines).to eq(["Edit Skill"])
      end

      it "uses balanced defaults for the root classes" do
        expect(hero.variant).to eq(:balanced)
        expect(hero.root_classes).to eq("page-hero page-hero--balanced page-hero--sticky page-hero--no-panel")
      end

      it "reports that no panel sections are present" do
        expect(hero.panel?).to be(false)
        expect(hero.actions?).to be(false)
        expect(hero.meta?).to be(false)
      end

      it "returns nil for the header icon when neither title nor eyebrow icons are present" do
        expect(hero.header_icon).to be_nil
      end
    end

    context "with ignored legacy stats options" do
      subject(:hero) do
        helper.build_page_hero(
          title: "Import Skill",
          eyebrow: "Skills",
          stats: [{ label: "Uploads", value: "ZIP" }],
          stats_style: :compact,
        )
      end

      it "accepts string eyebrows and ignores counter data" do
        expect(hero.eyebrow).to have_attributes(label: "Skills", icon: nil)
        expect(hero.title_lines).to eq(["Import Skill"])
        expect(hero.panel?).to be(false)
        expect(hero.actions).to eq([])
      end
    end

    context "with a dashboard hero that omits the eyebrow" do
      subject(:hero) do
        helper.build_page_hero(
          title: "Agents",
          variant: :dashboard,
          title_icon: "fa-solid fa-user-secret",
        )
      end

      it "falls back to the normalized title and title icon" do
        expect(hero.header_title).to eq("Agents")
        expect(hero.header_icon).to eq("fa-solid fa-user-secret")
      end
    end

    context "with an eyebrow icon on a non-dashboard hero" do
      subject(:hero) do
        helper.build_page_hero(
          title: "Reference",
          eyebrow: { label: "Skills", icon: "fa-solid fa-book-open" },
        )
      end

      it "uses the eyebrow icon when no compact title icon is provided" do
        expect(hero.header_icon).to eq("fa-solid fa-book-open")
      end
    end

    context "with no available header icon" do
      subject(:hero) do
        helper.build_page_hero(
          title: "Reference",
          eyebrow: "Skills",
        )
      end

      it "returns nil for the header icon" do
        expect(hero.header_icon).to be_nil
      end
    end

    context "with a compact internal-page hero" do
      subject(:hero) do
        helper.build_page_hero(
          title: "Edit Skill",
          variant: :compact,
          theme: :skills,
          title_icon: "fa-solid fa-sparkles",
          record_title: "Lead Routing",
          back_link: { label: "Back to Catalog", url: "/admin/skill_catalogs/example" },
          actions: [{ label: "Edit", url: "/edit", style: :secondary }],
        )
      end

      it "captures the compact title icon and record title" do
        expect(hero.title_icon).to eq("fa-solid fa-sparkles")
        expect(hero.header_title).to eq("Edit Skill")
        expect(hero.header_icon).to eq("fa-solid fa-sparkles")
        expect(hero.record_title).to eq("Lead Routing")
        expect(hero.back_link).to have_attributes(label: "Back to Catalog", url: "/admin/skill_catalogs/example")
      end

      it "adds compact panel classes to the root" do
        expected_root_classes = [
          "page-hero",
          "page-hero--compact",
          "page-hero--skills",
          "page-hero--sticky",
          "page-hero--has-panel",
        ].join(" ")

        expect(hero.root_classes).to eq(expected_root_classes)
        expect(hero.panel?).to be(true)
        expect(hero.actions.map(&:button_classes)).to eq(["btn btn-primary"])
        expect(hero.action_groups.map { |group| group.map(&:label) }).to eq([["Back to Catalog"], ["Edit"]])
      end
    end

    context "with a header submit action" do
      subject(:hero) do
        helper.build_page_hero(
          title: "New Agent",
          variant: :compact,
          actions: [helper.page_hero_form_action(label: "Create Agent", form_id: "agent-form")],
        )
      end

      it "tracks form-backed submit buttons as header actions" do
        expect(hero.root_classes).to eq("page-hero page-hero--compact page-hero--sticky page-hero--has-panel")
        expect(hero.actions.first).to have_attributes(
          label: "Create Agent",
          url: nil,
          form_id: "agent-form",
        )
        expect(hero.actions.first.form_submit?).to be(true)
        expect(hero.actions.first.non_get?).to be(false)
        expect(hero.actions.first.button_classes).to eq("btn btn-primary")
      end
    end

    context "with an explicit sticky option" do
      subject(:hero) do
        helper.build_page_hero(
          title: "Dashboard",
          variant: :compact,
          sticky: true,
        )
      end

      it "marks the hero as sticky without requiring a form action" do
        expect(hero.sticky?).to be(true)
        expect(hero.root_classes).to eq("page-hero page-hero--compact page-hero--sticky page-hero--no-panel")
      end
    end

    context "with an explicit sticky opt-out" do
      subject(:hero) do
        helper.build_page_hero(
          title: "Static Header",
          variant: :compact,
          sticky: false,
        )
      end

      it "allows callers to disable sticky behavior explicitly" do
        expect(hero.sticky?).to be(false)
        expect(hero.root_classes).to eq("page-hero page-hero--compact page-hero--no-panel")
      end
    end

    context "with multiple explicit primary actions" do
      subject(:hero) do
        helper.build_page_hero(
          title: "Edit Skill",
          actions: [
            { label: "Delete", url: "/delete", style: :danger_outline, method: :delete },
            { label: "Edit", url: "/edit", style: :primary },
            { label: "Duplicate", url: "/duplicate", style: :primary },
          ],
        )
      end

      it "keeps only the first remaining action primary" do
        expect(hero.actions.map(&:button_classes)).to eq(
          [
            "btn btn-danger-outline",
            "btn btn-secondary",
            "btn btn-primary",
          ],
        )
      end
    end

    context "with only non-promotable actions" do
      subject(:hero) do
        helper.build_page_hero(
          title: "Reference",
          actions: [{ label: "Docs", url: "/docs", style: "btn btn-link" }],
        )
      end

      it "leaves custom action styles untouched when no action can be promoted" do
        expect(hero.actions.map(&:button_classes)).to eq(["btn btn-link"])
      end
    end

    context "with a blank title" do
      subject(:hero) { helper.build_page_hero(title: ["", "   "]) }

      it "returns no title lines" do
        expect(hero.title_lines).to eq([])
      end
    end
  end

  describe "#render_page_hero" do
    before do
      helper.singleton_class.include(PageHeroRenderHelper)
    end

    it "renders a page hero built from merged options" do
      hero_options = Struct.new(:attributes) do
        def to_h = attributes
      end.new({ variant: :compact })

      render_arguments = nil
      allow(helper).to receive(:render) do |**kwargs|
        render_arguments = kwargs
        "rendered-hero"
      end

      result = helper.render_page_hero(hero_options, title: "Explicit", theme: :skills)

      expect(result).to eq("rendered-hero")
      expect(render_arguments[:partial]).to eq("shared/page_hero/hero")

      hero = render_arguments.dig(:locals, :hero)
      expect(hero).to have_attributes(variant: :compact, theme: "skills")
      expect(hero.title_lines).to eq(["Explicit"])
    end

    it "uses the title from the source options object when no explicit title is given" do
      hero_options = Struct.new(:attributes) do
        def to_h = attributes
      end.new({ title: "Fallback", variant: :compact })

      render_arguments = nil
      allow(helper).to receive(:render) do |**kwargs|
        render_arguments = kwargs
        "rendered-hero"
      end

      helper.render_page_hero(hero_options, theme: :skills)

      hero = render_arguments.dig(:locals, :hero)
      expect(hero).to have_attributes(variant: :compact, theme: "skills")
      expect(hero.title_lines).to eq(["Fallback"])
    end

    it "supports direct keyword arguments without a source hash" do
      render_arguments = nil
      allow(helper).to receive(:render) do |**kwargs|
        render_arguments = kwargs
        "rendered-hero"
      end

      helper.render_page_hero(title: "Simple Hero", variant: :compact)

      hero = render_arguments.dig(:locals, :hero)
      expect(hero).to have_attributes(variant: :compact, theme: nil)
      expect(hero.title_lines).to eq(["Simple Hero"])
    end

    it "ignores non-convertible source objects" do
      render_arguments = nil
      allow(helper).to receive(:render) do |**kwargs|
        render_arguments = kwargs
        "rendered-hero"
      end

      helper.render_page_hero(Object.new, title: "Object Hero", variant: :compact)

      hero = render_arguments.dig(:locals, :hero)
      expect(hero).to have_attributes(variant: :compact, theme: nil)
      expect(hero.title_lines).to eq(["Object Hero"])
    end
  end
end
