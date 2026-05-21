# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_05_20_140000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "vector"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "agent_memory_blocks", force: :cascade do |t|
    t.bigint "agent_id", null: false
    t.datetime "created_at", null: false
    t.bigint "memory_block_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.text "value", default: "", null: false
    t.index ["agent_id", "memory_block_id", "user_id"], name: "index_agent_memory_blocks_uniqueness", unique: true
    t.index ["agent_id"], name: "index_agent_memory_blocks_on_agent_id"
    t.index ["memory_block_id"], name: "index_agent_memory_blocks_on_memory_block_id"
    t.index ["user_id"], name: "index_agent_memory_blocks_on_user_id"
  end

  create_table "agents", force: :cascade do |t|
    t.string "agent_type"
    t.boolean "builtin", default: false, null: false
    t.jsonb "configuration", default: {}, null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "operation_id", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_type", "operation_id"], name: "index_agents_on_type_and_operation_builtin", unique: true, where: "(builtin = true)"
    t.index ["agent_type"], name: "index_agents_on_agent_type"
    t.index ["operation_id", "name"], name: "index_agents_on_operation_and_name", unique: true
    t.index ["operation_id"], name: "index_agents_on_operation_id"
    t.index ["slug"], name: "index_agents_on_slug", unique: true
  end

  create_table "api_client_missions", force: :cascade do |t|
    t.bigint "api_client_id", null: false
    t.datetime "created_at", null: false
    t.bigint "mission_id", null: false
    t.datetime "updated_at", null: false
    t.index ["api_client_id", "mission_id"], name: "index_api_client_missions_on_api_client_id_and_mission_id", unique: true
    t.index ["api_client_id"], name: "index_api_client_missions_on_api_client_id"
    t.index ["mission_id"], name: "index_api_client_missions_on_mission_id"
  end

  create_table "api_clients", force: :cascade do |t|
    t.string "access_scope", default: "all", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.boolean "enabled", default: true, null: false
    t.datetime "last_used_at"
    t.string "name", null: false
    t.bigint "tenant_id", null: false
    t.string "token_digest", null: false
    t.string "token_prefix", null: false
    t.datetime "updated_at", null: false
    t.index ["enabled"], name: "index_api_clients_on_enabled"
    t.index ["tenant_id", "name"], name: "index_api_clients_on_tenant_id_and_name", unique: true
    t.index ["tenant_id"], name: "index_api_clients_on_tenant_id"
    t.index ["token_prefix"], name: "index_api_clients_on_token_prefix", unique: true
  end

  create_table "archival_memories", force: :cascade do |t|
    t.bigint "agent_id", null: false
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.vector "embedding", limit: 1536
    t.string "tags", default: [], null: false, array: true
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["agent_id"], name: "index_archival_memories_on_agent_id"
    t.index ["tags"], name: "index_archival_memories_on_tags", using: :gin
    t.index ["user_id"], name: "index_archival_memories_on_user_id"
  end

  create_table "automation_triggers", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "cron_expression"
    t.boolean "enabled", default: true, null: false
    t.text "last_error"
    t.bigint "last_result_record_id"
    t.string "last_result_record_type"
    t.datetime "last_triggered_at"
    t.string "name", null: false
    t.datetime "next_run_at"
    t.bigint "operation_id", null: false
    t.jsonb "payload", default: {}, null: false
    t.bigint "schedulable_id", null: false
    t.string "schedulable_type", null: false
    t.string "timezone", default: "UTC", null: false
    t.string "trigger_type", null: false
    t.datetime "updated_at", null: false
    t.string "webhook_secret_digest"
    t.string "webhook_secret_prefix"
    t.index ["last_result_record_type", "last_result_record_id"], name: "index_automation_triggers_on_last_result_record"
    t.index ["operation_id"], name: "index_automation_triggers_on_operation_id"
    t.index ["schedulable_type", "schedulable_id", "name"], name: "index_automation_triggers_on_schedulable_and_name", unique: true
    t.index ["schedulable_type", "schedulable_id"], name: "index_automation_triggers_on_schedulable"
    t.index ["trigger_type", "enabled", "next_run_at"], name: "index_automation_triggers_on_schedule_state"
  end

  create_table "channel_conversations", force: :cascade do |t|
    t.bigint "channel_id", null: false
    t.bigint "channel_identity_id"
    t.bigint "channel_target_id"
    t.bigint "chat_id"
    t.datetime "created_at", null: false
    t.string "external_conversation_id", null: false
    t.string "external_thread_id", default: "", null: false
    t.jsonb "metadata", default: {}, null: false
    t.bigint "mission_run_id"
    t.datetime "updated_at", null: false
    t.index ["channel_id", "external_conversation_id", "external_thread_id"], name: "index_channel_conversations_on_external_ids", unique: true
    t.index ["channel_id"], name: "index_channel_conversations_on_channel_id"
    t.index ["channel_identity_id"], name: "index_channel_conversations_on_channel_identity_id"
    t.index ["channel_target_id"], name: "index_channel_conversations_on_channel_target_id"
    t.index ["chat_id"], name: "index_channel_conversations_on_chat_id"
    t.index ["mission_run_id"], name: "index_channel_conversations_on_mission_run_id"
  end

  create_table "channel_credentials", force: :cascade do |t|
    t.bigint "channel_id", null: false
    t.datetime "created_at", null: false
    t.string "credential_type", default: "bearer_token", null: false
    t.boolean "enabled", default: true, null: false
    t.datetime "last_used_at"
    t.jsonb "metadata", default: {}, null: false
    t.string "name", null: false
    t.string "token_digest", null: false
    t.string "token_prefix", null: false
    t.datetime "updated_at", null: false
    t.index ["channel_id", "name"], name: "index_channel_credentials_on_channel_id_and_name", unique: true
    t.index ["channel_id"], name: "index_channel_credentials_on_channel_id"
    t.index ["enabled"], name: "index_channel_credentials_on_enabled"
    t.index ["token_prefix"], name: "index_channel_credentials_on_token_prefix", unique: true
  end

  create_table "channel_identities", force: :cascade do |t|
    t.bigint "channel_id", null: false
    t.datetime "created_at", null: false
    t.string "external_user_id", null: false
    t.string "external_username"
    t.string "external_workspace_id"
    t.string "link_token_digest"
    t.datetime "linked_at"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["channel_id", "external_user_id"], name: "index_channel_identities_on_channel_id_and_external_user_id", unique: true
    t.index ["channel_id"], name: "index_channel_identities_on_channel_id"
    t.index ["external_workspace_id"], name: "index_channel_identities_on_external_workspace_id"
    t.index ["link_token_digest"], name: "index_channel_identities_on_link_token_digest", unique: true
    t.index ["user_id"], name: "index_channel_identities_on_user_id"
  end

  create_table "channel_targets", force: :cascade do |t|
    t.bigint "channel_id", null: false
    t.jsonb "configuration", default: {}, null: false
    t.datetime "created_at", null: false
    t.boolean "default", default: false, null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.string "slug", null: false
    t.bigint "target_id", null: false
    t.string "target_type", null: false
    t.datetime "updated_at", null: false
    t.index ["channel_id", "slug"], name: "index_channel_targets_on_channel_id_and_slug", unique: true
    t.index ["channel_id", "target_type", "target_id"], name: "idx_on_channel_id_target_type_target_id_7f034238bd", unique: true
    t.index ["channel_id"], name: "index_channel_targets_on_channel_id"
    t.index ["default"], name: "index_channel_targets_on_default"
    t.index ["target_type", "target_id"], name: "index_channel_targets_on_target_type_and_target_id"
  end

  create_table "channels", force: :cascade do |t|
    t.string "channel_type", null: false
    t.jsonb "configuration", default: {}, null: false
    t.bigint "connector_id"
    t.datetime "created_at", null: false
    t.boolean "default", default: false, null: false
    t.text "description"
    t.boolean "enabled", default: true, null: false
    t.string "name", null: false
    t.bigint "operation_id", null: false
    t.string "slug", null: false
    t.bigint "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["channel_type"], name: "index_channels_on_channel_type"
    t.index ["connector_id"], name: "index_channels_on_connector_id"
    t.index ["default"], name: "index_channels_on_default"
    t.index ["enabled"], name: "index_channels_on_enabled"
    t.index ["operation_id", "name"], name: "index_channels_on_operation_id_and_name", unique: true
    t.index ["operation_id"], name: "index_channels_on_operation_id"
    t.index ["slug"], name: "index_channels_on_slug", unique: true
    t.index ["tenant_id"], name: "index_channels_on_tenant_id"
  end

  create_table "chats", force: :cascade do |t|
    t.bigint "agent_id"
    t.bigint "channel_conversation_id"
    t.bigint "channel_id"
    t.bigint "channel_target_id"
    t.integer "child_chats_count", default: 0, null: false
    t.bigint "client_id"
    t.datetime "created_at", null: false
    t.string "execution_context", default: "playground", null: false
    t.integer "messages_count", default: 0, null: false
    t.bigint "mission_id"
    t.bigint "model_id"
    t.bigint "parent_chat_id"
    t.string "status", default: "idle", null: false
    t.bigint "telegram_chat_id"
    t.string "title"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["agent_id"], name: "index_chats_on_agent_id"
    t.index ["channel_conversation_id"], name: "index_chats_on_channel_conversation_id"
    t.index ["channel_id"], name: "index_chats_on_channel_id"
    t.index ["channel_target_id"], name: "index_chats_on_channel_target_id"
    t.index ["client_id"], name: "index_chats_on_client_id"
    t.index ["execution_context"], name: "index_chats_on_execution_context"
    t.index ["mission_id"], name: "index_chats_on_mission_id"
    t.index ["model_id"], name: "index_chats_on_model_id"
    t.index ["parent_chat_id"], name: "index_chats_on_parent_chat_id"
    t.index ["telegram_chat_id"], name: "index_chats_on_telegram_chat_id"
    t.index ["user_id"], name: "index_chats_on_user_id"
  end

  create_table "clients", force: :cascade do |t|
    t.bigint "agent_id", null: false
    t.jsonb "configuration", default: {}, null: false
    t.datetime "created_at", null: false
    t.boolean "default", default: false, null: false
    t.string "name", null: false
    t.string "slug"
    t.bigint "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_id"], name: "index_clients_on_agent_id"
    t.index ["default"], name: "index_clients_on_default"
    t.index ["slug"], name: "index_clients_on_slug", unique: true
    t.index ["tenant_id", "name"], name: "index_clients_on_tenant_id_and_name", unique: true
    t.index ["tenant_id"], name: "index_clients_on_tenant_id"
  end

  create_table "connectors", force: :cascade do |t|
    t.jsonb "configuration", default: {}, null: false
    t.string "connector_type", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.boolean "enabled", default: true, null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.bigint "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["connector_type"], name: "index_connectors_on_connector_type"
    t.index ["enabled"], name: "index_connectors_on_enabled"
    t.index ["slug"], name: "index_connectors_on_slug", unique: true
    t.index ["tenant_id", "name"], name: "index_connectors_on_tenant_id_and_name", unique: true
    t.index ["tenant_id"], name: "index_connectors_on_tenant_id"
  end

  create_table "memory_blocks", force: :cascade do |t|
    t.integer "char_limit", default: 5000, null: false
    t.datetime "created_at", null: false
    t.text "default_value", default: "", null: false
    t.text "description"
    t.string "label", null: false
    t.boolean "read_only", default: false, null: false
    t.datetime "updated_at", null: false
    t.index ["label"], name: "index_memory_blocks_on_label"
  end

  create_table "message_feedbacks", force: :cascade do |t|
    t.string "category"
    t.bigint "chat_id", null: false
    t.text "comment"
    t.datetime "created_at", null: false
    t.bigint "message_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.string "value", null: false
    t.index ["chat_id"], name: "index_message_feedbacks_on_chat_id"
    t.index ["message_id", "user_id"], name: "index_message_feedbacks_on_message_id_and_user_id", unique: true
    t.index ["message_id"], name: "index_message_feedbacks_on_message_id"
    t.index ["user_id"], name: "index_message_feedbacks_on_user_id"
    t.index ["value"], name: "index_message_feedbacks_on_value"
  end

  create_table "messages", force: :cascade do |t|
    t.integer "cache_creation_tokens"
    t.integer "cached_tokens"
    t.bigint "chat_id", null: false
    t.text "content"
    t.json "content_raw"
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.integer "input_tokens"
    t.bigint "model_id"
    t.integer "output_tokens"
    t.string "role", null: false
    t.text "thinking_signature"
    t.text "thinking_text"
    t.integer "thinking_tokens"
    t.bigint "tool_call_id"
    t.datetime "updated_at", null: false
    t.index ["chat_id"], name: "index_messages_on_chat_id"
    t.index ["model_id"], name: "index_messages_on_model_id"
    t.index ["role"], name: "index_messages_on_role"
    t.index ["tool_call_id"], name: "index_messages_on_tool_call_id"
  end

  create_table "mission_runs", force: :cascade do |t|
    t.bigint "api_client_id"
    t.string "callback_url"
    t.bigint "channel_conversation_id"
    t.bigint "channel_id"
    t.bigint "channel_target_id"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.string "current_node_id"
    t.text "error"
    t.jsonb "execution_state", default: {}, null: false
    t.jsonb "flow_snapshot", default: {}, null: false
    t.bigint "mission_id", null: false
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.jsonb "trigger_data", default: {}, null: false
    t.datetime "updated_at", null: false
    t.jsonb "variables", default: {}, null: false
    t.index ["api_client_id"], name: "index_mission_runs_on_api_client_id"
    t.index ["channel_conversation_id"], name: "index_mission_runs_on_channel_conversation_id"
    t.index ["channel_id"], name: "index_mission_runs_on_channel_id"
    t.index ["channel_target_id"], name: "index_mission_runs_on_channel_target_id"
    t.index ["mission_id", "status"], name: "index_mission_runs_on_mission_id_and_status"
    t.index ["mission_id"], name: "index_mission_runs_on_mission_id"
    t.index ["status"], name: "index_mission_runs_on_status"
  end

  create_table "missions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.jsonb "flow_data", default: {"edges" => [], "nodes" => []}, null: false
    t.jsonb "flow_redo_history", default: [], null: false
    t.jsonb "flow_undo_history", default: [], null: false
    t.string "name", null: false
    t.bigint "operation_id", null: false
    t.string "slug"
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_missions_on_name"
    t.index ["operation_id"], name: "index_missions_on_operation_id"
    t.index ["slug"], name: "index_missions_on_slug", unique: true
  end

  create_table "models", force: :cascade do |t|
    t.jsonb "capabilities", default: []
    t.integer "context_window"
    t.datetime "created_at", null: false
    t.string "family"
    t.date "knowledge_cutoff"
    t.integer "max_output_tokens"
    t.jsonb "metadata", default: {}
    t.jsonb "modalities", default: {}
    t.datetime "model_created_at"
    t.string "model_id", null: false
    t.string "name", null: false
    t.jsonb "pricing", default: {}
    t.string "provider", null: false
    t.datetime "updated_at", null: false
    t.index ["capabilities"], name: "index_models_on_capabilities", using: :gin
    t.index ["family"], name: "index_models_on_family"
    t.index ["modalities"], name: "index_models_on_modalities", using: :gin
    t.index ["provider", "model_id"], name: "index_models_on_provider_and_model_id", unique: true
    t.index ["provider"], name: "index_models_on_provider"
  end

  create_table "operations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "icon", default: "fa-solid fa-briefcase"
    t.string "name", null: false
    t.string "slug", null: false
    t.boolean "system", default: false, null: false
    t.bigint "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_operations_on_slug", unique: true
    t.index ["system"], name: "index_operations_on_system"
    t.index ["tenant_id", "name"], name: "index_operations_on_tenant_id_and_name", unique: true
    t.index ["tenant_id"], name: "index_operations_on_tenant_id"
  end

  create_table "plugins", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true, null: false
    t.string "identifier", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index ["identifier"], name: "index_plugins_on_identifier", unique: true
  end

  create_table "rag_flows", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "enabled", default: true, null: false
    t.string "name", null: false
    t.bigint "operation_id", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["operation_id", "name"], name: "index_rag_flows_on_operation_id_and_name", unique: true
    t.index ["operation_id"], name: "index_rag_flows_on_operation_id"
    t.index ["slug"], name: "index_rag_flows_on_slug", unique: true
  end

  create_table "rag_runs", force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.text "error_message"
    t.bigint "rag_flow_id", null: false
    t.datetime "started_at"
    t.jsonb "stats", default: {}, null: false
    t.string "status", default: "pending", null: false
    t.string "triggered_by", default: "manual", null: false
    t.datetime "updated_at", null: false
    t.index ["rag_flow_id", "status"], name: "index_rag_runs_on_rag_flow_id_and_status"
    t.index ["rag_flow_id"], name: "index_rag_runs_on_rag_flow_id"
  end

  create_table "rag_step_runs", force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.text "error_message"
    t.integer "input_count", default: 0, null: false
    t.integer "output_count", default: 0, null: false
    t.integer "position", null: false
    t.bigint "rag_run_id", null: false
    t.datetime "started_at"
    t.jsonb "stats", default: {}, null: false
    t.string "status", default: "pending", null: false
    t.string "step_type", null: false
    t.datetime "updated_at", null: false
    t.index ["rag_run_id", "step_type"], name: "idx_step_runs_on_run_and_type", unique: true
    t.index ["rag_run_id"], name: "index_rag_step_runs_on_rag_run_id"
  end

  create_table "rag_steps", force: :cascade do |t|
    t.jsonb "configuration", default: {}, null: false
    t.datetime "created_at", null: false
    t.string "module_type", null: false
    t.bigint "rag_flow_id", null: false
    t.string "stage", null: false
    t.datetime "updated_at", null: false
    t.index ["rag_flow_id", "stage"], name: "idx_rag_steps_flow_stage", unique: true
    t.index ["rag_flow_id"], name: "index_rag_steps_on_rag_flow_id"
  end

  create_table "skill_catalogs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.bigint "operation_id", null: false
    t.string "slug", null: false
    t.jsonb "source_metadata", default: {}, null: false
    t.string "source_type", default: "manual", null: false
    t.datetime "updated_at", null: false
    t.index ["operation_id", "name"], name: "index_skill_catalogs_on_operation_id_and_name", unique: true
    t.index ["operation_id"], name: "index_skill_catalogs_on_operation_id"
    t.index ["slug"], name: "index_skill_catalogs_on_slug", unique: true
  end

  create_table "skill_resources", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "relative_path", null: false
    t.string "resource_kind", default: "other", null: false
    t.bigint "skill_id", null: false
    t.datetime "updated_at", null: false
    t.index ["skill_id", "relative_path"], name: "index_skill_resources_on_skill_id_and_relative_path", unique: true
    t.index ["skill_id"], name: "index_skill_resources_on_skill_id"
  end

  create_table "skills", force: :cascade do |t|
    t.string "allowed_tools"
    t.string "compatibility"
    t.datetime "created_at", null: false
    t.text "description", null: false
    t.text "instructions"
    t.string "license"
    t.jsonb "metadata", default: {}, null: false
    t.string "name", null: false
    t.bigint "skill_catalog_id", null: false
    t.jsonb "source_metadata", default: {}, null: false
    t.string "source_type", default: "manual", null: false
    t.datetime "updated_at", null: false
    t.index ["skill_catalog_id", "name"], name: "index_skills_on_skill_catalog_id_and_name", unique: true
    t.index ["skill_catalog_id"], name: "index_skills_on_skill_catalog_id"
  end

  create_table "system_preferences", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "custom_llm_params", default: {}, null: false
    t.bigint "embedding_connector_id"
    t.string "embedding_model_id"
    t.bigint "image_connector_id"
    t.string "image_model_id"
    t.bigint "llm_connector_id"
    t.string "model_id"
    t.jsonb "model_routing_config", default: {}, null: false
    t.float "temperature"
    t.bigint "tenant_id", null: false
    t.integer "thinking_budget"
    t.string "thinking_effort"
    t.datetime "updated_at", null: false
    t.index ["tenant_id"], name: "index_system_preferences_on_tenant_id", unique: true
  end

  create_table "telegram_link_requests", force: :cascade do |t|
    t.bigint "channel_id", null: false
    t.datetime "created_at", null: false
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["channel_id", "user_id"], name: "index_telegram_link_requests_on_channel_id_and_user_id", unique: true
    t.index ["channel_id"], name: "index_telegram_link_requests_on_channel_id"
    t.index ["token_digest"], name: "index_telegram_link_requests_on_token_digest", unique: true
    t.index ["user_id"], name: "index_telegram_link_requests_on_user_id"
  end

  create_table "tenants", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_tenants_on_name", unique: true
    t.index ["slug"], name: "index_tenants_on_slug", unique: true
  end

  create_table "test_case_results", force: :cascade do |t|
    t.text "actual_answer"
    t.jsonb "actual_child_builtin_keys", default: [], null: false
    t.string "actual_status"
    t.jsonb "actual_tool_names", default: [], null: false
    t.jsonb "actual_variables", default: {}, null: false
    t.text "analysis"
    t.text "behavior_analysis"
    t.boolean "behavior_passed"
    t.bigint "chat_id"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.jsonb "debug_snapshot", default: {}, null: false
    t.integer "duration_ms"
    t.bigint "mission_run_id"
    t.boolean "passed"
    t.float "score"
    t.boolean "semantic_passed"
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.bigint "test_case_id", null: false
    t.bigint "test_suite_run_id", null: false
    t.datetime "updated_at", null: false
    t.index ["chat_id"], name: "index_test_case_results_on_chat_id"
    t.index ["mission_run_id"], name: "index_test_case_results_on_mission_run_id"
    t.index ["status"], name: "index_test_case_results_on_status"
    t.index ["test_case_id"], name: "index_test_case_results_on_test_case_id"
    t.index ["test_suite_run_id", "test_case_id"], name: "idx_test_case_results_on_run_and_case", unique: true
    t.index ["test_suite_run_id"], name: "index_test_case_results_on_test_suite_run_id"
  end

  create_table "test_cases", force: :cascade do |t|
    t.string "category"
    t.string "complexity"
    t.datetime "created_at", null: false
    t.boolean "disallow_child_chats", default: false, null: false
    t.text "expected_answer"
    t.string "expected_child_builtin_key"
    t.string "expected_status"
    t.jsonb "expected_tool_names", default: [], null: false
    t.jsonb "expected_variables", default: {}, null: false
    t.string "fixture_key"
    t.jsonb "forbidden_keywords", default: [], null: false
    t.jsonb "input_variables", default: {}, null: false
    t.string "match_type", default: "semantic", null: false
    t.string "name"
    t.integer "position", default: 0, null: false
    t.text "prompt"
    t.jsonb "required_keywords", default: [], null: false
    t.string "scenario_key"
    t.jsonb "source_metadata", default: {}, null: false
    t.string "source_type", default: "manual", null: false
    t.bigint "test_suite_id", null: false
    t.datetime "updated_at", null: false
    t.index ["scenario_key"], name: "index_test_cases_on_scenario_key"
    t.index ["source_type"], name: "index_test_cases_on_source_type"
    t.index ["test_suite_id", "position"], name: "index_test_cases_on_test_suite_id_and_position"
    t.index ["test_suite_id", "scenario_key"], name: "index_test_cases_on_suite_and_scenario_key", unique: true, where: "(scenario_key IS NOT NULL)"
    t.index ["test_suite_id"], name: "index_test_cases_on_test_suite_id"
  end

  create_table "test_suite_runs", force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.jsonb "debug_snapshot", default: {}, null: false
    t.integer "duration_ms"
    t.integer "error_count", default: 0, null: false
    t.integer "failed_count", default: 0, null: false
    t.integer "passed_count", default: 0, null: false
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.bigint "test_suite_id", null: false
    t.integer "total_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["status"], name: "index_test_suite_runs_on_status"
    t.index ["test_suite_id", "created_at"], name: "index_test_suite_runs_on_test_suite_id_and_created_at"
    t.index ["test_suite_id"], name: "index_test_suite_runs_on_test_suite_id"
    t.index ["user_id"], name: "index_test_suite_runs_on_user_id"
  end

  create_table "test_suites", force: :cascade do |t|
    t.bigint "agent_id"
    t.datetime "created_at", null: false
    t.text "description"
    t.bigint "evaluation_llm_connector_id"
    t.string "evaluation_model_id"
    t.float "evaluation_temperature", default: 0.7, null: false
    t.bigint "mission_id"
    t.string "name", null: false
    t.string "slug"
    t.jsonb "source_metadata", default: {}, null: false
    t.string "source_type", default: "manual", null: false
    t.string "status", default: "active", null: false
    t.string "suite_type", default: "agent", null: false
    t.datetime "updated_at", null: false
    t.index "((source_metadata ->> 'builtin_key'::text))", name: "index_test_suites_on_builtin_key", where: "((source_type)::text = 'builtin'::text)"
    t.index ["agent_id"], name: "index_test_suites_on_agent_id"
    t.index ["evaluation_llm_connector_id"], name: "index_test_suites_on_evaluation_llm_connector_id"
    t.index ["mission_id"], name: "index_test_suites_on_mission_id"
    t.index ["name"], name: "index_test_suites_on_name"
    t.index ["slug"], name: "index_test_suites_on_slug", unique: true
    t.index ["source_type"], name: "index_test_suites_on_source_type"
  end

  create_table "tool_calls", force: :cascade do |t|
    t.jsonb "arguments", default: {}
    t.datetime "created_at", null: false
    t.string "display_name"
    t.integer "duration_ms"
    t.string "icon"
    t.bigint "message_id", null: false
    t.string "name", null: false
    t.string "thought_signature"
    t.string "tool_call_id", null: false
    t.datetime "updated_at", null: false
    t.index ["message_id"], name: "index_tool_calls_on_message_id"
    t.index ["name"], name: "index_tool_calls_on_name"
    t.index ["tool_call_id"], name: "index_tool_calls_on_tool_call_id", unique: true
  end

  create_table "tools", force: :cascade do |t|
    t.jsonb "configuration", default: {}, null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.boolean "enabled", default: true, null: false
    t.string "name", null: false
    t.bigint "operation_id", null: false
    t.string "slug", null: false
    t.string "tool_type", null: false
    t.datetime "updated_at", null: false
    t.index ["enabled"], name: "index_tools_on_enabled"
    t.index ["operation_id", "name"], name: "index_tools_on_operation_id_and_name", unique: true
    t.index ["operation_id"], name: "index_tools_on_operation_id"
    t.index ["slug"], name: "index_tools_on_slug", unique: true
    t.index ["tool_type"], name: "index_tools_on_tool_type"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "password_digest"
    t.string "provider"
    t.string "role", default: "user", null: false
    t.string "status", default: "active", null: false
    t.string "telegram_link_token"
    t.bigint "telegram_user_id"
    t.string "telegram_username"
    t.bigint "tenant_id", null: false
    t.string "uid"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["provider", "uid"], name: "index_users_on_provider_and_uid", unique: true, where: "(provider IS NOT NULL)"
    t.index ["role"], name: "index_users_on_role"
    t.index ["telegram_link_token"], name: "index_users_on_telegram_link_token", unique: true, where: "(telegram_link_token IS NOT NULL)"
    t.index ["telegram_user_id"], name: "index_users_on_telegram_user_id", unique: true, where: "(telegram_user_id IS NOT NULL)"
    t.index ["tenant_id"], name: "index_users_on_tenant_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "agent_memory_blocks", "agents"
  add_foreign_key "agent_memory_blocks", "memory_blocks"
  add_foreign_key "agent_memory_blocks", "users"
  add_foreign_key "agents", "operations"
  add_foreign_key "api_client_missions", "api_clients"
  add_foreign_key "api_client_missions", "missions"
  add_foreign_key "api_clients", "tenants"
  add_foreign_key "archival_memories", "agents"
  add_foreign_key "archival_memories", "users"
  add_foreign_key "automation_triggers", "operations"
  add_foreign_key "channel_conversations", "channel_identities"
  add_foreign_key "channel_conversations", "channel_targets"
  add_foreign_key "channel_conversations", "channels"
  add_foreign_key "channel_conversations", "chats"
  add_foreign_key "channel_conversations", "mission_runs"
  add_foreign_key "channel_credentials", "channels"
  add_foreign_key "channel_identities", "channels"
  add_foreign_key "channel_identities", "users"
  add_foreign_key "channel_targets", "channels"
  add_foreign_key "channels", "connectors"
  add_foreign_key "channels", "operations"
  add_foreign_key "channels", "tenants"
  add_foreign_key "chats", "agents"
  add_foreign_key "chats", "channel_conversations"
  add_foreign_key "chats", "channel_targets"
  add_foreign_key "chats", "channels"
  add_foreign_key "chats", "chats", column: "parent_chat_id"
  add_foreign_key "chats", "clients"
  add_foreign_key "chats", "missions"
  add_foreign_key "chats", "models"
  add_foreign_key "chats", "users"
  add_foreign_key "clients", "agents"
  add_foreign_key "clients", "tenants"
  add_foreign_key "connectors", "tenants"
  add_foreign_key "message_feedbacks", "chats"
  add_foreign_key "message_feedbacks", "messages"
  add_foreign_key "message_feedbacks", "users"
  add_foreign_key "messages", "chats"
  add_foreign_key "messages", "models"
  add_foreign_key "messages", "tool_calls"
  add_foreign_key "mission_runs", "api_clients"
  add_foreign_key "mission_runs", "channel_conversations"
  add_foreign_key "mission_runs", "channel_targets"
  add_foreign_key "mission_runs", "channels"
  add_foreign_key "mission_runs", "missions"
  add_foreign_key "missions", "operations"
  add_foreign_key "operations", "tenants"
  add_foreign_key "rag_flows", "operations"
  add_foreign_key "rag_runs", "rag_flows"
  add_foreign_key "rag_step_runs", "rag_runs"
  add_foreign_key "rag_steps", "rag_flows"
  add_foreign_key "skill_catalogs", "operations"
  add_foreign_key "skill_resources", "skills"
  add_foreign_key "skills", "skill_catalogs"
  add_foreign_key "system_preferences", "connectors", column: "embedding_connector_id"
  add_foreign_key "system_preferences", "connectors", column: "image_connector_id"
  add_foreign_key "system_preferences", "connectors", column: "llm_connector_id"
  add_foreign_key "system_preferences", "tenants"
  add_foreign_key "telegram_link_requests", "channels"
  add_foreign_key "telegram_link_requests", "users"
  add_foreign_key "test_case_results", "chats"
  add_foreign_key "test_case_results", "mission_runs"
  add_foreign_key "test_case_results", "test_cases"
  add_foreign_key "test_case_results", "test_suite_runs"
  add_foreign_key "test_cases", "test_suites"
  add_foreign_key "test_suite_runs", "test_suites"
  add_foreign_key "test_suite_runs", "users"
  add_foreign_key "test_suites", "agents"
  add_foreign_key "test_suites", "connectors", column: "evaluation_llm_connector_id"
  add_foreign_key "test_suites", "missions"
  add_foreign_key "tool_calls", "messages"
  add_foreign_key "tools", "operations"
  add_foreign_key "users", "tenants"
end
