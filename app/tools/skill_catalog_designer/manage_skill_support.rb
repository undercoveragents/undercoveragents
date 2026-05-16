# frozen_string_literal: true

module SkillCatalogDesigner
  module ManageSkillSupport
    private

    def success_message(skill:, action:, refreshed:)
      [
        "Skill #{action}d successfully.",
        "- Skill: #{skill.name} (`#{skill.id}`)",
        "- Catalog: #{skill.skill_catalog.name} (`#{skill.skill_catalog.id}`)",
        ("Current page refresh started to show the saved skill catalog." if refreshed),
      ].compact.join("\n")
    end

    def assign_skill_attributes(skill, attributes)
      skill.assign_attributes(attributes.slice(*skill_attribute_keys))
      skill.metadata = normalized_metadata(attributes["metadata"]) if attributes.key?("metadata")
    end

    def apply_resource_updates(skill, attributes)
      remove_selected_resources(skill, attributes["remove_resource_ids"]) if attributes.key?("remove_resource_ids")
      return unless boolean(attributes["use_current_message_attachments"])

      add_current_message_attachments(skill, attributes["resource_directory"])
    end

    def remove_selected_resources(skill, raw_resource_ids)
      resource_ids = Array(raw_resource_ids).compact_blank.map(&:to_i)
      return if resource_ids.empty?

      skill.skill_resources.where(id: resource_ids).destroy_all
    end

    def add_current_message_attachments(skill, resource_directory)
      attachments = latest_user_attachments
      raise ArgumentError, "No file attachment is available on the latest user message." if attachments.empty?

      directory = sanitize_resource_directory(resource_directory)

      attachments.each do |attachment|
        relative_path = [directory.presence, attachment.blob.filename.to_s].compact.join("/")
        resource = skill.skill_resources.find_or_initialize_by(relative_path:)
        resource.file.attach(attachment.blob)
        resource.save!
      end
    end

    def normalize_attributes(value)
      normalized = parse_hash(value)
      if normalized.key?("remove_resource_ids")
        normalized["remove_resource_ids"] = Array(normalized["remove_resource_ids"]).compact_blank
      end

      unknown_keys = normalized.keys - MANAGE_SKILL_ATTRIBUTE_KEYS
      raise ArgumentError, "Unknown skill attributes: #{unknown_keys.join(", ")}" if unknown_keys.any?

      normalized
    end

    def parse_hash(value)
      case value
      when nil
        {}
      when ActionController::Parameters
        value.to_unsafe_h.stringify_keys
      when Hash
        value.stringify_keys
      when String
        stripped = value.strip
        return {} if stripped.empty?

        parsed = JSON.parse(stripped)
        raise ArgumentError, "Expected attributes to be a JSON object." unless parsed.is_a?(Hash)

        parsed.stringify_keys
      else
        raise ArgumentError, "Expected attributes to be a hash or JSON object string."
      end
    end

    def normalized_metadata(value)
      case value
      when nil
        {}
      when ActionController::Parameters
        value.to_unsafe_h
      when Hash
        value
      when String
        stripped = value.strip
        return {} if stripped.empty?

        parsed = JSON.parse(stripped)
        raise ArgumentError, "Expected metadata to be a JSON object." unless parsed.is_a?(Hash)

        parsed
      else
        raise ArgumentError, "Expected metadata to be a hash or JSON object string."
      end
    end

    def sanitize_resource_directory(value)
      value.to_s.tr("\\", "/").squeeze("/").gsub(%r{\A/+|/+$}, "")
    end

    def restored_builtin_skill(skill)
      restored_catalog = tenant.headquarter_operation.skill_catalogs.builtin
                               .where("source_metadata ->> 'builtin_key' = ?", skill.skill_catalog.builtin_key)
                               .first!

      restored_catalog.skills.builtin.where("source_metadata ->> 'builtin_key' = ?", skill.builtin_key).first!
    end

    def skill_attribute_keys
      SkillCatalogDesigner::READ_SKILL_EDITABLE_FIELDS
    end

    def boolean(value)
      ActiveModel::Type::Boolean.new.cast(value)
    end

    def tenant
      @runtime_context&.tenant ||
        current_skill_catalog_tenant ||
        current_skill_operation&.tenant ||
        Current.tenant ||
        Tenant.default_tenant
    end

    def current_skill_operation
      current_skill&.skill_catalog&.operation
    end

    def current_skill_catalog_tenant
      @current_skill_catalog&.operation&.tenant
    end

    def unknown_action_message(action)
      "Error: Unknown action '#{action}'. Use create, update, delete, restore, or import."
    end
  end
end
