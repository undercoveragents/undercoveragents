# frozen_string_literal: true

module SkillCatalogsHelper
  def skill_catalog_skill_count_label(skill_catalog)
    count = skill_catalog.skill_count
    "#{count} #{count == 1 ? "skill" : "skills"}"
  end

  def skill_catalog_agent_count_label(skill_catalog)
    count = skill_catalog.assigned_agents_count
    "#{count} #{count == 1 ? "agent" : "agents"}"
  end

  def skill_catalog_resource_count_label(skill_catalog)
    count = skill_catalog.total_resource_count
    "#{count} #{count == 1 ? "resource" : "resources"}"
  end

  def skill_source_badge(skill)
    label, color = if skill.builtin?
                     ["Builtin", "secondary"]
                   elsif skill.imported?
                     ["Imported", "info"]
                   else
                     ["Manual", "success"]
                   end

    content_tag(:span, label, class: "badge badge-#{color} whitespace-nowrap")
  end

  def skill_warning_badge(skill)
    warnings = skill.spec_warnings
    return if warnings.empty?

    content_tag(:span, "#{warnings.size} warning#{"s" if warnings.size != 1}",
                class: "badge badge-warning whitespace-nowrap",)
  end

  def skill_resource_icon(resource)
    case resource.resource_kind
    when "scripts"
      "fa-solid fa-terminal"
    when "references"
      "fa-solid fa-book"
    when "assets"
      "fa-solid fa-photo-film"
    else
      "fa-solid fa-file"
    end
  end
end
