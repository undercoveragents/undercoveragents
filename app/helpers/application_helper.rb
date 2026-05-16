# frozen_string_literal: true

module ApplicationHelper
  include ClientUiHelper

  # Renders a partial from a plugin's own views directory, temporarily scoping
  # the view lookup so that the plugin's files are resolved by name alone (no
  # subdirectory or naming convention required per plugin).
  #
  # @param view_path [String, Pathname] absolute path to the plugin's views directory
  # @param partial [String] partial name (without leading underscore)
  # @param locals [Hash] locals to pass to the partial
  def render_plugin_partial(view_path:, partial:, locals: {})
    controller.prepend_view_path(view_path.to_s)
    saved_prefixes = lookup_context.prefixes
    lookup_context.prefixes = [""]
    render(partial:, locals:)
  ensure
    lookup_context.prefixes = saved_prefixes if defined?(saved_prefixes) && saved_prefixes
  end

  def render_rag_step_form(steppable, **locals)
    render_plugin_partial(view_path: steppable.form_partial_path, partial: "form", locals:)
  end

  def render_connector_form(connector, **locals)
    configurator = connector.configurator
    return unless configurator

    render_plugin_partial(view_path: configurator.form_partial_path, partial: "form", locals: locals.merge(connector:))
  end

  def render_connector_show(connector)
    configurator = connector.configurator
    return unless configurator

    render_plugin_partial(view_path: configurator.show_partial_path, partial: "show", locals: { connector: })
  end

  def render_channel_form(channel, **locals)
    configurator = channel.configurator
    return unless configurator

    render_plugin_partial(view_path: configurator.form_partial_path, partial: "form", locals: locals.merge(channel:))
  end

  def render_channel_show(channel, **locals)
    configurator = channel.configurator
    return unless configurator

    render_plugin_partial(view_path: configurator.show_partial_path, partial: "show", locals: locals.merge(channel:))
  end

  def render_connector_partial(connector, partial_name, **locals)
    configurator = connector.configurator
    return unless configurator

    render_plugin_partial(
      view_path: configurator.show_partial_path,
      partial: partial_name,
      locals: locals.merge(connector:),
    )
  end

  def render_capability_form(capability_config, capability_record:, **locals)
    return unless capability_config

    plugin_locals = capability_config.form_locals
    render_plugin_partial(
      view_path: capability_config.form_partial_path,
      partial: "form",
      locals: locals.merge(plugin_locals).merge(capability_config:, capability_record:),
    )
  end

  # Renders profile panel partials from all enabled plugins that provide one.
  # Each plugin can place a `profile/_profile_panel.html.haml` in its `app/views/`
  # directory to contribute a card to the profile page.
  def render_plugin_profile_panels(user)
    panels = []
    UndercoverAgents::PluginSystem.registry.enabled.each do |definition|
      views_dir = definition.root_path&.join("app", "views")
      next unless views_dir&.exist?
      next unless views_dir.join("profile", "_profile_panel.html.haml").exist?

      controller.prepend_view_path(views_dir.to_s)
      saved_prefixes = lookup_context.prefixes
      lookup_context.prefixes = ["profile"]
      panels << render(partial: "profile_panel", locals: { user: })
      lookup_context.prefixes = saved_prefixes
    end
    safe_join(panels)
  end

  def toast_messages
    messages = []
    messages << { type: "notice", text: notice } if notice.present?
    messages << { type: "alert", text: alert } if alert.present?
    messages
  end

  def initial_theme
    theme = cookies[:theme].to_s
    ["light", "dark"].include?(theme) ? theme : "light"
  end

  def initial_theme_root_class
    initial_theme == "dark" ? "dark" : nil
  end

  def initial_theme_root_data
    {
      theme: initial_theme,
      theme_ready: "false",
    }
  end

  def theme_root_primer_style_tag
    content_tag(:style, theme_root_primer_css, { nonce: true }, false)
  end

  def theme_bootstrap_script_tag
    content_tag(:script, theme_bootstrap_script, { nonce: true }, false)
  end

  def theme_background_color(theme)
    theme == "dark" ? "#020617" : "#f8fafc"
  end

  def theme_text_color(theme)
    theme == "dark" ? "#f1f5f9" : "#0f172a"
  end

  def theme_root_primer_css
    <<~CSS
      html { background-color: #{theme_background_color(initial_theme)}; color-scheme: #{initial_theme}; }
      body { background-color: #{theme_background_color(initial_theme)}; color: #{theme_text_color(initial_theme)}; }
      html[data-theme-ready='false'] body { visibility: hidden; }
    CSS
  end

  def theme_bootstrap_script
    <<~JS
      (() => {
        const root = document.documentElement
        const storedTheme = (() => {
          try {
            const value = localStorage.getItem("theme")
            return value === "dark" || value === "light" ? value : null
          } catch (_) {
            return null
          }
        })()
        const theme = storedTheme || (window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light")
        const backgroundColor = theme === "dark" ? "#020617" : "#f8fafc"
        const textColor = theme === "dark" ? "#f1f5f9" : "#0f172a"

        root.classList.toggle("dark", theme === "dark")
        root.dataset.theme = theme
        root.style.backgroundColor = backgroundColor
        root.style.color = textColor
        root.style.colorScheme = theme
        document.cookie = `theme=${theme}; Max-Age=31536000; Path=/; SameSite=Lax`

        const reveal = () => {
          root.dataset.themeReady = "true"
        }

        if (document.readyState === "loading") {
          document.addEventListener("DOMContentLoaded", reveal, { once: true })
        } else {
          requestAnimationFrame(reveal)
        }

        window.addEventListener("pageshow", reveal, { once: true })
        window.setTimeout(reveal, 1500)
      })()
    JS
  end

  def temperature_label(temperature)
    case temperature
    when 0.0..0.3 then "Precise"
    when 0.3..0.7 then "Balanced"
    when 0.7..1.2 then "Creative"
    else "Experimental"
    end
  end
end
