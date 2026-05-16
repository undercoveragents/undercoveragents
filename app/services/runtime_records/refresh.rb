# frozen_string_literal: true

module RuntimeRecords
  class Refresh
    def self.broadcast!(context:, resource:, record:, action: :update)
      new(context:, resource:, record:, action:).broadcast!
    end

    def initialize(context:, resource:, record:, action: :update)
      @context = context
      @chat = context.chat
      @ui_context = context.ui_context.is_a?(Hash) ? context.ui_context.deep_stringify_keys : {}
      @definition = Registry.fetch(resource)
      @record = record
      @action = action.to_sym
    end

    def broadcast!
      path = refresh_path
      return :skipped unless @chat&.application? && @chat.user_id.present? && path.present?

      ActionCable.server.broadcast(
        @chat.ui_stream_channel_name,
        @chat.ui_stream_payload(
          type: "refresh",
          chat_id: @chat.id,
          path:,
          current_path: current_page_path,
        ),
      )

      :broadcasted
    end

    private

    def refresh_path
      return if current_page_path.blank?

      return current_page_path if preserve_current_path?
      return canonical_record_page_path || current_page_path if refresh_current_record_page?

      nil
    end

    def preserve_current_path?
      preview_record_page? || collection_page?
    end

    def preview_record_page?
      preview_page? && refresh_current_record_page?
    end

    def refresh_current_record_page?
      @action != :delete && current_object_matches_record?
    end

    def canonical_record_page_path
      page_name = current_page_name
      return if page_name.blank?

      @definition.path_for(page_name, record: @record, context: @context)
    rescue ArgumentError
      nil
    end

    def current_page_name
      action = @ui_context.dig("page", "action").to_s

      case action
      when "index" then "index"
      when "new", "create" then "new"
      when "edit", "update" then "edit"
      when "show" then "show"
      when "designer" then "designer"
      end
    end

    def current_page_path
      @current_page_path ||= @ui_context.dig("page", "path").to_s.presence
    end

    def collection_page?
      normalize_path(current_page_path) == normalize_path(index_path)
    end

    def index_path
      @definition.path_for("index", record: nil, context: @context)
    end

    def current_object_matches_record?
      object = @ui_context["current_object"]
      return false unless object.is_a?(Hash)
      return false if @record.blank?
      return false unless object_class_names(object).intersect?(record_class_names)

      object_id = object["id"].presence
      return object_id.to_s == @record.id.to_s if object_id.present?

      return false unless object["slug"].present? && @record.respond_to?(:slug)

      object["slug"].to_s == @record.slug.to_s
    end

    def object_class_names(object)
      [object["class_name"], object["type"]].compact.to_set
    end

    def record_class_names
      [@record.class.name, @record.class.model_name.human].compact.to_set
    end

    def normalize_path(value)
      string = value.to_s
      return if string.blank?

      URI.parse(string).path.presence || "/"
    rescue URI::InvalidURIError
      string.split("?", 2).first.presence
    end

    def preview_page?
      current_page_path.to_s.include?("view=preview")
    end
  end
end
