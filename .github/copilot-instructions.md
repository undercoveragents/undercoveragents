# Undercover Agents — Copilot Instructions

## Overview

AI Platform built with **Ruby 4.0.4 / Rails 8.1**, Falcon server, PostgreSQL, Haml views, Tailwind CSS v4, simple_form, Importmap + Hotwire (Turbo + Stimulus).

> **Always update this file and README.md** when adding new conventions, patterns, dependencies, or architectural decisions.

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Server | Falcon (async, `falcon-rails` gem) |
| CSS | Tailwind CSS v4, native nesting, modular files in `app/assets/tailwind/` |
| Views | Haml only — **never ERB** |
| Icons | Font Awesome 6 Free (CDN) — never hardcoded SVGs |
| Forms | simple_form |
| Dropdowns | Choices.js v11 — all `<select>` elements |
| Email | Resend SMTP in production, `letter_opener_web` in development, `:test` in test |
| Auth | bcrypt + `has_secure_password`, OmniAuth (Keycloak, Google), Pundit 2.5 |
| Friendly URLs | friendly_id 5.x (connectors, agents, tools) |
| Jobs | Solid Queue + Mission Control Jobs (`/jobs`) |
| Error tracking | Sentry Rails SDK (`sentry-ruby`, `sentry-rails`) with GlitchTip via `SENTRY_DSN` in production only |
| Misc | amoeba (deep cloning), Chartkick + Groupdate, rubyzip, stream-markdown-parser, pnpm |
| Marketing | VitePress site under `website/` |

## Marketing Website

- The public marketing site lives under `website/` and uses VitePress.
- Keep it dark-only and visually aligned with the app's cyan, cobalt, ink, and amber language instead of default VitePress styling.
- Deploy the marketing site as a separate Railway service via `website/Dockerfile`; do not replace Rails root routes just to serve the homepage.
- Keep website CTAs simple and hand off hosted signup to the Rails app's public `/try-in-cloud` flow instead of rebuilding tenant onboarding logic inside VitePress.
- The website runtime supports `WEBSITE_COMING_SOON=true`, which makes the Node static server answer every HTML route with the minimal logo/title coming-soon page while still serving static assets like the logo image.

## JavaScript Dependency Split

- The main Rails app ships browser JavaScript through Importmap and vendored files under `config/importmap.rb` and `vendor/javascript/`.
- Root `package.json` is only for Node-driven tooling and bundles, currently the mission designer React/esbuild pipeline and the VitePress marketing site.
- Do not add Importmap-only browser libraries to `package.json` unless a Node build or Node-based tool in this repo also imports them directly.

## Code Style

### Ruby
- `# frozen_string_literal: true` at top of every file.
- **Double quotes**, bracket array notation, trailing commas in multiline structures, Ruby 3.x hash shorthand (`{ x:, y: }`).
- Max: 120 chars/line, 20 lines/method, 150 lines/class. Follow `.rubocop.yml`.

### Views
- Haml only. Tailwind utility classes. `simple_form_for` for forms. FA Free icons only.
- Max 150 lines per template — extract partials. Use `#{expr}` interpolation.
- Haml `:ruby` filters are forbidden. Move setup into helpers or partials, and use plain Haml silent script lines only for small, local glue code.
- Destructive actions use `confirm` Stimulus controller.
- Semantic color classes: `bg-surface-card`, `text-text-primary` — never `bg-bg-*`.
- Shared admin and tooling surfaces use a compact density scale; prefer shared CSS primitives and modest spacing over large one-off paddings, margins, and headline sizes.
- Operation-owned agent and tool show pages should expose one-click Clone page-hero actions when the record supports cloning, and those clone buttons should use the shared `confirm` Stimulus dialog before posting. Mission cloning belongs in the mission designer properties tab rather than the edit page. Route all agent/tool/mission cloning through a shared clone service, keep cloned missions on the current workflow with reset undo/redo history, and use the same policy tooltip behavior when clone actions are disabled.
- The shared admin layout includes a shared right-side panel sidebar. Keep the shell mounted once in the admin layout, render Agent Alpha as the always-available `assistant` panel, lazy-load it from the dedicated `admin/agent_alpha` route, and keep only the inner assistant frame persistent with `data-turbo-permanent`; do not make the main admin sidebar or the shared panel-shell root permanent because their active-link, operation-switcher, and page-specific panel sets must still re-render on navigation. Agent Alpha itself should not mount a live `turbo_stream_from` subscription inside that preserved frame; on Falcon plus `actioncable-next`, page navigation can duplicate subscriptions and stall streaming. Use the generic `chat-stream` Stimulus controller and `ChatStreamChannel` JSON payloads for every live chat surface, including the preserved Agent Alpha panel and standard chat pages. Keep the rendering/state helper under `app/javascript/controllers/chat/live_stream.js` so the shared `chat` controller delegates live chunks, thinking, tool events, status, nested subagent branches, navigation, refresh, and chat-title updates to one path. Keep the current admin page context in the shared layout inside `turbo-frame#app-content-frame` as the hidden `#admin-agent-alpha-page-context` token, copy that token into the preserved Agent Alpha composer on `turbo:load` and `turbo:frame-load`, verify it server-side on message posts, and pass the resulting structured `ui_context` into the runtime instructions. That `ui_context` payload should stay page-scoped, include the current page, current object, current operation, nested route params such as `skill_catalog_id`, `rag_flow_id`, `test_suite_id`, `connector_id`, preview params such as `view` and `chat_id`, and reserved `references` entries for future `#` references. Keep `turbo-frame#app-content-frame` on Turbo `advance` history mode so standard in-pane admin navigation updates the browser URL/history while the shared shell and preserved Agent Alpha frame stay mounted. Resolve signed mission-page context into the current `Mission` runtime object and signed agent-page context into the current `Agent` runtime object before enqueuing the turn so Agent Alpha's `mission_designer` and `agent_designer` builtin subagents can edit the active record directly. Extend that same current-object/runtime-context path to skill catalogs, skills, rag flows, connectors, and test suites so shared discovery can scope itself to the visible page instead of only the session operation. Standard record refreshes from Agent Alpha should reload only `turbo-frame#app-content-frame`: broadcast the currently visible pane path as the refresh guard and the canonical post-mutation record path as the frame target, and never reload the whole document or `#admin-agent-alpha-frame`. Use the shared chat frame only for normal HTML rendering, composer UX, and the final persisted refresh after streaming ends. Leave Agent Alpha message persistence to message completion rather than checkpointing partial text to the database. Apply Agent Alpha's initial submit and cancel status updates without Turbo DOM replacement, and keep focus on Agent Alpha's own input while its stream starts so multi-chat pages do not hand focus to another chat. Pages that need extra right-sidebar panels, such as the mission designer, should inject them through `content_for :admin_panel_sidebar_panels`, `:admin_panel_sidebar_tabs_before_chat`, and `:admin_panel_sidebar_tabs_after_chat` instead of rendering a second sidebar shell.
- Explicitly opening the Agent Alpha panel, whether by clicking the sidebar tab or via a system-triggered action such as dashboard onboarding, should focus the Agent Alpha composer once the panel content is available.
- Shared chat catch-up refreshes must target a chat-specific transcript id such as `chat-<id>-messages`, not a global `#messages`, because admin pages can host more than one chat shell at once.
- Every configured `admin/agent_alpha` frame response must keep `turbo-frame#admin-agent-alpha-frame` marked with `data-turbo-permanent`; otherwise the marker disappears after the lazy load and later navigation can reload Agent Alpha.
- Admin shell links and forms that navigate within the admin app but live outside `turbo-frame#app-content-frame` must target `app-content-frame`. Do not add admin navigation links that force a whole-document visit or target `#admin-agent-alpha-frame`; that includes inline `window.location` handlers, `_top` Turbo-frame escapes for normal in-app navigation, and page-specific sidebar links rendered outside the content frame. Agent Alpha itself should never reload during normal in-app navigation.
- Programmatic admin form submissions that should stay on the Turbo/frame path must use `requestSubmit()` (or another real submit event) instead of native `form.submit()`, because `submit()` bypasses Turbo interception and reloads the whole page instead of updating only `app-content-frame`.
- In that shared right activity bar, keep the Agent Alpha tab first, render any page-specific tabs after the separator below it, and leave the collapse control as the final item.
- Turbo frame navigation does not rerender the outer admin shell, so pages that populate those shared sidebar slots or set `.main-content` data attributes must also emit the hidden `layouts/_admin_frame_state` payload inside `turbo-frame#app-content-frame`; the shared `admin-frame-state` Stimulus controller rehydrates those outer-shell slots and controller attributes on `turbo:frame-load` and clears them again when a later frame response omits the payload.
- Theme-aware layouts must render the helper-provided initial theme class/data on `%html` and include the shared head helpers for the theme primer style tag plus bootstrap script. Persist theme changes to both cookies and `localStorage`, and keep the `%html` `data-theme-ready` first-paint guard wired through those helpers so refreshes stay on the saved theme primer instead of rendering light unstyled content before the main stylesheet and Stimulus finish loading.
- Forms must display validation errors.
- Use `content_for(:head)` with `meta[name="turbo-cache-control"] = "no-cache"` only for pages that rely on **transient, non-replayable** `turbo_stream_from` events (e.g., Playground streaming chunks). Do not enforce it for every Turbo Stream page.
- **haml-lint workaround:** Insert a `-#` comment between consecutive `= render` sibling calls to avoid false `Lint/Syntax` errors.
- When a write action is unavailable on an admin surface, prefer rendering the disabled control with the policy's `denied_reason(...)` as its tooltip instead of hiding the action entirely.

### CSS
- Modular — `app/assets/tailwind/application.css` is the import hub.
- Dirs: `base/`, `layout/`, `components/`, `features/`. Use CSS nesting. No SCSS needed.
- Add styles in the appropriate existing file; `@import` new files in `application.css`.
- When a density change should affect multiple screens, update the shared Tailwind modules or scoped density overrides first instead of duplicating tighter utility classes across views.
- Shared chat primitives and shared variant presentation rules live in `app/assets/tailwind/components/_shared_chat.css`; that includes the compact `.ms-chat-panel.shared-chat--application` shell plus the shared playground variant. Admin tool-widget configuration and summary surfaces live in `app/assets/tailwind/components/_tool_widget_admin.css`, so keep `features/_playground.css`, `features/_chat.css`, and `features/_mission.css` limited to surface-specific layout/tokens or true feature-only deltas instead of duplicating transcript typography, tool-row, or composer rules there.
- Reusable page hero/header primitives live in `app/assets/tailwind/components/_page_hero.css` with shared partials under `app/views/shared/page_hero/` and view helpers in `app/helpers/page_hero_helper.rb`. Render them through `render_page_hero(...)` in Haml instead of building hero objects in templates. Prefer `variant: :dashboard` on index-style surfaces and `variant: :compact` on internal pages rather than reintroducing feature-local hero markup, but keep both variants on the same compact toolbar shell. Shared headers should render a title/icon badge on the left and grouped controls on the right, with separators between badge/meta groups, back navigation, destructive actions, and the trailing primary action. Internal pages that need the current record name inline next to the title badge should pass `record_title:` instead of adding a neutral badge row below the title. Shared page headers are sticky by default; pass `sticky: false` only when a surface must opt out. Dedicated form pages should still bind their primary submit button into the header with a form-targeted page-hero action and should not keep duplicate footer back/save controls, while dashboard-scoped controls such as the operation filter should live in that shared header instead of a separate quick-actions bar. Shared page headers no longer render summary counters. Shared right-sidebar panel headers should match that same overall height via the shared header-height token, and chat header actions such as history/new should render as compact neutral buttons rather than icon-only controls or primary buttons. `app/assets/tailwind/layout/_layout.css` owns the default decorative page-content backdrop for standard admin pages. Playground and inspector remain immersive opt-out surfaces there, but mission designer now keeps the shared page-content backdrop and shared compact page hero on its main canvas page instead of rebuilding alternate page chrome in feature CSS. Page-level card grids should keep both their inter-card gap and their stacked top-level spacing aligned with `--page-padding`, so horizontal and vertical card spacing matches the page gutter. `app/assets/tailwind/components/_cards.css` is the source of truth for that rhythm: top-level card surfaces and wrappers whose direct children are `.card`, `.stat-card`, or `*-card` elements should inherit the shared `--page-padding` spacing instead of view-local `gap-5`, `gap-6`, `mb-6`, or `mb-8` tweaks. Reusable index/listing cards should use the shared `.card-grid` and `.entity-card` primitives from that stylesheet, including their responsive header, metrics, chip rows, and footer patterns, instead of rebuilding those layouts with page-local utility stacks. Card-based resource indexes should stay on those shared primitives even when records need inline actions, nested utility panels, or multiple badge rows; do not keep feature-local wrappers such as custom `connector-card`, `test-suite-card`, or index-only grid selectors once the shared entity-card structure can express the layout. When an index is empty, render the shared `render_page_empty_state(...)` helper backed by `app/views/shared/_page_empty_state.html.haml` and `app/assets/tailwind/components/_page_empty_state.css`; keep that empty state text-and-actions only and let the page-content backdrop provide the visual atmosphere.
- Reusable card and row icon chips should use the shared `.entity-card__icon` primitive from `app/assets/tailwind/components/_cards.css` directly instead of feature-local alias classes such as connector- or test-suite-specific icon boxes. Keep feature stylesheets limited to genuinely surface-specific deltas that the shared primitive cannot express.
- Reusable multi-step wizard primitives live in `app/assets/tailwind/components/_wizard.css` with shared partials under `app/views/shared/wizard/` and view helpers in `app/helpers/wizard_ui_helper.rb`.
- Plugin- or feature-specific wizard theming must stay inside the owning plugin. Load plugin-owned stylesheets from `content_for(:head)` rather than adding plugin selectors to shared app feature CSS.
- Wizard flows that need live schema/query feedback should render through Turbo Frame previews on the normal Rails form route, with Ruby-side state objects preparing options and status messaging. Keep Stimulus limited to tiny generic frame-preview helpers instead of large plugin-specific state machines.
- Choices.js overrides go in `components/_choices.css`.

### Dropdowns (Choices.js)
- **Never** put `data-controller` directly on `<select>`. Always on a wrapper element.

### Helpers & Testing
- **No UI logic in models.** All display logic in `app/helpers/`.
- RSpec only. FactoryBot, Faker, Shoulda::Matchers, WebMock, VCR, Capybara.
- Rails transactional fixtures are the default test isolation mode. Only `:commit_db` specs and browser-visible JS/system specs should opt out and use truncation so committed rows stay visible across separate connections.
- The test environment enables `ActiveModel::SecurePassword.min_cost = true`; keep it that way so password-backed factories and request-spec logins stay cheap.
- Browser/system specs run through Capybara + Selenium with the app's Falcon stack and should use truncation (`js: true`) rather than transaction-only DB isolation so the browser can see committed records.
- Default `bundle exec rspec`, `bundle exec rake`, `bundle exec rake spec`, and CI RSpec runs should exclude `:js` specs unless `SYSTEM_SPECS=1` is set. Keep the system-spec support hooks aligned to `:js`.
- Keep direct `bundle exec rspec` default discovery aligned with `bundle exec rake spec` by patching `RSpec::Core::Configuration#files_to_run` from `spec/default_spec_discovery.rb` so no-arg runs include both `spec/` and `plugins/**/spec/`, while explicit file selections such as `bundle exec rspec spec/models/client_spec.rb` stay narrow. Do not move that behavior into `.rspec` `--pattern`, because it makes explicit file runs expand back to the full suite.
- The rake path also keeps its explicit `spec/system` path guard unless `SYSTEM_SPECS=1` is set.
- Fresh environments that render the mission designer in request specs must build the esbuild mission bundle first (`pnpm run build:mission`) so Propshaft can resolve `mission_designer.js` and `mission_designer.css` from `app/assets/builds`; keep both GitHub Actions and local `bin/ci` doing that before RSpec, and keep `bin/ci` running `CI=1 bundle exec rspec` so local coverage matches GitHub Actions eager-load mode.
- Keep the checked-in `pnpm-workspace.yaml` root `packages` entry plus `allowBuilds.esbuild: true` so `actions/setup-node` cache setup under pnpm 9 and local pnpm 11 installs both work without an interactive `pnpm approve-builds` step.
- GitHub Actions jobs that use `actions/setup-node` with `cache: pnpm` must install pnpm first (for example via `pnpm/action-setup`) before the cache-enabled `setup-node` step, or the action fails while resolving the pnpm cache path.
- Request specs auto-sign in by default via `spec/support/authentication_helpers.rb`; mark groups `unauthenticated: true` when a spec intentionally performs its own sign-in flow or needs a specific logged-out state.
- 100% line and branch coverage (SimpleCov). Keep the repo-wide filter for `lib/undercover_agents/ruby_llm_debug_logging.rb`; it is a local toggle-only diagnostics hook and should not count against the app coverage gate. Suppress expected logger errors with `allow(Rails.logger).to receive(:error)`.
- CI coverage uploads use Codecov OIDC and the Cobertura report at `coverage/coverage.xml`; keep SimpleCov generating both the default HTML output and the Cobertura XML when touching test coverage setup, and keep the upload step non-blocking until the repository is connected to the Codecov GitHub app.

## Tool Architecture

`Tool` uses a **plugin-based configurator + single table** architecture (`tool_type` + `configuration` JSONB). Agents reference tools via `AgentTool` join. Each tool type is a self-contained plugin under `plugins/tool_<type_key>/`.

### ToolPlugin Protocol (`app/models/concerns/tool_plugin.rb`)
Controller delegates all type-specific behavior to the resolved tool configurator — **no type-checking in controller**.

**Registry:** `ToolPlugin.type_map`, `ToolPlugin.resolve(key)`, `ToolPlugin.filter_type(key)`, `ToolPlugin::Result = Data.define(:success?, :message)`.

Keep `ToolPlugin` registrations recoverable after test resets and development reloads: shared runtime callers such as builtin-tool registration, runtime tool building, and tool-call display metadata may lazily re-register tool types from the loaded plugin manifests when the in-memory tool registry is empty instead of assuming a single boot-time registration pass.

**Each tool type implements:**
- Class: `type_key`, `type_label`, `type_icon`, `permitted_params(params)`, `build_from_params(params)`
- Class: `tool_designer_editable_attributes`, `tool_designer_notes`, `tool_designer_field_hints`, `tool_designer_resource_kinds`, `tool_designer_action_definitions`/`tool_designer_actions`, `tool_designer_state_attributes`
- Instance: `perform_tool_designer_action!(action_key, arguments)`, `tool_designer_state`, `perform_discovery!`, `update_visibility!(raw_params)`, `visibility_available?`, `visibility_param_key`, `form_partial_path`, `show_partial_path`, `edit_visibility_partial_path`
- Tool Designer runtime tools must stay plugin-isolated: `read_tool` renders only `tool_designer_state`, `get_tool_type_info` renders plugin-declared fields/actions/resources plus derived validators, and `manage_tool_action` authorizes via each action definition's policy query before calling `perform_tool_designer_action!`. Do not hardcode plugin state labels, action argument shapes, or resource lookup kinds in the main app.

### Shared Tool Widget Presentation
- User-created tools share a single chat-widget configuration layer backed only by `tools.configuration` JSONB. Do not add dedicated DB columns for widget icon/copy/animation settings.
- Shared widget attributes live on the configurator through `ToolWidgetConfigurable`; keep icon and execution/completion copy parsing/validation in that shared concern instead of duplicating logic per tool type.
- Tool-call presentation defaults are code-defined: user-created tools expose `tool_widget_default_presentation(display_name:, icon:)`, builtin runtime tools define their shared row copy in `config/initializers/builtin_tools.rb`, and subagent/fallback copy lives in `ToolCalls::PresentationDefaults`.
- The dedicated tool widget edit page should render the shared admin partial `app/views/admin/tools/shared/_widget_configuration.html.haml`, and tool show pages should render `app/views/admin/tools/shared/_widget_summary.html.haml`.
- Saved user-created tools edit shared widget icon and copy from the dedicated Chat Widget page linked from the tool show screen rather than the main tool edit form.
- Built-in runtime tools keep their behavior and widget presentation code-defined alongside their `BuiltinTools::Registry.register` entry. Only mark a built-in tool with `user_assignable: true` when normal user-created agents may select it through `runtime_tool_keys`; keep internal designer/admin tools unassignable.
- Shared widget resolution for both persisted and streaming tool calls must go through `ToolCalls::DisplayMetadataResolver` returning `ToolCalls::Presentation`.
- All shared-chat tool calls must render through the shared compact timeline row UI in `app/views/shared/chat/` and the generic chat streaming controller. `ToolCalls::Presentation#group_title` only controls whether consecutive calls collapse into one shared tool-chain block; it must not switch to a separate badge renderer. Persisted refreshes and live optimistic rendering must stay on that same shared path.
- Shared cross-tool widget Stimulus controller (`tool-widget`) lives in `app/javascript/controllers/` because it is an app-level UI primitive, not a plugin-specific controller.

## Skill Architecture

Skills are app-level, operation-scoped knowledge libraries that agents can discover and activate at runtime without adding full instructions to every prompt.

- **Models:** `SkillCatalog` (`belongs_to :operation`, FriendlyId slug, `has_many :skills`), `Skill`, and `SkillResource` (`has_one_attached :file`).
- **Agent assignment:** agent skill-catalog links live in `Agent.configuration["skill_catalog_ids"]`. Keep this JSONB-backed, matching the existing lightweight association pattern instead of adding join tables unless requirements materially change.
- **Runtime integration:** `HasSkillCatalogs` augments `Agent#build_full_instructions` with a compact `<available_skill_catalogs>` block and appends runtime-only RubyLLM tools `list_available_skills`, `activate_skill`, and `read_skill_resource` to `Agent#tools`.
- **Progressive disclosure rule:** keep the base prompt limited to assigned catalog identifiers, names, descriptions, and skill counts. The model should call `list_available_skills` with a catalog identifier to inspect skill identifiers/descriptions, then call `activate_skill` only when a listed skill is relevant. Full `SKILL.md` content and bundled files should only load through the runtime tools.
- **Import flow:** `Skills::ImportService` supports standalone `SKILL.md` files and ZIP collections. ZIP imports discover directories containing `SKILL.md`, upsert skills by name within the target catalog, preserve bundled resources, and retry common YAML colon parsing mistakes before failing.
- ZIP-backed runtime features such as `Skills::ImportService` must declare `rubyzip` directly in the root Gemfile. Do not rely on transitive copies from development- or test-scoped gems, because production images exclude those groups.
- **Builtin skills:** `BuiltinSkills::Synchronizer` loads app-owned builtin catalogs from `config/builtin_skills/<catalog_key>/CATALOG.md` plus nested standard `SKILL.md` packages, and also loads plugin-owned builtin catalogs from `plugins/**/config/builtin_skills/<catalog_key>/`. Shared app builtin skills should be area-based, user-facing product manuals for the shared core app areas such as administration, agents, missions, channels, test suites, skills, tools, and RAG. Keep them focused on product behavior and operator guidance rather than code internals; plugin-specific feature details belong in plugin-owned builtin skill catalogs.
- **Admin UI:** skill catalog and skill CRUD/import screens live under `app/views/admin/skill_catalogs/` and `app/views/admin/skills/`, with feature styling in `app/assets/tailwind/features/_skills.css` and shared app-level Stimulus controllers in `app/javascript/controllers/skill_*`.

### Tool Plugins

| Plugin | Type Key | Notes |
|--------|----------|-------|
| `tool_sql_query` | `sql_query` | Belongs to `Connector`, schema discovery + visibility, `SchemaIntelligence` + `SqlQueryBroadcasts` concerns, agents, jobs, services, prompts |
| `tool_mcp_server` | `mcp_server` | Belongs to `Connector`, discovers MCP tools + manages visibility |
| `tool_rag_query` | `rag_query` | pgvector similarity search. Configurable tables, embedding model, distance method, thresholds. Uses `Tools::RagSearchable` concern |
| `tool_rag_flow` | `rag_flow` | pgvector similarity search against an `RagFlow`. Delegates table/field config to flow storage/embedding steps. Uses `Tools::RagSearchable` concern |

### Plugin File Layout
Each tool plugin follows this structure:
```
plugins/tool_<type_key>/
  plugin.rb                          # register + add_tool DSL
  app/models/<type_key>.rb           # configurator (include ToolPlugin)
  app/models/*.rb                    # concerns (e.g., schema_intelligence.rb)
  app/services/*.rb                  # type-specific services
  config/builtin_agents/*.toml       # optional single-file builtin-agent definitions + instructions for internal LLM helpers
  app/tools/*.rb                     # RubyLLM::Tool adapters
  app/jobs/*.rb                      # background jobs
  app/views/                         # _form.html.haml, _show.html.haml, etc.
  spec/                              # all specs + factories for the plugin
```

### Plugin Namespace Loading
Tool plugins push `app/models/`, `app/services/`, and `app/agents/` under the `Tools::` namespace via `configure_tool_namespaced_paths` in the plugin loader. `app/tools/` and `app/jobs/` are autoloaded without namespace prefix. Builtin-agent definitions remain file-based under `config/builtin_agents/`, with instructions embedded directly in each TOML file.

Plugin `app/assets/` directories are added to the asset load path by the plugin loader, so plugin-owned stylesheets and images can stay self-contained and be linked explicitly from plugin views.

### RAG shared concerns (in app/)
- `Tools::RagSearchable` (model concern `app/models/concerns/tools/rag_searchable.rb`) — shared constants (`DISTANCE_METHODS`, `DISTANCE_OPERATORS`, `DEFAULT_TOOL_PROMPT`), validations, and methods (`distance_operator`, `effective_instructions`, `selected_document_fields`) for both RAG tool types.
- `RagToolBehavior` (RubyLLM tool concern in `app/tools/concerns/`) — shared params, name sanitization, execute flow, error handling, result formatting for `RagQueryTool` and `RagFlowTool`.
- `Tools::RagSearchService` — generic search service accepting any `RagSearchable` model. `Tools::RagQueryService` is a thin subclass for backward compatibility.

**`ToolsController`** is a thin dispatcher. `ModelOptionsSupport` concern handles AJAX model selects via `render_model_options(config)`. Views under plugin `app/views/` with `_form.html.haml` and `_show.html.haml` at minimum (or plugin-owned partial paths).

### Adding a New Tool Type
1. Create plugin folder `plugins/tool_<type_key>/` with `plugin.rb` using `add_tool "<Label>"` DSL, `category [:tool]`
2. Add configurator model in plugin `app/models/<type_key>.rb` with `include ToolPlugin`, implement protocol
3. Add view partials `_form.html.haml` + `_show.html.haml` in plugin `app/views/tools/<type_key_plural>/`
4. Optional: services, RubyLLM::Tool adapters, builtin-agent TOML definitions for internal helpers, jobs
5. Specs + factory in plugin `spec/`

### Plugin Isolation Rules
- Tool plugin specs must live inside each plugin under `plugins/tool_<type_key>/spec/**`
- Tool plugin factories must live inside each plugin under `plugins/tool_<type_key>/spec/factories/**`
- Plugin-owned builtin-agent definitions must live at `plugins/tool_<type_key>/config/builtin_agents/*.toml`
- Tool plugin Stimulus controllers must live under the owning plugin (`plugins/**/app/javascript/controllers/**`), not `app/javascript/controllers`
- Do not place tool-type-specific code in `app/models/tools/`, `app/services/tools/`, etc. — keep it in the plugin

## Playground

Full-screen chat sandbox, `playground` layout. `ChatResponseJob` streams chunks via `broadcast_append_to`, status via `broadcast_replace_to` for user, playground, and mission-designer chats. Stimulus: `chat`, `playground-sidebar`, `markdown-render`.

- Playground, Agent Alpha application chat, and client chat must all render through the shared partial stack in `app/views/shared/chat/`. Configure placeholder text, empty states, drag/drop, and attachment visibility through `ChatUiHelper#build_chat_component` instead of creating new chat-specific partials.
- Shared chat reference mentions are opt-in through `chat_reference_config`; keep `chat-references` Stimulus generic and disabled unless a component passes reference config. Keep resource discovery and server validation in `ChatReferences::Registry`, `Search`, `SelectionResolver`, `PromptRenderer`, and `MessagePayload`. Mention UI should stay record-readable, such as inline `#launch-plan` code badges, while posted references carry a signed global id that is re-scoped server-side before use. The LLM history receives prompt-safe record ids such as `mission id: 23` plus a `Referenced records:` mapping for both inline and context-button references that includes the selected record type, label, id, and slug from the persisted payload; if an inline reference chip is removed from the composer, remove its matching token from the textarea too so no unresolved `#tag` is left behind. Agent Alpha enables missions, tools, skill catalogs, skills, agents, clients, connectors, RAG flows, and test suites, while future agents should customize allowed kinds through component config rather than hardcoding picker behavior in the shared chat shell.
- Shared chat transcripts use compact assistant panels instead of assistant bubbles. Keep tool calls and thinking on the same one-line row primitives in `app/views/shared/chat/` and `app/assets/tailwind/components/_shared_chat.css`, and render subagent calls as collapsible nested transcript branches backed by `Chat#child_chats`; only plugin-owned custom widgets should break out of that compact tree view.
- Tool-heavy parent chats can occasionally persist a synthetic terminal assistant message whose content is just the concatenation of the earlier assistant planning messages from the same turn. Keep the shared `ChatResponseJob` guard that strips that duplicate terminal message before backfill/finalization so Agent Alpha and similar tool-using chats do not end with a replayed planning transcript.
- Shared chat tool-call rows must prefer persisted `ToolCall.display_name` / `ToolCall.icon` metadata and use `ToolCalls::DisplayMetadataResolver` as the fallback source for both saved messages and live Turbo tool-call events.
- Shared chat tool-call rows also use resolver-driven presentation copy (`group_title`, `running_messages`, `complete_messages`, `running_mode`, `running_interval_ms`) so the live optimistic rows and persisted history stay in sync.
- Consecutive tool calls that share a `group_title` must collapse into the shared compact timeline block in both persisted history and live optimistic rendering. The runtime label line shows only the group title and a spinner while the trailing grouped block still represents the active streaming turn, even if all visible tool rows are already complete; the timeline rows below it own the per-step status icons. Persisted refreshes must regroup consecutive assistant tool-call messages the same way, while plugin-owned custom widgets such as human-in-the-loop still own their own rendering.
- Admin Playground only allows enabled, selectable agents from the current operation whose `runtime_tool_keys` are empty. Keep the agent dropdown in the sidebar and render an explicit empty state when no compatible agents exist.
- Playground-style chat pages (`app/views/admin/playground/chats/show.html.haml`, `app/views/chats/show.html.haml`, and the shared admin application chat) use transient Turbo broadcasts plus a stale-update catch-up poll from `chat` against the show route's `.turbo_stream` format.
- During active streaming, the shared `chat` controller should only use catch-up responses for status recovery and defer persisted `#chat-<id>-messages` replacement until the chat is no longer streaming; replacing the list mid-stream breaks optimistic bubbles and scroll position.
- Live tool-event placeholders broadcast from `BaseChatResponseJob#broadcast_tool_event` must include the widget presentation data attributes consumed by the shared `tool-widget` controller.
- Any controller or service that needs to continue a chat asynchronously should call `Chat#enqueue_response!` instead of selecting a response job class itself; `Chat` owns the routing for user, playground, and mission-designer chats.
- Keep `turbo-cache-control` set to `no-cache` on those pages and preserve the `#chat-<id>-messages` / `#chat-<id>-status` targets in their catch-up responses.

## Chat Token Optimization

- **Stale tool-result compaction:** `Chat#to_llm` runs `Chats::MessageCompactor` before each LLM rebuild and exposes the stale AR message ids through `Chat#stale_message_ids`. `Message#to_llm` replaces the in-memory content of stale tool-result messages with `Chats::MessageCompactor::STUB_CONTENT` while leaving the persisted AR record untouched. This keeps long tool-heavy chats (mission designer, agents that call `read_*` tools repeatedly) within a bounded token budget.
- **RubyLLM 1.15 token semantics:** persisted `messages.input_tokens` now represent only standard input tokens. Cache reads and writes remain in `cached_tokens` and `cache_creation_tokens`. High-level “In”/total token summaries that should preserve request-side input activity must sum all three buckets, while inspector-style normalized breakdowns should keep the buckets separate. Manual message cost math must charge `input_tokens` directly rather than subtracting cached tokens from it.
- **Compaction policies:** register per-tool policies through `Chats::MessageCompactor.register(tool_name, policy:)`. Valid policies: `:replace_by_time` (keep only the latest call result), `:replace_by_args` (keep latest per `(name, arguments)` tuple — the default), `:keep_all` (never compact). App-level defaults live in `config/initializers/tool_result_compaction.rb`; add new state-reading tools there rather than hardcoding behaviour in the tool itself.
- **Tool description budget:** RubyLLM ships every tool's `description` string in every request. Keep mission-designer and similar high-frequency tool descriptions to one short sentence and push detailed authoring guidance into `get_node_type_info` or other on-demand discovery tools.

## Mission Architecture

Visual workflow engine for orchestrating multi-step LLM pipelines. Admin-managed at `/admin/missions`.

- **Models:** `Mission` (flow_data JSONB, undo/redo history via `Missions::FlowHistory`) + `MissionRun` (execution_state, variables, flow_snapshot, status enum).
- **Designer:** React Flow canvas (`app/javascript/mission_designer/`). Flow saved via `PATCH save_flow`. Stimulus: `mission` controller.
- **Admin controller split:** keep `Admin::MissionsController` limited to CRUD/designer shell concerns. Route designer AJAX endpoints through `Admin::MissionFlowsController` and debug-run HTTP endpoints through `Admin::MissionDebugRunsController` instead of rebuilding runtime/debug state in the main controller.
- **Mission route context:** mission-specific pages and mission-designer endpoints must resolve the mission through the current tenant and adopt `mission.operation` as the active operation for the request and session before rendering or mutating state; do not rely on the previously selected operation when the URL already identifies the target mission.
- **Persisted flow normalization:** mission designer saves and `Missions::FlowEditor` mutations must normalize persisted `flow_data` through `Missions::FlowPersistenceNormalizer`, not ad hoc controller/editor cleanup paths. Keep transient React fields, derived node names, numeric coercions, edge metadata normalization, global-variable key sanitization, and Generate Text `llm_config_source` defaulting centralized there.
- **Execution:** `MissionExecutionJob` → `Missions::Runner`. Queue-driven graph execution via branch-local `Missions::RunnerScheduler` instances, with runtime expression evaluation in `Missions::ExecutionContext`. Resumable — state persisted after every node plus scheduler-frontier checkpoints for active or ready work.
- **Control-flow orchestration:** special multi-step control nodes (`iterator`, `loop`) execute through dedicated runner control-flow modules, while shared branch fan-out helpers stay isolated from node-specific runtime behavior.
- **Synchronization orchestration:** `Missions::RunnerSynchronization` composes narrow helpers for implicit multi-input join readiness/diagnostics and edge-state transitions; keep traversal/scheduling logic separate from synchronization rules and preserve the `Runner#edge_state_changed` hook for debug broadcasts.
- **Node execution bookkeeping:** handler invocation, output serialization, disabled-node skipping, and node-scoped variable registration execute through `Missions::RunnerNodeExecution`; keep routing/traversal logic separate from node execution bookkeeping.
- **Execution log payloads:** each `MissionRun.execution_state["execution_log"]` entry persists both resolved node `input` and `output`. Populate those snapshots from the shared runtime resolution path, and keep Mission Control plus the mission-designer debug timeline rendering both sides from that persisted log instead of recomputing inputs in controllers or JavaScript.
- **Execution setup:** flow snapshot sanitization, graph construction, execution-context restore/build, and global-variable seeding execute through `Missions::RunnerExecutionSetup`; keep lifecycle focused on top-level run flow instead of context/bootstrap details.
- **State persistence orchestration:** current-node persistence, active-frontier checkpoints, terminal run-state writes, and failure-state writes execute through `Missions::RunnerStatePersistence`; keep traversal/control-flow modules from open-coding `MissionRun` updates.
- **Traversal orchestration:** entry-node discovery and persisted frontier restoration execute through `Missions::RunnerFrontierTraversal`, work-item draining and current-node context setup execute through `Missions::RunnerTraversal`, and outgoing-edge routing executes through `Missions::RunnerEdgeDispatch`, all on top of `Missions::RunnerScheduler`. Linear paths should stay inside one scheduler drain loop, loop and iterator bodies should checkpoint active frontier progress between iterations, iterator bodies may optionally run in batched parallel groups, and same-handle fan-out should still run through the shared async branch helpers.
- **Lifecycle orchestration:** run bootstrap, execution-context seeding/restoration, and top-level failure/completion flow execute through `Missions::RunnerLifecycle`; keep `Runner` as the thin public API and constant owner.
- **Runtime state ownership:** `Missions::ExecutionContext` is now the single owner of persisted mission variables, node-scoped variables, Dentaku evaluation, and branch-local runtime helper state. Do not reintroduce a separate expression-evaluator layer for normal mission execution.
- **Node-scoped state:** keep node outputs in `execution_state["node_variables"]` and `execution_state["node_outputs"]`, and reference them through qualified names like `summarizer.response`. Do not add flattened alias variables such as `summarizer__response` or synthetic shared variables like `node_<id>_output` back into persisted mission state.
- **Unique node prefixes:** the node variable prefix is the canonical `data["name"]`/derived name, not the raw label. It must be unique per flow; duplicate labels receive suffixed prefixes like `json_extract_2` and `json_extract_3`. Designer docs, `read_mission_flow`, and `list_node_variables` should surface those exact prefixes, and runtime code should resolve node-scoped variables from that canonical unique prefix rather than assuming normalized labels are unique.
- **Transient runtime helpers:** `Missions::ExecutionContext` treats `_current_node_id`, `_current_node_type`, `_current_node_data`, and iterator/loop helper bindings such as `item`, `index`, `total`, `iteration`, node-scoped `_iterator_states`, node-scoped `_loop_iterations`, and the active-loop `_loop_iteration` value as branch-local runtime helpers. Concurrent branches inherit a snapshot of those helpers from their parent branch. Nested iterators and loops must keep their internal state isolated per control node while still exposing the current `item`/`index`/`total` triplet and active loop iteration to the body that is currently executing.
- **Runtime helper field access:** formula evaluation flattens hash-valued runtime helpers such as `item`, so expressions like `item.title` and `item.meta.score` work in filter, iterator, and loop formulas without adding persisted alias variables.
- **Node value resolution:** shared parsing for templates, formulas, integers, and collection references lives in `Missions::ValueResolver` and `Missions::CollectionResolver`. Mission nodes should use those helpers rather than duplicating interpolation/evaluation/parsing logic inline.
- **Debug mode:** `Missions::DebugRunner` (subclass) broadcasts real-time events via `MissionDebugChannel`. Persisted debug catch-up/status projection belongs in `Missions::DebugRunState`, not ad hoc controller helpers. Stimulus: `mission-debug` controller.
- **Edge state rule:** `Missions::Runner` is the single source of truth — persists edge statuses under `execution_state["edge_states"]`. `DebugRunner` only broadcasts those transitions; do not reconstruct edge state in controllers or JavaScript from node execution logs.
- **Node types:** `MissionNodePlugin` registry. Built-in: input/output (`input`, `output`), nodes (`agent`, `llm`, `mission`, `http_request`, `code`, `text_template`, `json_extract`, `write_file`, `generate_image`), and control (`condition`, `switch`, `iterator`, `loop`, `filter`, `aggregate`, `sort`, `unique`, `limit`, `set_variable`, `delay`).
- **Implicit join semantics:** any node with more than one distinct immediate predecessor is a synchronization point. It waits for each unique immediate predecessor node that still has at least one enabled path into the join before executing and does not create join-specific variables. Multiple direct ports from the same upstream node count as one predecessor while any of those edges remain enabled.
- **Fan-out semantics:** multiple outgoing edges from the same handle execute concurrently. When those branches later feed the same downstream node from different predecessor nodes, that downstream node implicitly waits for all of them.
- **Mutually exclusive branch pruning:** `condition`, `switch`, `filter`, and `http_request` disable every non-selected outgoing edge when they complete. Disabled edges propagate downstream: if a node's incoming edges are all disabled, that node becomes disabled too and its outgoing edges are disabled. Disabled edges and disabled nodes do not block downstream joins.
- **Shared downstream nodes:** nodes with one or zero distinct immediate predecessors execute on each arrival as usual; nodes with two or more distinct immediate predecessors wait for all of them.
- **Loop/iterator body boundaries:** iterator and loop bodies are closed per-iteration subgraphs. Do not wire a body node back into its iterator/loop node, and do not mix body-fed inputs with non-body inputs on the same node.
- **Parallel iterator semantics:** iterator `parallel` mode runs loop bodies in batches up to `max_parallel_branches` and still preserves the source-order `results` array on the `done` chain. Treat sibling iterations as independent branches: aggregate through `results` instead of depending on shared mutable variables being written in a deterministic order across parallel iterations.
- **Loop-body joins:** do not connect a loop-body or iterator-body node directly into a continuation that should run once after the loop finishes. Route the once-per-run continuation through the iterator/loop `done` chain or another post-loop node instead of joining per-iteration and post-loop arrivals together.
- **Nested inner `done` ports:** an inner iterator/loop can intentionally end its nested body branch without a `done` edge when no once-per-run continuation is needed at that nesting level; do not add dummy `done` handlers just to satisfy a warning.
- **Output nodes:** `output` ends the entire mission as soon as it runs. Do not use it as a loop-body sink, trace sink, or side-effect placeholder; loop and iterator body chains may validly end on a non-output leaf node.
- **Code node outputs:** design-time variable discovery exposes `result` plus any names declared in `output_variables`. If code calls `set()`, keep the same names in `output_variables` so downstream tools and agents can see them.
- **Workflow tests and downstream assertions:** when configuring `output.selected_variables`, aggregate inputs, or mission test `expected_variables`, call `list_node_variables` on the exact downstream node after wiring upstream edges. Use the returned names verbatim as identifiers, keep non-global keys fully qualified, and compute expected values from the exact post-transform dataset that reaches the assertion node rather than the original seed constants. Do not assume iterator `done` `results` is a flat scalar array.
- **Aggregate count semantics:** `aggregate` `count` returns collection length, not semantic matches. To count a subset such as even numbers, count a filtered collection like `filter_evens.matches` or filter iterator results before aggregating.
- **Collection variable references:** collection-driven nodes such as `iterator`, `filter`, `unique`, `sort`, `limit`, and `aggregate` must point to a defined upstream array variable or a literal JSON/CSV array. Bare unknown refs like `remove_duplicates.result` now fail validation and runtime; use `list_node_variables` and exact names like `remove_duplicates.unique`, `sort_descending.sorted`, or `take_top_two.items`.
- **Template variable syntax:** `list_node_variables` returns identifiers such as `get_capacities.body`. Wrap those identifiers in `{{...}}` when the target field is template-valued (`json_extract.source`, `http_request.url`, `llm.prompt`, `output.response_body`). Keep them bare in non-template fields such as `selected_variables`, mission test `expected_variables`, collection refs, and formulas.
- **JSON Extract source validation:** `json_extract.source` accepts either literal JSON text or template-wrapped mission variables such as `{{get_capacities.body}}`. Bare plain strings like `get_capacities.body` are invalid config and should fail flow validation before runtime.
- **Scalar-only mission formulas:** mission expressions evaluate scalar numbers, strings, and booleans. If `list_node_variables` shows an array or hash, extract a scalar field/count or normalize it before comparing it in formulas. When mutually exclusive branches set shared globals like `summary` or `test_status`, reference those globals downstream instead of concatenating branch-specific placeholders.
- **Shared downstream templates after branches:** do not reference outputs from multiple mutually exclusive branches directly in one downstream template or formula. Normalize the selected branch output into a shared variable first, then reference that shared variable downstream.
- **Global variables are seeded inputs only:** do not define blank globals for values the workflow computes later with `set_variable` or similar runtime steps. If the mission produces `final_summary` or `final_test_status`, leave them as runtime outputs unless an operator must provide an initial value before execution.
- **Shared LLM chat options:** Agent forms and mission `llm` nodes share `Llm::ChatOptions` for temperature, reasoning/thinking, and provider-specific params. Gate temperature off `Model.capabilities` `temperature`, gate thinking off `reasoning`, and keep provider overrides in validated `custom_llm_params` JSON rather than ad hoc per-surface keys. Do not add app-level DeepSeek reasoning guardrails that disable thinking when tools are present; DeepSeek thinking mode supports tool calls, and the local RubyLLM compatibility patch owns the required `reasoning_content` round-trip until upstream RubyLLM includes the fix. DeepSeek's thinking-off state is different from the tools guardrail: when the effective effort is explicitly `none`, keep sending the provider's `thinking.type = "disabled"` payload so default thinking mode is actually disabled.
- **LLM node tools:** mission `llm` nodes can store enabled operation tool IDs in `data.tool_ids`; keep the inspector UI compact, surface those IDs from `get_node_type_info`, and resolve the runtime tool instances through `Tools::RuntimeBuilder` so nodes and agents share the same adapters.
- **HTTP Request node config:** keep `params`, `headers`, `form_urlencoded_body`, and `multipart_form_data` as structured hashes in `node.data`, and organize the inspector UI into request, authorization, body, and transport groups rather than one flat form. `body_mode` is explicit-only; do not add runtime or presenter fallbacks that infer it from legacy `body` content or `Content-Type` headers. Multipart and binary file uploads should store the selected file as a full template reference like `{{write_file_1.file}}` so variable extraction, validation, and runtime resolution stay consistent.
- **Config validation:** `Missions::NodeConfigValidator` validates all nodes before execution; errors shown in the designer.
- **Expression authoring:** In mission formulas, reference variables directly (`llm.response`, `http_request.response_body`) rather than `{{...}}`. `{{...}}` performs raw text interpolation before Dentaku parsing and breaks string/JSON comparisons; reserve it for template text, not expression operands. For string concatenation inside formulas or `set_variable` assignments, use `CONCAT(...)` instead of `+`.
- **Formula-field validation:** config validation rejects `{{...}}` inside formula-bearing fields such as `condition.expression`, `filter.expression`, `loop.condition`, `switch.expression`, `limit.count`, and formula-like `set_variable` assignments. Use direct references like `seed_defaults.effective_max_posts`, and when a mission must run without trigger data prefer `input` field `config.default_value` over formulas that compare maybe-`nil` inputs.
- **Formula helper compatibility:** Author new formulas with the canonical helpers from the expression reference (for example `LEN(...)`), but the runtime also accepts `LENGTH(...)` as a compatibility alias so older or generated flows do not silently break.

### Self-Contained Node Protocol

Each node class under `app/models/missions/nodes/` is **self-contained** — all metadata, variable extraction, and execution logic lives on the node model itself. The `MissionNodePlugin` concern provides defaults; each node overrides as needed.

**Class methods (metadata — all defined on the node class):**
- `node_type` → unique string key (e.g. `"llm"`)
- `node_label` → display label (e.g. `"LLM"`)
- `node_icon` → FontAwesome icon class
- `node_color` → hex color
- `node_category` → `:trigger` / `:node` / `:control` / `:input_output`
- `node_description` → short description
- `singleton?` → `true` if only one instance allowed per flow (default `false`)
- `field_contracts` → array of `Missions::FieldContract` entries describing config-field semantics such as `template`, `formula`, `collection_ref`, `assignment_map`, and JSON validation; prefer this over duplicating field rules across validators and helpers
- `variable_schema` → `Missions::VariableSchema` describing outputs only
- `dynamic_output_variables(data)` → array of output hashes for nodes whose `variable_schema` includes `*`
- `extract_variables(data, label, variables, seen)` → extracts referenced variables from node config data (for designer UI)
- `register_node!` → self-registers in `MissionNodePlugin` registry from class metadata
- `default_output_ports` → array of `{ key:, label: }` defining output handles (serialized to JS via registry)

**Instance methods (execution):**
- `output_ports` → delegates to `self.class.default_output_ports` (override for dynamic ports)
- `execute(context)` → returns `Missions::NodeResult`
- `validate_config!` → raises if invalid

**Self-registration:** Each node calls `register_node!` at the end of its class body. `MissionNodePlugin.register_defaults!` provides bootstrap registrations (string class names) for lazy-loading compatibility; `register_node!` updates registry metadata from the actual class when loaded.

**Shared extraction utilities on `MissionNodePlugin`:**
- `add_variable(variables, seen, key, category, source, description)`
- `extract_template_vars(variables, seen, template, label, node_type)`
- `extract_expression_vars(variables, seen, expression, label)`
- `extract_collection_var(variables, seen, data, label)`

**Field contracts:** `field_contracts` is the canonical source for node config-field semantics. `NodeConfigValidator`, collection-reference validation, and designer variable extraction should consume `field_contracts` first. Keep `variable_schema` focused on outputs only, and derive any input/config metadata from `field_contracts` instead of duplicating it in `variable_schema`.

**Constants on `MissionNodePlugin`:** `RESERVED_EXPRESSION_WORDS`, `INTERNAL_VARIABLES`.

**Singleton detection:** Nodes declare `singleton?` on the class; the registry stores it in metadata. `NodeConfigValidator`, palette view, and controller all read from the registry — no hardcoded `SINGLETON_TYPES` lists. JavaScript reads singleton types from `data-singleton-types` on the canvas element (serialized from backend `MissionNodePlugin.all_types`).

**Variable extraction:** `MissionsHelper#extract_workflow_variables` delegates to each node class's `extract_variables` method via `MissionNodePlugin.resolve`. No type-specific switch/case in the helper.

**React designer data flow:** The canvas element (`#mission-designer-root`) carries `data-singleton-types` (JSON array) and `data-node-type-metadata` (JSON map) from `MissionNodePlugin`. The palette serializes `output_ports` into each dragged node's data. Unknown node types fall back to `GenericNode.jsx` via a Proxy-based `nodeTypes` registry. The properties panel `#toggleTypeFields` detects config fields dynamically via `data-prop-for` matching — no hardcoded type lists.

## Test Suite Metrics

- Turbo Stream targets must be stable: `#test-run-header`, `#test-run-status-bar`.
- Test run pages use transient `turbo_stream_from` updates plus a Stimulus catch-up poll against the show route's `.turbo_stream` format; keep the run page `turbo-cache-control` meta set to `no-cache`.
- Per-test usage includes execution (`execution_context: :test`) and evaluation chats (`execution_context: :system`, linked via `parent_chat_id`).
- Show tokens as separate **input** / **output** values — never only a sum.
- Builtin test suites live in `config/builtin_tests/*.toml`, sync into Headquarter, and remain normal editable `TestSuite`/`TestCase` records. Preserve editable suite/case changes on ensure/sync and use explicit restore flows for shipped defaults.
- Agent-style behavior assertions live on `TestCase` and persisted evidence/debug data lives on `TestCaseResult`/`TestSuiteRun`; do not reintroduce external JSON benchmark reports.
- `TestSuites::CreateRunService` should keep accepting an optional `test_cases:` subset so runtime tools can run either a whole suite or a single selected test without cloning the execution path.
- The test-suite designer runtime path should run requested suites or single tests synchronously through the shared execution job, read failures from the resulting `TestSuiteRun`, and delegate to Agent or Mission Designer only after it has concrete failing details.
- Benchmark fixture runs such as `fixture_key: "agent_alpha_benchmark"` must delete every scenario-created agent/tool/mission/channel/skill/RAG/test-suite record after the result is evaluated while preserving the run and result rows.
- With `config.active_support.isolation_level = :fiber`, test suite execution/evaluation services should not introduce explicit DB locks or `Async::Semaphore` guards around ActiveRecord writes.

## Builtin Agent Records

Builtin/internal agents are normal `Agent` records synchronized from TOML definitions, not `RubyLLM::Agent` subclasses.

- Shared builtin web research is split between the runtime tool keys `web.web_search` and `web.web_fetch`, exposed to Agent Alpha and the designer builtins. Keep search provider implementations plugin-backed, use `web_search` only to discover relevant public URLs, and use `web_fetch` only for the smallest number of specific public pages needed. Provider-specific secrets must stay in encrypted connector-backed config owned by the relevant plugin; for example Brave Search uses its own connector plugin for the API key while DuckDuckGo remains unauthenticated. Both paths must validate hosts through `WebSearch::Safety`, cap downloaded bytes, and return focused snippets instead of whole-page dumps.

- The admin agent UI is split deliberately: `GET /admin/agents/new` and `GET /admin/agents/:id/edit` own configuration only, `GET /admin/agents/:id/edit_instructions` owns system instructions only, and input-parameter add/edit/remove flows live on the agent show page through the shared schema-fields dialog.

- **Never use `RubyLLM.chat` directly.** Route internal LLM work through `Agent#build_chat` / `Agent#configure_chat` or `BuiltinAgents::Runner`.
- App-owned builtin definitions live in `config/builtin_agents/*.toml`; plugin-owned definitions live in `plugins/**/config/builtin_agents/*.toml`.
- Builtin-agent instructions live in the same TOML file under the `instructions` key.
- `BuiltinAgents::Synchronizer` creates missing builtin agents in the `Headquarter` operation, preserves editable customizations during ensure/sync, and restores defaults on demand.
- Locked builtin attributes include `builtin_key`, `builtin_source`, builtin tool links, builtin subagent links, and `selectable`; editable fields such as name, description, instructions, temperature, and input schema are stored on the `Agent` record.
- Builtin agents can declare `llm_config_source` (`agent`, `system_preference`, `runtime`), `agent_type`, `input_schema`, `tools`, `subagents`, and `capabilities` in TOML. Use `capabilities = ["chat_title_generator"]` for default assignment or `[capabilities.<key>]` tables for custom capability settings. Keep `input_schema` as an inline array of objects rather than repeated `[[input_schema]]` blocks.
- Builtin agents can also declare `skill_catalogs` in TOML. Sync those by builtin catalog key and treat them as the shipped knowledge base for that builtin.
- Agent Alpha is a builtin that declares `subagents = ["mission_designer", "agent_designer", "tool_designer", "channel_designer", "skill_catalog_designer", "test_suite_designer"]` and the `chat_title_generator` capability by default; delegated subagent calls must inherit the current turn's runtime context so mission-scoped, agent-scoped, tool-scoped, channel-scoped, skill-catalog-scoped, skill-scoped, and test-suite-scoped builtins can bind to the active mission, agent, tool, channel, skill catalog, skill, or test suite page.
- Agent Alpha may take one narrow `list_resources` discovery step before delegation when the current page object, selected references, or an exact cross-domain ID genuinely needs disambiguation, and it may take at most one follow-up step after delegation when a designer subagent returns actionable `record_ids`, `warnings`, or `blockers` in the trailing `<child_result>` JSON block appended by `SubagentTool`. Keep direct delegation as the default, and keep connector creation out of scope.
- Agent Alpha regression coverage ships as builtin test suites under `config/builtin_tests/*.toml` and syncs into each tenant's Headquarter through `BuiltinTestSuites::Synchronizer`. Keep benchmark-style assertions on normal `TestCase` fields (`expected_child_builtin_key`, `expected_tool_names`, `disallow_child_chats`, `required_keywords`, `forbidden_keywords`) and store run evidence on `TestCaseResult` debug/evidence columns rather than writing JSON reports.
- Agent Alpha and its designer subagents must respect the same Pundit write guards as the admin UI. In Headquarter, keep builtin/resource discovery read-only and block all create, update, delete, capability, tool-action, flow-edit, and similar mutation tools through the shared policy layer, with the current app-level exception that built-in restore actions for agents, skills, and skill catalogs remain allowed there, including the bulk restore-defaults flows for agents and skill catalogs.
- Streamed subagent calls must return a meaningful parent-facing string even when the child chat's final assistant message is blank after a handoff-style tool such as `manage_record` with navigation. Fall back to the latest meaningful child assistant/tool message instead of returning an empty tool result to the parent, or Agent Alpha can keep looping on the same request.
- Agent Alpha also exposes `resources.list_resources` as a read-only discovery tool. Keep it limited to inspecting available resource kinds and IDs before answering directly; mission, agent, tool, channel, skill catalog, skill, test suite, and test create/update/troubleshooting requests should delegate to the specialized designer subagent first instead of using `list_resources` as a preflight step. Agent Alpha instructions should enumerate the core `list_resources` kinds (`agent_types`, `capabilities`, `models`, `default_models`, `tool_types`, `tools`, `runtime_tools`, `agents`, `missions`, `channels`, `skill_catalogs`, `skills`, `test_suites`) and tell the model to call it without `kind` first only when the available kinds are genuinely unclear.
- Agent Alpha should surface its designer subagent tools ahead of shared runtime discovery tools, but `SubagentTool` itself must stay generic: pass the delegated question through unchanged, and keep any specialized execution guidance or extra delegation context in the child agent's own instructions or other runtime prompt-building layers instead of hardcoding wrapper text in the tool.
- Agent Alpha should treat clone requests for agents, tools, and missions the same way it treats create/update requests: delegate them immediately to Agent Designer, Tool Designer, or Mission Designer instead of answering with static guidance.
- Agent-driven admin page moves should go through the shared `chat-stream` ActionCable payload type `navigate` so the browser uses a Turbo frame visit targeted at `turbo-frame#app-content-frame` instead of a full reload and the preserved Agent Alpha frame stays mounted.
- Agent Alpha should keep the shared area-based builtin skill catalogs attached so it can answer general product questions by activating the relevant shipped skills before responding.
- Keep shipped mission-design handbook content in the app-owned missions skill catalog instead of reintroducing a dedicated builtin handbook tool.
- Hardcoded runtime-only tools are registered via `BuiltinTools::Registry` and surfaced read-only in Headquarter. Built-in runtime tools that are safe for normal agents, such as `web.web_search` and `web.web_fetch`, must opt in with `user_assignable: true`; agent admin and runtime-record updates should filter `runtime_tool_keys` to those user-assignable definitions for non-built-in agents.
- In service specs, stub `allow_any_instance_of(Chat).to receive(:to_llm).and_return(double.as_null_object)` when a real chat instance is involved.

## Connector Architecture

**Configurator + single `connectors` table:** `Connector` is a thin AR model storing `connector_type` (string key) and `configuration` (JSONB). The LLM Provider connector is core app-owned under `app/models/connectors/llm_provider.rb`; extensible connector types are ActiveModel configurators loaded from plugins under `plugins/connector_<type_key>/`.

### ConnectorPlugin Protocol (`app/models/concerns/connector_plugin.rb`)
**Registry:** `ConnectorPlugin.type_map`, `ConnectorPlugin.resolve(key)`, `ConnectorPlugin.all_types`, `ConnectorPlugin.label_for(key)`, `ConnectorPlugin.icon_for(key)`.

**Each configurator implements (via `include ConnectorPlugin` + DSL):**
- Class DSL: `key`, `label`, `icon`, `description`, `sensitive_keys`
- Class: `permitted_params(params)` — returns hash of type-specific params from ActionController::Parameters
- Instance: `summary`, `form_partial_path`, `show_partial_path`
- Optional: `on_configuration_change(connector, old_config, new_config)` callback
- `_connector_record` accessor — reference to the owning `Connector` AR record (set by `Connector#build_configurator`)

### Connector Model (`app/models/connector.rb`)
- `connector_type` column identifies the connector type (e.g. `"sql_database"`, `"llm_provider"`)
- `configuration` JSONB column stores all type-specific attributes (encrypted via `EncryptedConfigurationJsonType`)
- `configurator` method builds and caches the ActiveModel configurator via `ConnectorPlugin.resolve(connector_type)`
- `method_missing` / `respond_to_missing?` delegates to configurator for transparent attribute access
- `before_save :apply_configurator_before_save` serializes configurator attributes back to `configuration`
- `before_update :notify_configurator_of_changes` calls `configurator.on_configuration_change` if defined
- Convenience scopes: `llm_providers`, `sql_databases`, `mcp_servers`, `authentications`

### Core Connectors

| Core Connector | Type Key | Notes |
|----------------|----------|-------|
| `Connectors::LlmProvider` | `llm_provider` | App-owned generic LLM provider connector with `PROVIDER_KEYS`, `build_context`, main-app views, Stimulus controller, and provider-fields route. Keep it out of the plugin registry. |

### Connector Plugins

| Plugin | Type Key | Notes |
|--------|----------|-------|
| `connector_sql_database` | `sql_database` | ADAPTER_TYPES, connection_string or field-based config |
| `connector_mcp_server` | `mcp_server` | stdio/sse/streamable_http transports, optional OAuth |
| `connector_authentication` | `authentication` | OAuth (Keycloak, Google), `for_provider`/`enabled_for_provider?` class methods |
| `connector_telegram` | `telegram` | Telegram credentials plus Bot API access for Telegram channels |

### View Rendering
- `ApplicationHelper`: `render_connector_form(connector)`, `render_connector_show(connector)`, `render_connector_partial(connector, partial_name)`, `render_plugin_profile_panels(user)` — prepend connector/plugin view path + scope lookup_context
- LLM Provider views live under `app/views/admin/connectors/llm_provider/`, its Stimulus controller lives in `app/javascript/controllers/llm_provider_connector_form_controller.js`, and `/admin/connectors/provider_fields` is handled by `Admin::ConnectorsController#provider_fields`.
- Plugin views at `plugins/connector_<type_key>/app/views/` with `_form.html.haml`, `_show.html.haml` at minimum
- SQL table/tool visibility UI is plugin/tool-owned; do not add SQL visibility templates under `app/views/connectors/**`
- **Connector show extras:** a configurator can implement `show_extra_partial_name` (default `nil`) to have an additional partial rendered on the connector show page.
- **Profile panels:** plugins can contribute panels to the user profile page by placing `profile/_profile_panel.html.haml` in their `app/views/` directory. `render_plugin_profile_panels(user)` discovers and renders all matching partials.
- Plugin-specific controllers/routes live inside the plugin.
- Plugin locale files at `plugins/<plugin>/config/locales/*.yml` are auto-loaded by the plugin loader.

### Plugin Isolation Rules
- Connector plugin specs live inside each plugin under `plugins/connector_<type_key>/spec/**`
- Connector plugin factories live inside each plugin under `plugins/connector_<type_key>/spec/factories/**`
- Plugin runtime dependencies must be declared in `plugins/<plugin>/Gemfile`; root `Gemfile` loads all plugin Gemfiles via `eval_gemfile`.
- Plugin schema migrations must live in `plugins/<plugin>/db/migrate`; plugin loader appends those paths to Rails `db/migrate` so `bin/rails db:migrate` runs them.
- For schema ownership moves between app and plugins, keep migrations schema-only and move existing data via Rails console/runner scripts (no data-copy SQL inside migrations).
- Plugin-specific routes/controllers must stay inside the plugin
- Plugin-specific Stimulus controllers must live inside the plugin at `plugins/**/app/javascript/controllers/**`; the app-owned LLM Provider controller is the exception and lives in `app/javascript/controllers/`.
- Connector test endpoints must be plugin-owned (e.g., `connector_sql_database`, `connector_mcp_server`); do not add generic test actions/routes to `ConnectorsController`.

### Adding a New Connector Type
1. Create plugin folder `plugins/connector_<type_key>/` with `plugin.rb` using `add_connector "<Label>"` DSL
2. Add configurator model in plugin `app/models/<type_key>.rb` with `include ConnectorPlugin`, implement protocol
3. Add view partials `_form.html.haml` + `_show.html.haml` in plugin `app/views/`
4. Optional: connection tester service, plugin-specific controller + routes
5. Specs + factory in plugin `spec/`

Connectors = connections only; schema/visibility live on tools.

`Connectors::Authentication` — OAuth config (site_url, realm, client_id, client_secret). Parent `Connector.enabled` controls login page visibility. Used by OmniAuth initializer dynamically.

## Channel Architecture

Channels are the new operation-owned invocation/exposure layer for agents and missions. A channel owns routing, enabled/default state, presentation/configuration, external identities, external conversation mapping, channel-specific credentials, and target assignment inside one operation. Connectors remain credentials/connectivity only, and capabilities remain agent behavior/extensions only.

- **Models:** `Channel` (`channel_type` + `configuration` JSONB, operation-owned via `operation_id`, optional `connector_id`, optional `default`, FriendlyId slug, logo attachment), `ChannelTarget` (polymorphic `Agent`/`Mission` target assignment), `ChannelIdentity`, `ChannelConversation`, and `ChannelCredential`.
- **Plugin protocol:** `ChannelPlugin` mirrors the connector/capability configurator pattern. Core app-owned types are `Channels::Client` and `Channels::Api`; plugin-owned channel configurators live under `plugins/**/app/models/channels/` and register through `add_channel` with `category [:channel]`.
- **Target rule:** `ChannelTarget` must validate target kind support from the configurator and enforce same-operation targets. Do not expose operation-owned records across workspace boundaries through channel assignments.
- **Credential rule:** channel API/form tokens live in `ChannelCredential` as digests with generated raw tokens shown once; connector secrets stay on connectors.
- **Runtime links:** `Chat` and `MissionRun` carry optional `channel_id`, `channel_target_id`, and `channel_conversation_id` while invocation surfaces migrate behind channels.
- **API route shape:** API channels invoke assigned targets through `/api/v1/channels/:channel_slug/targets/:target_slug/invocations`. Keep the controller keyed by `channel + target`, branch on the target kind, and reuse the existing mission-run or chat runtime instead of creating separate API-only execution stacks.
- **Channel chat runtime:** agent-target API invocations should create `Chat` rows with `execution_context: :channel`; keep `Chat#response_context` and `ChatResponseJob` treating that context as the shared agent-chat path rather than introducing a separate response job.
- **Refactor direction:** new publishing/invocation work should build on `Channel`; channels replace the old Client and ApiClient publication surfaces. Telegram, Slack, WhatsApp, and similar integrations should be connector + channel, not agent capabilities.
- **Telegram plugin rule:** keep Telegram self-contained as connector + channel inside `plugins/telegram/`. `Channels::Telegram` owns webhook routing, account linking, and default-target invocation; linked accounts use `ChannelIdentity`, external chats use `ChannelConversation`, and pending `/link` state stays plugin-local in `Channels::TelegramLinkRequest` rather than user columns or app-level tables.

## Client-Type Channels

Client-type channels customize the end-user chat experience (branding, messaging, default agent target, and preview behavior). Manage them through `/admin/channels` with `channel_type = "client"`.

- **Attributes:** `name` (unique per operation), `channel_type = "client"`, `configuration` (JSONB-backed chat copy/settings), `default` (boolean), default agent target, and `logo` (Active Storage attachment).
- **Configuration:** keep client-facing chat copy in the client channel configuration via `Channels::Client`. Rich content such as `title`, `welcome_message`, and `footer` stays sanitized HTML, while chat/menu/button labels are plain text settings exposed through `Channel#settings_payload`.
- **Rich text editing:** Lexxy editor (`<lexxy-editor>` custom element) with attachments disabled globally. Gem pinned via importmap; CSS loaded in admin layout.
- **Sanitization:** `Channels::Client` strips disallowed HTML through `Rails::HTML5::SafeListSanitizer`. Allowed tags: p, br, strong, em, b, i, u, s, a, ul, ol, li, h1-h6, blockquote, code, pre, span, sub, sup. Allowed attributes: href, target, rel, class.
- **Caching:** `Channel.current_client_channel` and `Channel.current_client_settings` cache the default client-type channel payload per operation for the public chat layout and preview surfaces.
- **Default flag:** keep one default client-type channel per operation so public `/chat` resolution uses the active workspace's primary branding source.
- **Chat UI:** `chat.html.haml` layout and `chats/index.html.haml` render branding from the current client-type channel instead of hardcoded values.
- **Chat scoping:** user-facing chats now carry an optional `channel_id`. Public `/chat` routes scope chats to the current client-type channel, and admin preview mode reuses the shared chat stack by passing preview-channel context into `ChatsController` and `MessagesController`.
- **Admin preview:** client-type channel cards and show pages open the live preview through `admin_channel_path(channel, view: :preview)`, rendered inside the normal admin content frame with that channel's branding, footer, history, and shared chat shell.
- **Agent Alpha support:** channel-focused Agent Alpha turns should delegate to `channel_designer` and keep channel CRUD/navigation on the shared `RuntimeRecords::Registry` path rather than adding client-only runtime mutation code.
- **Preview refresh rule:** when the current admin page is a client-type channel preview, record refreshes triggered by Agent Alpha must reuse the exact current preview path, including any `chat_id` or other preview params, instead of switching back to the canonical show route.

## Tenant Architecture

Tenants are the top-level isolation boundary. Operations remain tenant-local workspaces, not tenants.

- **Model:** `Tenant` — `name` (unique), FriendlyId slug, `description`, `has_many :operations`, `has_many :users`, `has_many :connectors`, `has_one :system_preference`.
- **Core resources:** every tenant bootstraps `Headquarter` and `Default` operations through `Tenant#ensure_core_resources!`. Builtin agents sync into each tenant's `Headquarter`, and normal admin work defaults to that tenant's `Default` operation.
- **Tenant lifecycle:** tenant creation must provision one local tenant-admin account using the email entered on the tenant form, with a generated password shown only once to the system administrator on the post-create redirect. Tenant deletion should purge tenant-owned records before removing the tenant row instead of relying on empty-tenant preconditions, and the default tenant must not be deletable.
- **Roles:** `system_admin` is global and can manage tenants, but tenant-scoped admin work should happen through tenant-local accounts. `admin` is tenant-scoped and only manages records inside the current tenant. `admin?` includes both roles when a controller only cares about admin-surface access.
- **User admin scope:** the normal admin users CRUD surface is tenant-scoped even for `system_admin`; load users through `current_tenant.users`, keep create/update params pinned to the current tenant, and reserve cross-tenant administration for the dedicated tenant-management surfaces.
- **Session:** `current_tenant` on `ApplicationController` resolves directly from the signed-in user's tenant. Do not add tenant-switch session state or UI back into the app.
- **Tenant login URLs:** tenant-local admins and users sign in through `/tenants/:tenant_id/login`, which only authenticates accounts that belong to that tenant.
- **Tenant login UI:** tenant-specific login URLs must render the exact same generic login surface as `/login` with no tenant banner, tenant name, or extra tenant-only copy visible in the page chrome.
- **Global tenant-owned models:** `User`, `Operation`, `Connector`, and `SystemPreference` carry a non-null `tenant_id`. Channels remain tenant-contained through their owning operation.
- **Scoped helpers:** use `scoped_operations`, `scoped_connectors`, `scoped_channels`, `tenant_scoped_test_suites`, `tenant_scoped_mission_runs`, and `tenant_scoped_chats` from `ApplicationController` instead of global queries. `scoped_channels` is operation-scoped.
- **Tenant authorization guardrail:** tenant-owned admin flows must keep tenant-scoped record loading and explicit Pundit authorization together. Back tenant-owned and operation-owned policies with shared tenant-aware helpers in `ApplicationPolicy`; never leave those policies as unconditional `true` because a future controller-scope regression would become a cross-tenant leak.
- **Tenant authorization strictness:** shared tenant-aware helpers in `ApplicationPolicy` must deny foreign-tenant tenant-owned and operation-owned records for every role, including `system_admin`; reserve any global system-admin exceptions for explicit tenant-management policies such as `TenantPolicy`, and keep runtime mutation tools on the same scoped lookup plus policy path.
- **Tenant UI visibility:** keep tenant names and tenant selectors out of normal admin chrome and user CRUD screens. Tenant management belongs on the dedicated system-admin tenant screens, not the shared sidebar header or standard user list/form surfaces.
- **Connector ownership rule:** when code handling a tenant-owned record (agent capability, tool configuration, rag step, mission node, presenter state, or API/admin request param) already knows the owning tenant, resolve connector ids through that tenant's connectors instead of direct global `Connector.find` / `Connector.find_by` calls.
- **Background job scoping rule:** when enqueueing a background job for a tenant-owned or operation-owned record and the caller already knows the tenant, pass that `tenant_id` explicitly and re-scope the lookup inside `perform` before mutating or executing against the record. Do not rely on bare global `find` calls in jobs for mission runs, chats, tools, test suites, RAG flows/runs, API callbacks, or connector-backed plugin jobs when tenant context is available.
- **Copilot instruction rule:** when adding a new resource, decide first whether it belongs directly to a tenant or to an operation. Cross-workspace configuration belongs to `Tenant`; workspace content belongs to `Operation`. Add the FK, associations, controller scoping helper, and policy updates together.

## Operations Architecture

Operations are logical workspaces inside a tenant. Every `Agent`, `Mission`, `Tool`, `SkillCatalog`, and `RagFlow` carries a non-null `operation_id` FK and is only visible when that operation is active.

- **Model:** `Operation` — `name` (unique), `slug` (FriendlyId), `description`, `icon` (FA class), `system` boolean. Scopes: `ordered`, `headquarter_first`, `user_managed`.
- **Ownership:** every operation belongs to a tenant and names are unique per tenant, not globally.
- **System operations:** `Headquarter` (always shown first) and `Default` (session fallback) are created per tenant through `Tenant#ensure_core_resources!`. `Headquarter` is system-only and cannot be deleted.
- **Headquarter mutability rule:** treat `Headquarter` as browse-only for operation-owned resources. Gate writes through shared policies so normal controllers, admin UI, runtime mutation tools, and Agent Alpha all deny create/update/delete-style operations there with the same reason string, while keeping built-in restore actions for agents, skills, and skill catalogs explicitly allowed in Headquarter, including the bulk restore-defaults flows for agents and skill catalogs.
- **Session:** `current_operation` on `ApplicationController` reads `session[:current_operation_id]`, falls back to `current_tenant.default_operation`, and writes the resolved ID back on every request.
- **Mission deep-link rule:** mission record routes (`Admin::MissionsController`, `Admin::MissionFlowsController`, `Admin::MissionDebugRunsController`) must resolve the mission through the current tenant, then adopt `mission.operation` into `session[:current_operation_id]`, `@current_operation`, and `Current.operation` for that request before continuing. Direct mission URLs and Agent Alpha `navigate_to_page` handoffs must land in the mission's owning operation even when the previous admin session was still on another workspace.
- **Scoping helpers** (on `ApplicationController`): `scoped_agents`, `scoped_missions`, `scoped_tools`, `scoped_skill_catalogs`, `scoped_rag_flows` — each calls `Model.where(operation: current_operation)`. All admin index controllers use these; never query resources without them.
- **Switching:** `POST /admin/operations/:id/switch` must scope the lookup through `current_tenant.operations` before writing `session[:current_operation_id]`. It redirects back by default, and the sidebar switcher passes a filtered dashboard target so the user lands on `admin_root_path(operation: operation.slug)`.
- **URL-based filter:** Dashboard, Inspector Chats, and Mission Control Runs accept `?operation=<slug>` to filter without touching the session. Resolved via `Operation.friendly.find(params[:operation])`.
- **New resources:** Controllers pass `operation: current_operation` when building new records (`Agent.new(operation: current_operation)`, etc.) and should never build operation-owned records from a tenant-unscoped query.
- **Deletion guard:** `Operation#destroyable?` returns `false` when `system?` or any `has_many` association is non-empty. `OperationPolicy#destroy?` enforces this.
- **Sidebar switcher:** Renders `current_tenant.operations.headquarter_first`. Dashboard quick-actions bar has an identical custom dropdown reusing the `operation-switcher` Stimulus controller.
- **Copilot instruction rule:** When adding a new resource type that should be operation-scoped, add `belongs_to :operation` + `operation_id` FK migration, add a `has_many` on `Operation`, add a `scoped_<plural>` helper to `ApplicationController`, and use it in the resource's admin controller index/create.

## Inspector Architecture

`/inspector/chats` — two-panel: searchable sidebar + chat/message detail. Keep views up to date when `Chat`/`Message`/`ToolCall` models change. Stimulus: `inspector-search`, `inspector-collapse`. Subscribes to `inspector_chat_<id>` Turbo Stream for live title updates.

## Agent Capabilities Architecture

Plugin-style functionalities via **JSONB-backed configurators** (`CapabilityPlugin`). Self-contained — no capability-specific code in `AgentsController`.

- `Capability` state is stored in `Agent.configuration["capabilities"]`; a capability is active as soon as it is assigned, and disabling is done by removing it rather than toggling an `enabled` flag in the admin UI.
- `CapabilityPlugin` concern (`app/models/concerns/capability_plugin.rb`) — registry (`type_map`, `resolve`, `all_types`) and metadata DSL (`key`, `label`, `icon`, `description`).
- `HasCapabilities` concern on `Agent` — `capability(:key)` and `capability_enabled?(:key)` resolved dynamically via `CapabilityPlugin`.
- Each capability configurator implements: `permitted_params`, optional `event_handler_class`, `summary`, and optional `form_locals` (plugin-owned locals injected into the capability form render path).
- Event system: `Capabilities::EventDispatcher.dispatch(:event, **payload)` → finds assigned capabilities → calls `handler.handle(event, **payload)`. **Never hardcode capability calls in jobs/controllers.**
- Each capability has its own form at `.../capabilities/:key/edit` via `CapabilitiesController`.
- Capability edit screens configure settings only; do not add enable/disable toggles there. Capability removal from the agent is the off switch.
- Deep-cloned with agents via amoeba `customize` lambda.
- Interactive capability UI must remain plugin-owned. If a capability needs runtime chat widgets, keep the routes/controllers, services, Stimulus controller, styles, and any `ToolCall`/message extension modules inside the plugin. Persist live widget state on existing runtime records such as `ToolCall.arguments` unless a separate table is materially required.
- If a plugin persists widget-only state on `ToolCall.arguments`, keep the canonical runtime tool arguments recoverable for history serialization. Expose a plugin-owned `arguments_for_llm` override on the `ToolCall` extension when the LLM should see only a sanitized subset of those persisted fields.
- Plugins must not dispatch `ChatResponseJob` directly. Hand follow-up prompts to `Chat#enqueue_response!(content:, attachment_signed_ids: [])` and keep execution-context routing inside the main app.

**Chat Title Generator** (`:chat_title_generator`, plugin `plugins/capability_chat_title_generator`): `max_length`, `max_turns`, `llm_config_source`, `llm_connector_id`, `model_id`, `temperature` stored in `capabilities.configuration`. The plugin ships a builtin-agent definition plus prompt in the same plugin, and `Capabilities::TitleGenerationService` handles `:chat_response_completed` broadcasting title updates to `chat_stream_<id>`.

**Human in the Loop** (`:human_in_the_loop`, plugin `plugins/capability_human_in_the_loop`): exposes the runtime `ask_user_questions` tool, stores each live clarification request directly on `ToolCall.arguments`, renders a plugin-owned widget from the persisted tool call through the shared chat tool-call surface, suppresses the default compact tool-call row for those calls, and resumes the correct chat job after the user submits answers. Keep its persisted widget state serializable back to the UI while exposing only runtime-safe `prompt`/`questions` through `arguments_for_llm`, or later turns can replay answered widget state as invalid tool-call arguments. Prefer structured `questions` objects with `prompt` + `options`; the runtime also normalizes legacy inline `Question N: ... Options: ...` strings when models emit them and truncates overflow options to the configured limit because the widget always includes a custom-answer field.

**Adding a capability:** create plugin + manifest (`add_capability`) → configurator model with `CapabilityPlugin` + `Configurator` → plugin form partial + optional event handler service → plugin-local specs/factories.

## RAG Architecture

Modular rag system with **4 fixed stages** (source → chunking → embedding → storage). `RagFlow` under the **Build** sidebar section.

### Models
- **`RagFlow`** — FriendlyId slug, has many steps (one per stage) and runs. Amoeba clones steps, excludes runs.
- **`RagStep`** — `delegated_type :steppable` (14 types). `stage` column. Delegates `execute`, `each_batch`, `validate_configuration!`, `summary` to steppable.
- **`RagRun`** / **`RagStepRun`** — execution records with status enum, JSONB stats, Turbo Stream progress broadcasts.
- RAG run progress broadcasts are best-effort. On PostgreSQL pubsub, rendered Turbo Stream payloads can exceed the `NOTIFY` size limit; `RagRun#broadcast_progress` must log and skip broadcast failures instead of aborting the job, and the runs page should recover through its `.turbo_stream` catch-up refresh.

### Stages & Modules

| Stage | Active |
|-------|--------|
| Source | `SqlDatabaseSource` |
| Chunking | `FixedSizeChunker`, `ParagraphChunker`, `MarkdownChunker`, `SentenceChunker` |
| Embedding | `LlmEmbedder` |
| Storage | `SqlDatabaseStorage` |

### RagStepPlugin Protocol (`app/models/concerns/rag_step_plugin.rb`)
**Registry:** `RagStepPlugin.type_map`, `RagStepPlugin.stage_map`, `RagStepPlugin.resolve(key)`, `RagStepPlugin.modules_for_stage(stage)`.

### Rag Plugin Manifest DSL
- Plugin manifests are declared via `UndercoverAgents::PluginSystem.register("<identifier>") do ... end` using instance DSL methods.
- Use metadata methods (`name`, `version`, `author`, `description`, `icon`) and set `category` as an array (e.g., `[:rag_chunking]`).
- Rag step entry points must use `add_rag_input`, `add_rag_chunker`, `add_rag_embedding`, `add_rag_storage`.
- Pass unnamespaced class names to rag entry points (e.g., `add_rag_embedding "LlmEmbedder"`), not `RagSteps::...`.
- Do not use `stage`, `type_key`, or `type_class_name` metadata in manifests.

**Each steppable implements:** `key`, `label`, `icon`, `stage`, `description`, `permitted_params`, `build_from_params`, `execute(documents, context)`, `each_batch(context, &block)` (sources), `validate_configuration!`, `summary`, `form_partial_path`.

### Runtime Data Structures (not persisted)
- `Rag::Document = Data.define(:id, :content, :metadata, :chunks)`
- `Rag::Chunk = Data.define(:content, :position, :metadata, :embedding)`
- `Rag::StepContext = Data.define(:run_id, :flow_id, :batch_number, :total_batches, :metadata)`

### Services
- **`Rag::PipelineExecutor`** — orchestrates batch run: source yields batches → chunking → embedding → storage. Creates Run + StepRun records.
- Rag-step runtime code is plugin-local under each module plugin folder in `plugins/<type_key>/app/services/`.
- Keep plugin service paths flat under `plugins/*/app/services/` when possible (avoid unnecessary nested folders).

### Controllers & Views
- `RagFlowsController` — CRUD + toggle + execute.
- `Rag::StepsController` — stage-based editing via `param: :stage`. `edit` renders module selection (no step) or config form (step exists or `module_type` param). `update` creates/updates/switches. No `new` action.
- `Rag::RunsController` — index, show, cancel.
- Views under `app/views/rag_flows/` and `app/views/rag/steps/`.
- Rag-step module forms must be named `_form.html.haml` and live at the root of the plugin's `app/views/` directory: `plugins/<plugin>/app/views/_form.html.haml`. `RagStepPlugin#form_partial_path` returns the absolute path to that directory. `ApplicationHelper#render_rag_step_form` scopes the view lookup to the plugin's views directory before rendering so Rails finds the right `_form` with zero cross-plugin naming conflicts. Plugins hosting multiple module types (e.g. `rag_sql_database`) override `form_partial_path` to a type-keyed subdirectory (`app/views/<type_key>/`), keeping `_form.html.haml` as the filename.
- Rag-step module partials must receive a form builder local (`f`) from `app/views/rag/steps/edit.html.haml` and use builder helpers (`f.label`, `f.text_field`, `f.select`, etc.) so params stay model-scoped (e.g., `fixed_size_chunker[chunk_size]`) without manual `*_tag` naming.
- `SqlDatabaseSource` now uses a plugin-owned wizard flow. Persist wizard state in the step configuration JSONB (`source_mode`, `selected_object_name`, `selected_object_type`, `record_limit`) and regenerate the stored `query` whenever table/view mode is active so runtime execution still reads from `query` only. Keep its schema/query inspection endpoints and Stimulus controller inside `plugins/sql_database/`.
- Plugin-specific rag AJAX endpoints must live in the plugin itself (`plugins/<type_key>/config/routes.rb` + `plugins/<type_key>/app/controllers/**`).

### Shared Embedding Model Options
`embedding_model_options` is a shared collection route on `AgentsController`. Accepts `frame_id`, `field_prefix`, and `connector_id` as params. Used by both tools (RAG Query) and rag steps (LLM Embedder) to fetch embedding models for a given LLM connector. Uses `ModelOptionsSupport#models_for_connector`.

### Shared Model Options
`model_options` is also a shared collection route on `AgentsController`. Accepts `frame_id` (required), `field_prefix` (required), and optionally `field_name`, `required`, `connector_id`, `selected_model_id`. Used by agents, tools (including SQL Query runtime LLM config), test suites, and capabilities. The config keys `:field_name` and `:required` are forwarded to the `shared/model_select` partial via `ModelOptionsSupport#render_model_options`. Views bake static params into the URL; JS controllers only append `connector_id`.

Model picker options should include capability metadata (`supports_temperature`, `supports_reasoning`) in `data-custom-properties` so shared Stimulus controllers can enable or disable temperature/reasoning controls without provider-specific hardcoding.

### Adding a New Module
1. Create plugin folder `plugins/<type_key>/` and add the step model in `app/models/` with `include RagStepPlugin`, implement protocol.
2. Register the plugin entry point in `plugin.rb` using the plugin DSL (`category [...]` + matching `add_rag_*` method). Add the type to `RagStep`'s `delegated_type`.
3. Migration for new table. Executor service if needed. View partial at `plugins/<plugin>/app/views/_form.html.haml` (`form_partial_path` returns the absolute path to `app/views/`; `render_rag_step_form` in `ApplicationHelper` finds it automatically). Specs + factory.
4. **If the module needs custom AJAX actions:** add plugin-local routes under `plugins/<type_key>/config/routes.rb` and handle requests in plugin controllers under `plugins/<type_key>/app/controllers/**`.

### Plugin Isolation Rule
- Rag-step plugin logic must stay under `plugins/**`.
- Rag-step plugin specs must live inside each plugin under `plugins/<type_key>/spec/**`.
- Rag-step plugin factories must live inside each plugin under `plugins/<type_key>/spec/factories/**`.
- Shared rag-step runtime classes `Rag::Chunking::Base` and `Rag::Steps::ChunkerExecutor` live in `app/services/rag/` and are used by every chunking plugin. Do not redefine them inside plugin directories; subclass `Rag::Chunking::Base` for new strategies and let the shared executor drive them.
- Cross-plugin SQL connection setup is shared through `app/models/concerns/sql_connection_config_builder.rb`, and SQL error sanitization is shared through `app/models/concerns/sql_error_sanitizer.rb`; rag-step plugins should keep only thin wrapper concerns that include these shared modules. Shared SQL connection behavior should attempt URL-based `PG.connect` first and fall back to field-based params when malformed connection strings raise `string not matched`.
- Do not place rag-step executors, chunking services, or plugin-specific DB helpers in `app/services`.
- Do not add shared rag-step runtime folders: each rag-step plugin must keep its own runtime/helper code inside its own plugin directory.
- Keep plugin paths flat: use `app/models/*` and `app/services/*` (avoid extra namespace folders like `app/models` or deeply nested service folders).
- Plugin-specific routes/controllers must stay inside the plugin (do not add rag-step custom endpoints to app-level controllers/routes).
- Rag-step Stimulus controllers must live inside the plugin at `plugins/**/app/javascript/controllers/**`, not `app/javascript/controllers`.
- Importmap pins plugin controllers dynamically from `plugins/**/app/javascript/controllers`, so plugin JS should not require app-level per-plugin pin entries.

## System Preferences

`SystemPreference` — singleton model storing system-wide model configuration. Admin-managed at `/admin/preferences`.

- **Attributes:** `llm_connector_id` + `model_id` (default model), `embedding_connector_id` + `embedding_model_id` (default embedding model), `image_connector_id` + `image_model_id` (default image model). All FKs to `connectors`.
- **Caching:** `SystemPreference.current_settings` returns a cached hash. Invalidated via `after_commit`. `SystemPreference.llm_configured?` checks default model fields.
- **Singleton access:** `SystemPreference.current` returns the single instance (via `first_or_create!`).
- **Context:** `#resolve_llm_context`, `#resolve_embedding_context`, `#resolve_image_context` build `RubyLLM::Context` from the configured connectors.
- **Configured checks:** `#configured?` (default model), `#embedding_configured?`, `#image_configured?`.
- **Default LLM options:** System preferences store the tenant default LLM connector/model plus temperature, reasoning effort/budget, and provider custom params. Agents and mission `llm` nodes that use `system_preference` inherit that whole option set.
- **Generate Text source modes:** mission `llm` nodes use `llm_config_source` values `node`, `system_preference`, and `runtime`. Omitted connector/model settings normalize to `system_preference`; explicit connector/model settings normalize to `node`; `runtime` merges caller `_llm_config`/`llm_config` over system preference and falls back to system preference when caller values are absent.

### Mission Designer Builtin Agent

The mission designer uses the builtin `mission_designer` agent definition synced into Headquarter.

- It uses `llm_config_source: system_preference`, so it raises through normal agent runtime resolution when the default model is not configured.
- It declares mission-designer structure-editing tools through `tools` and handles workflow code, prompt, and expression authoring directly; do not reintroduce helper-subagent dependencies for that builtin.
- It uses `manage_record(action: "clone", resource: "mission", ...)` for mission cloning, which should open the cloned mission in the designer and allow same-turn follow-up flow edits through the returned `mission_id`.
- It also exposes `run_mission_debug` and `read_mission_run` for persisted debug execution and run inspection. Keep `run_mission_debug` opt-in only at the agent-instruction level rather than via regex guards in the tool implementation. Delegated subagent calls now arrive as plain request text, so do not reintroduce wrapper parsing for `User request:` blocks in mission-designer tools. Treat concrete sample usernames, emails, IDs, slugs, and similar values from mission test requests as runtime payload inputs, keep existing dynamic references such as `{{username}}` in the flow, and only hardcode those values if the user explicitly asked to change the workflow. Treat `payload` as the mission input/trigger data and reserve optional `variables` for extra debug-only values.
- It should treat straightforward built-in-node workflows such as `input` + `http_request` + `json_extract` + `llm` + `output` as direct mission authoring work, not tool design. Prefer `manage_record` plus `apply_flow_patch` before node-type docs or shared resource discovery, and keep resource lookups for genuinely resource-backed nodes or ambiguous cases.
- For a plain `input` + `llm` + `output` flow, let the edge carry the incoming user data into the `llm` node and treat `llm.prompt` as model instructions instead of echoing the input with `{{...}}` unless a real text template is required.
- Mission flow edits should default straightforward `llm` nodes to `llm_config_source: "system_preference"` when the user did not ask for a specific model, use `"node"` only for explicit node-level connector/model/temperature/thinking/custom overrides, and use `"runtime"` when the caller will supply `_llm_config` at run time with system preference fallback.
- Mission-variable helper tools such as `manage_global_variables` and `list_node_variables` must build cleanly even before a mission exists, accept `mission_id` for a mission created earlier in the same turn, and only return a clear "create or open a mission first" message when invoked too early. `list_node_variables` should also accept batched `node_ids` so the agent can inspect multiple consuming nodes in one call.
- Mission Designer should treat names returned by `list_node_variables` as identifiers, not pre-rendered template strings. Wrap them in `{{...}}` only for template-valued fields such as `json_extract.source`, `http_request.url`, `llm.prompt`, and `output.response_body`; keep them bare for `selected_variables`, mission test `expected_variables`, collection refs, and formulas.
- `temp_id` is only for same-turn patch wiring. It is not a variable prefix. `apply_flow_patch` may normalize same-patch `temp_id` variable references to the real reported prefix, but mission-designer authoring should still follow the returned `var_prefix` or `list_node_variables` identifiers after the patch instead of reusing `temp_id` in later edits.
- `set_variable` config uses `assignments` object maps, not `variables` arrays, and globals remain seeded inputs/constants only. Do not create blank or sentinel globals for values the flow computes later; use node outputs or `set_variable` instead.
- Once Mission Designer has a valid, warning-free flow that already satisfies the user's request, it should stop instead of doing reassurance reads or speculative follow-up patches. Do not invent optional convenience inputs or override knobs such as `endpoint_override` unless the user explicitly asked for that flexibility; if endpoint/auth config already lives in globals, keep it there.
- Structured mission-tool arguments such as `apply_flow_patch` must stay strict JSON with double-quoted keys and strings, no comments, no trailing commas, and no Markdown code fences.
- It follows a least-powerful-node policy: prefer dedicated nodes such as `json_extract`, `text_template`, `set_variable`, and the collection nodes before `code`; use `code` only when existing nodes cannot express the behavior. For HTTP JSON responses, default to `json_extract` instead of Ruby parsing.
- Mission flow-edit tools should reject omitted or invalid `source_port` values for multi-output nodes such as `http_request`, `condition`, `filter`, `iterator`, `loop`, and `switch` instead of silently persisting `default` edges that the designer cannot render correctly.
- `apply_flow_patch` update entries use the single canonical mission-designer shape: `id` plus optional `name` and `config`, matching `read_mission_flow` output.
- Jobs/controllers should configure it through `BuiltinAgents::Runner.configure_chat!(builtin_key: "mission_designer", ...)`.

### Agent Designer Builtin Agent

The agent designer uses the builtin `agent_designer` agent definition synced into Headquarter.

- It uses `llm_config_source: system_preference`, so it raises through the normal agent runtime resolution when the default model is not configured.
- It inspects agent state through `read_agent`, discovers valid IDs and capability field schemas through `list_resources`, and changes capability assignments/config through `manage_capability`; use those tools before mutating replacement fields.
- It also troubleshoots agent runtime behavior through `read_agent_chat` for recent chats or one persisted transcript and `debug_agent` for synchronous repro prompts. Keep those tools scoped to the current agent or a specified agent ID, authorize them through the same tenant-scoped agent policy path, and format chat/message output from persisted `Chat`/`Message`/`ToolCall` data so Agent Alpha sees the same diagnostic facts as the inspector.
- It edits agent records through the generic `manage_record` and `navigate_to_page` builtins with `resource="agent"`, using `assigned_tool_ids` for existing tools and `subagent_ids` for existing subagents. Agent cloning also goes through `manage_record(action: "clone", resource: "agent", ...)`. Treat `navigate_to_page` as a post-change UI handoff only; it does not return page content or agent data.
- It uses `manage_agent_action` for non-CRUD admin actions such as restoring one built-in agent or the Headquarter-wide built-in agent defaults.
- New agent records default to `agent_type = "general"`. Agent Designer should omit `agent_type` on create unless the user explicitly asked for a different type, and the runtime create path should coerce unspecific Agent Designer creates back to `general`.
- Turning off thinking/reasoning on an agent means explicitly storing `thinking_effort = "none"` and clearing `thinking_budget`; blank reasoning updates should remain blank/default instead of being normalized provider-specifically.
- Capability configuration goes through the dedicated `manage_capability` builtin rather than `manage_record`, so capability validation and callbacks still flow through the capability plugin configurators.

### Channel Designer Builtin Agent

The channel designer uses the builtin `channel_designer` agent definition synced into Headquarter.

- It uses `llm_config_source: system_preference`, so it raises through the normal agent runtime resolution when the default model is not configured.
- It inspects channel state through `channel_designer.read_channel`, discovers valid channel IDs through `list_resources(kind: "channels")`, and edits channel records through the generic `manage_record` and `navigate_to_page` builtins with `resource="channel"`.
- It uses `manage_channel_action` for non-CRUD admin actions such as API token rotation and supported channel-type webhook setup.
- Channel runtime context should resolve the active `Channel` from Agent Alpha page context so delegated turns can reuse the currently open record without forcing an ID lookup first.
- Client-type channel create flows should default to the preview page, while other channel types default to the standard show page. `navigate_to_page(resource: "channel", ...)` remains a post-change UI handoff only; it does not return page content.
- When Agent Alpha mutates a client-type channel while the preview pane is open, the follow-up refresh must preserve the exact current preview URL, including preview-specific params such as `chat_id`, instead of recomputing the canonical show path.

### Skill Catalog Designer Builtin Agent

The skill catalog designer uses the builtin `skill_catalog_designer` agent definition synced into Headquarter.

- It uses `llm_config_source: system_preference`, so it raises through the normal agent runtime resolution when the default model is not configured.
- It inspects skill catalog state through `skill_catalog_designer.read_skill_catalog`, discovers valid catalog IDs through `list_resources(kind: "skill_catalogs")`, and edits skill catalog records through the generic `manage_record` and `navigate_to_page` builtins with `resource="skill_catalog"`.
- It also inspects individual skills through `skill_catalog_designer.read_skill`, manages skill CRUD/import/restore through `skill_catalog_designer.manage_skill`, and manages catalog import/restore/restore-defaults plus agent attach/detach through `skill_catalog_designer.manage_skill_catalog_action`.
- Skill imports and skill resource uploads use attachments from the latest user message in the current Agent Alpha turn; when multiple archive files are attached, the runtime tool should require an explicit attachment filename instead of guessing.

### Test Suite Designer Builtin Agent

The test suite designer uses the builtin `test_suite_designer` agent definition synced into Headquarter.

- It uses `llm_config_source: system_preference`, so it raises through the normal agent runtime resolution when the default model is not configured.
- It inspects test suite state through `test_suite_designer.read_test_suite`, reads suite execution history through `test_suite_designer.read_test_suite_run`, and keeps suite CRUD on the generic `manage_record` builtin with `resource="test_suite"`.
- It manages nested test CRUD through `test_suite_designer.manage_test_case` instead of `manage_record`, so prompt/expected-answer fields and mission-variable hashes stay type-aware.
- Agent test cases may include behavior assertions (`expected_child_builtin_key`, `expected_tool_names`, `disallow_child_chats`, `required_keywords`, `forbidden_keywords`) plus benchmark metadata (`scenario_key`, `category`, `complexity`, `fixture_key`). The `agent_alpha_benchmark` fixture key provisions temporary operation-owned records for that one case and must clean them after evaluation while preserving suite run/results.
- It runs a whole suite or one selected test synchronously through `test_suite_designer.manage_test_suite_action`; that runtime path should reuse `TestSuites::CreateRunService` plus `TestSuiteExecutionJob.perform_now` so the agent can inspect failures in the same turn.
- After a failed run, it should fix test-suite-owned problems directly and delegate only once to Agent Designer or Mission Designer when the concrete failure details show the defect belongs to the target agent or mission rather than the suite itself.
- `navigate_to_page(resource: "test_suite", ...)` remains a post-change UI handoff only; it does not return page content or run data, and after it moves to another suite page the current turn should stop making more record-edit calls.

### Tool Designer Builtin Agent

The tool designer uses the builtin `tool_designer` agent definition synced into Headquarter.

- It uses `llm_config_source: system_preference`, so it raises through the normal agent runtime resolution when the default model is not configured.
- The shared top-level `ListResourcesTool` is exposed once through the generic builtin key `resources.list_resources` and reused by `mission_designer`, `agent_designer`, and `tool_designer`; keep generic resource discovery there instead of duplicating designer-specific registrations.
- It inspects tool state through `read_tool`, discovers valid tool types and resource IDs through `list_resources`, and reads plugin-declared config/action guidance through `get_tool_type_info`. Plugin-specific state labels, lookup kinds, action arguments, action policy mapping, and field-ID hints must come from connector/tool plugin metadata, not hardcoded cases in the main app.
- It edits tool records through the generic `manage_record` and `navigate_to_page` builtins with `resource="tool"`, using nested `toolable_attributes` for type-specific config. Tool cloning also goes through `manage_record(action: "clone", resource: "tool", ...)`. Treat `navigate_to_page` as a post-change UI handoff only; it does not return page content or tool data.
- Discovery, visibility updates, and other plugin-declared admin actions go through the dedicated `manage_tool_action` builtin rather than direct JSON mutation, so existing tool-plugin behavior stays the single source of truth through `perform_tool_designer_action!`. SQL Query tools auto-generate their instructions from discovered visible schema instead of using separate analysis or instruction-generation agents.

### Mission Designer Runtime

Mission-scoped builtin turns still run through the builtin `mission_designer` agent, but the dedicated mission-sidebar chat surface has been removed in favor of the shared Agent Alpha panel.

- **Job:** the shared `ChatResponseJob` derives mission-designer context from `Chat#response_context` and uses `BuiltinAgents::Runner.configure_chat!(builtin_key: "mission_designer", ...)`.
- **UI:** Mission designer pages rely on the shared Agent Alpha sidebar panel for interactive assistance. Do not reintroduce a separate mission-chat tab, route stack, or feature-local chat variant.
- **Lifecycle + navigation tools:** Mission Designer can use the generic builtin `manage_record` and `navigate_to_page` tools, both backed by `RuntimeRecords::Registry`. Keep those tools resource-agnostic, register supported resources there, scope operation-owned records through the current operation and tenant, and treat `navigate_to_page` as a final UI handoff only after update work or after creates/clones that did not already navigate; it does not read page content or return mission data. When the agent must create or clone and fully author a mission in one turn, let `manage_record` navigate to the designer immediately, then target that returned mission through the mission-designer tools' explicit `mission_id` support. After a standalone `navigate_to_page` moves to a different mission page, do not continue flow edits in the same turn; mission create/clone navigation may continue only through the returned `mission_id`.
- **Navigation handoff behavior:** when mission navigation lands on an existing mission page, the HTTP controllers must switch the active operation to that mission's owning operation before mission lookup and scoped follow-up endpoints run. Do not assume the previous session operation already matches the mission selected by `navigate_to_page` or a pasted mission URL.
- **Patch validation warnings:** `apply_flow_patch` responses must include `FlowValidator` warnings even when the flow is otherwise valid, and the mission designer agent should treat unconnected mutually exclusive ports (`false`, `no_match`, `done`, `error`, unused switch cases) as blocking when the workflow is supposed to continue to an intended downstream node or `output`. Validation should also surface invalid edge source handles and downstream nodes whose incoming wiring is effectively disconnected by those invalid handles.

## Authentication Architecture

- **Local:** `has_secure_password`, `PasswordComplexityValidator` (upper, lower, digit, special, 8+ chars), `session[:user_id]` storage. `PasswordResetsController` (2-hour token), `PasswordChangesController`.
- **OAuth (Keycloak, Google):** OmniAuth + `omniauth-keycloak` / `omniauth-google-oauth2`, DB-driven config via `Connectors::Authentication`. OAuth users have no password. First-time external sign-in and email-based account linking must happen only through the tenant-scoped login page; the generic `/login` page may offer external providers for already-linked accounts but must never create or link users without tenant context.
- **Roles:** `system_admin` can manage tenants globally, `admin` manages the current tenant, and `user` is end-user scoped to one tenant. Users always belong to exactly one tenant.
- **Default:** `admin@localhost` / `Changeme123!` seeds a system-admin user (override via `ADMIN_EMAIL` / `ADMIN_PASSWORD`).
- **Session bootstrap:** local login and OAuth both set `session[:user_id]` and the tenant's default `session[:current_operation_id]`.
- **Rules:** Public hosted onboarding lives at `/try-in-cloud` and creates a new tenant admin locally or through Google. Password change UI only for local users. Forgot password only for local active users. Tenant-local admins and users should use their tenant-specific `/tenants/:tenant_id/login` URL for first-time external sign-in and account linking instead of any tenant-switching workflow. The shared `/login` page remains login-only for local credentials or already-linked external accounts.

## Commands

| Command | Purpose |
|---------|---------|
| `bin/dev` | Start dev server |
| `bundle exec rspec` | Run tests |
| `bundle exec rake` | All linters, then specs (default) |
| `bundle exec rake lint` | RuboCop + haml-lint + Brakeman + bundler-audit + importmap |
| `bin/ci` | Full CI pipeline |
| `bundle exec annotaterb models` | Annotate models |

## Infrastructure

- PostgreSQL: development defaults to `undercover_agents_development_demo` plus `undercover_agents_development_queue_demo`. Test DB names are worktree-scoped from the current git worktree directory, for example `undercover_agents_test_app` and `undercover_agents_test_queue_app`, while CI keeps the fixed `undercover_agents_test_ci` and `undercover_agents_test_queue_ci` names. Solid Queue uses a separate `queue` DB. Local setup and GitHub Actions test databases must provide the pgvector `vector` extension; the Actions spec job uses the `pgvector/pgvector:pg16` service image so `db:prepare` can enable it.
- Env vars via `.env.development` / `.env.test` (dotenv-rails). Never commit secrets.
- GlitchTip/Sentry uses `SENTRY_DSN` and should initialize only in production, only when the env var is present, and never during rake tasks so deploy, db, and maintenance tasks do not report exceptions as app runtime failures.
- RubyLLM request debugging is wired once through `lib/undercover_agents/ruby_llm_debug_logging.rb` plus `config/initializers/ruby_llm_debug_logging.rb`. Keep the hardcoded `ENABLED = false` default, toggle it locally only when needed, and let that provider-level hook write human-readable payload dumps to `log/llm_api_debug_chat_<chat_id>.log` for chat-backed calls, with `log/llm_api_debug.log` as the fallback for non-chat calls, instead of adding ad hoc logging around individual `chat.ask` call sites.
- Production host defaults to `https://undercoveragents.ai`; keep `APP_HOST` overrides explicit for non-production or alternate deployment targets instead of reintroducing placeholder hosts into production config.
- Email delivery: production uses Resend SMTP with `RESEND_API_KEY` and `MAILER_FROM_EMAIL`; sender addresses must belong to a verified Resend domain or subdomain. `RESEND_SMTP_DOMAIN` is optional when the SMTP HELO domain must differ from the sender domain.
- PostgreSQL GSS mode: `PG_GSSENCMODE` (default `disable` via `config/database.yml`) to avoid `pg_GSS_have_cred_cache` segfaults on some macOS/libpq setups. Override only when your DB requires GSS encryption.
- Railway deployment uses the shared root Dockerfile for both web and worker services, keeps `railway.json` free of service-specific start or healthcheck settings, defaults `QUEUE_DATABASE_URL` / `CACHE_DATABASE_URL` to `DATABASE_URL` when dedicated URLs are absent, and should use S3-compatible Active Storage (`ACTIVE_STORAGE_SERVICE=s3`) instead of local disk when a separate worker is running. Prefer startup-time `db:prepare` in the container entrypoint over Railway pre-deploy hooks so failures surface in normal service logs; the running app must still receive either `RAILS_MASTER_KEY` with a production `secret_key_base` in credentials or an explicit `SECRET_KEY_BASE`. The Docker image excludes `config/master.key`, so Railway must provide that secret source at runtime. `DATABASE_URL` must also be provided explicitly on the app services or Rails falls back to a nonexistent local PostgreSQL socket. Railway web services must run Falcon via `bundle exec falcon host falcon.rb` or the default Docker CMD, not `falcon serve`, because `serve` uses the local HTTPS localhost defaults instead of the repo's host config. Docker asset precompile runs without Postgres, so DB-backed startup syncs must skip `assets:*` tasks, and startup metadata syncs should skip `db:*` tasks for the same reason. After `db:prepare`, production startup must also ensure the Solid Queue schema is loaded for the `queue` connection when `solid_queue_jobs` is missing, because a shared `QUEUE_DATABASE_URL` fallback to `DATABASE_URL` can leave the primary schema prepared without any queue tables. Treat worker start commands `bin/jobs`, `/rails/bin/jobs`, `bundle exec bin/jobs`, and `bundle exec rails solid_queue:start` as equivalent bootstrap paths in the entrypoint so Railway command-style differences do not skip DB preparation or queue schema loading.
- Railway deployment uses the shared root Dockerfile for both web and worker services, keeps `railway.json` free of service-specific start or healthcheck settings, defaults `QUEUE_DATABASE_URL` / `CACHE_DATABASE_URL` to `DATABASE_URL` when dedicated URLs are absent, and should use S3-compatible Active Storage (`ACTIVE_STORAGE_SERVICE=s3`) instead of local disk when a separate worker is running. Prefer startup-time `db:prepare` in the container entrypoint over Railway pre-deploy hooks so failures surface in normal service logs; the running app must still receive either `RAILS_MASTER_KEY` with a production `secret_key_base` in credentials or an explicit `SECRET_KEY_BASE`. The Docker image excludes `config/master.key`, so Railway must provide that secret source at runtime. `DATABASE_URL` must also be provided explicitly on the app services or Rails falls back to a nonexistent local PostgreSQL socket. Railway web services must run Falcon via `bundle exec falcon host falcon.rb` or the default Docker CMD, not `falcon serve`, because `serve` uses the local HTTPS localhost defaults instead of the repo's host config. Keep Falcon host preloading disabled for this app: preloading `config/environment.rb` currently collides with Rails 8.1 plus the plugin path loader and can raise `FrozenError` during worker boot. Falcon boot on Rails 8.1 also needs the app-local compatibility shim in `lib/undercover_agents/console_adapter_rails_compat.rb` so `console-adapter-rails` can remove `Rails::Rack::Logger` without crashing on a frozen middleware array. Docker asset precompile runs without Postgres, so DB-backed startup syncs must skip `assets:*` tasks, and startup metadata syncs should skip `db:*` tasks for the same reason. After `db:prepare`, production startup must also ensure the Solid Queue schema is loaded for the `queue` connection when `solid_queue_jobs` is missing, because a shared `QUEUE_DATABASE_URL` fallback to `DATABASE_URL` can leave the primary schema prepared without any queue tables. Treat worker start commands `bin/jobs`, `/rails/bin/jobs`, `bundle exec bin/jobs`, and `bundle exec rails solid_queue:start` as equivalent bootstrap paths in the entrypoint so Railway command-style differences do not skip DB preparation or queue schema loading.
- Falcon plus `actioncable-next` also needs the app-local compatibility shim in `lib/undercover_agents/action_cable_threaded_executor_compat.rb`; the gem's default pubsub executor uses `max_queue: 0` with abort-on-reject behavior, which can raise `Concurrent::RejectedExecutionError` during bursty Agent Alpha streaming or websocket teardown. Keep the bounded-queue + `:caller_runs` override in place unless upstream changes that default.
- Keycloak: `KEYCLOAK_CA_FILE`, `KEYCLOAK_SSL_VERIFY` (default `true`), `KEYCLOAK_BASE_URL` (default `/auth`).
- Telegram env vars (`TELEGRAM_WEBHOOK_BASE_URL`) are plugin-owned — see `plugins/telegram/` docs.
- Development file reload watches `plugins/**` through `config.watchable_dirs` in `config/environments/development.rb` (extensions: `rb`, `haml`, `css`, `js`, `yml`, `yaml`) so plugin edits reload without restarting `bin/dev`.
- Development also hot-reloads plugin manifests (`plugins/**/plugin.rb`) through `ActiveSupport::FileUpdateChecker` in `config/initializers/plugins.rb`, which refreshes plugin registry metadata and DSL entry-point `RagStepPlugin` registrations without restarting `bin/dev`.
- Plugin registry database sync must remain concurrency-safe for `bin/dev` and fresh-database boots: insert discovered plugin rows through the unique index, preserve existing `enabled` flags, and keep metadata refreshes idempotent.
- Development reload cycles re-register `RagStepPlugin` entries from plugin definitions in `Rails.application.reloader.to_prepare`, so module keys remain available after normal code/view reloads.
