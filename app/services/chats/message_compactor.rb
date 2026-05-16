# frozen_string_literal: true

module Chats
  # Identifies tool-result messages whose content is stale and can be replaced
  # with a short stub before shipping the chat history to the LLM. Used by
  # Chat#to_llm to rewrite their in-memory content, saving significant input
  # tokens on long, tool-heavy chats.
  #
  # Policies:
  # - :replace_by_time             → keep only the LAST tool-result for this
  #                                  tool name. Use for state-reading tools
  #                                  whose later call always supersedes earlier
  #                                  ones.
  # - :replace_by_args             → keep only the LAST tool-result per
  #                                  (tool_name, args). Dedups identical
  #                                  repeated calls. Default for unknown tools.
  # - :drop_all                    → stub ALL tool-results for this tool. Use
  #                                  for fire-and-forget workflow tools whose
  #                                  output is never needed on later turns
  #                                  (e.g. add_node, update_node).
  # - :replace_on_assistant_reply  → keep the tool-result live within the
  #                                  current user turn (everything since the
  #                                  last user-visible assistant reply) and
  #                                  stub it as soon as the assistant has
  #                                  produced a new user-visible text message.
  #                                  Ideal for read-only discovery tools whose
  #                                  result is only needed to decide the next
  #                                  tool call inside the same turn.
  # - :keep_all                    → never compact.
  #
  # Policy resolution order:
  #   1. Builtin tools:   BuiltinTools::Registry definition compaction_policy
  #   2. User-created tools: tool_record.toolable.tool_compaction_policy when
  #      the configurator exposes it (via ToolWidgetConfigurable)
  #   3. DEFAULT_POLICY
  class MessageCompactor
    DEFAULT_POLICY = :replace_by_args
    POLICIES = [
      :replace_by_time,
      :replace_by_args,
      :drop_all,
      :replace_on_assistant_reply,
      :keep_all,
    ].freeze

    STUB_CONTENT = "[Tool result omitted to save context — superseded by a later call of the same tool. " \
                   "Call the tool again if the current state is needed.]"

    def initialize(chat)
      @chat = chat
      @policy_cache = {}
    end

    # @return [Set<Integer>] AR message IDs whose content should be stubbed.
    def stale_message_ids
      groups = group_tool_messages
      stale = Set.new
      groups.each_value { |group| stale.merge(stale_ids_for_group(group)) }
      stale.merge(stale_ids_for_assistant_reply_policy)
      stale
    end

    def policy_for(tool_name)
      name = tool_name.to_s
      return @policy_cache[name] if @policy_cache.key?(name)

      @policy_cache[name] = resolve_policy(name)
    end

    private

    attr_reader :chat

    def group_tool_messages
      groups = {}
      tool_messages.each do |message|
        tool_call = message.parent_tool_call
        next unless tool_call

        policy = policy_for(tool_call.name)
        next if policy == :keep_all
        next if policy == :replace_on_assistant_reply

        key = group_key(tool_call, policy)
        groups[key] ||= { policy:, ids: [] }
        groups[key][:ids] << message.id
      end
      groups
    end

    def stale_ids_for_assistant_reply_policy
      latest_reply_id = latest_assistant_reply_id
      return [] unless latest_reply_id

      stale = []
      tool_messages.each do |message|
        tool_call = message.parent_tool_call
        next unless tool_call
        next unless policy_for(tool_call.name) == :replace_on_assistant_reply
        next unless message.id < latest_reply_id

        stale << message.id
      end
      stale
    end

    def latest_assistant_reply_id
      chat.messages
          .where(role: :assistant)
          .where.not(content: [nil, ""])
          .order(:id)
          .last&.id
    end

    def stale_ids_for_group(group)
      ids = group[:ids]
      return ids if group[:policy] == :drop_all
      return [] if ids.size <= 1

      ids[0..-2]
    end

    def tool_messages
      chat.messages.where(role: :tool).includes(:parent_tool_call).order(:id)
    end

    def group_key(tool_call, policy)
      case policy
      when :replace_by_time, :drop_all
        [tool_call.name, policy]
      else
        [tool_call.name, tool_call.arguments, policy]
      end
    end

    def resolve_policy(name)
      builtin = BuiltinTools::Registry.definition_for_runtime_name(name)
      return builtin.compaction_policy if builtin&.compaction_policy

      user_policy = user_tool_policy(name)
      return user_policy if user_policy

      DEFAULT_POLICY
    end

    def user_tool_policy(name)
      tool_record = ToolCalls::DisplayMetadataResolver.tool_record_for(name, chat:)
      return unless tool_record

      toolable = tool_record.toolable
      return unless toolable.respond_to?(:tool_compaction_policy)

      configured = toolable.tool_compaction_policy
      return if configured.blank?

      symbol = configured.to_sym
      POLICIES.include?(symbol) ? symbol : nil
    end
  end
end
