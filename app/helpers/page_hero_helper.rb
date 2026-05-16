# frozen_string_literal: true

module PageHeroHelper
  PageHeroBackLink = PageHeroTypes::BackLink
  PageHeroEyebrow = PageHeroTypes::Eyebrow
  PageHeroAction = PageHeroTypes::Action
  PageHeroComponent = PageHeroTypes::Component

  def build_page_hero(title:, **options)
    variant = (options[:variant] || :balanced).to_sym
    PageHeroComponent.new(**page_hero_attributes(title:, options:, variant:))
  end

  def page_hero_form_action(label:, form_id:, **options)
    {
      label:,
      url: nil,
      icon: options[:icon],
      style: options.fetch(:style, :primary),
      form_id:,
      data: options.fetch(:data, {}),
      title: options[:title],
      disabled: options.fetch(:disabled, false),
    }
  end

  private

  def page_hero_attributes(title:, options:, variant:)
    page_hero_identity_attributes(title:, options:, variant:).merge(page_hero_panel_attributes(options:))
  end

  def page_hero_identity_attributes(title:, options:, variant:)
    {
      variant:,
      theme: options[:theme].to_s.presence,
      eyebrow: build_page_hero_eyebrow(options[:eyebrow]),
      back_link: build_page_hero_back_link(options[:back_link]),
      title_icon: options[:title_icon].to_s.presence,
      title_lines: normalize_page_hero_title_lines(title),
      record_title: options[:record_title].to_s.strip.presence,
      description: options[:description].to_s.presence,
    }
  end

  def page_hero_panel_attributes(options:)
    {
      meta: Array(options[:meta]).compact,
      actions: build_page_hero_actions(options[:actions]),
      sticky: options.fetch(:sticky, true),
    }
  end

  def build_page_hero_eyebrow(eyebrow)
    return if eyebrow.blank?

    attributes = eyebrow.is_a?(Hash) ? eyebrow.symbolize_keys : { label: eyebrow }
    PageHeroEyebrow.new(
      label: attributes.fetch(:label).to_s,
      icon: attributes[:icon].to_s.presence,
    )
  end

  def build_page_hero_back_link(back_link)
    return if back_link.blank?

    attributes = back_link.symbolize_keys
    PageHeroBackLink.new(
      label: attributes.fetch(:label),
      url: attributes.fetch(:url),
    )
  end

  def build_page_hero_actions(actions)
    normalized_actions = Array(actions).map do |action|
      attributes = action.symbolize_keys

      PageHeroAction.new(
        label: attributes.fetch(:label).to_s,
        url: attributes[:url],
        icon: attributes[:icon].to_s.presence,
        style: (attributes[:style] || :secondary).to_sym,
        http_method: attributes[:method],
        params: attributes[:params] || {},
        data: attributes[:data] || {},
        title: attributes[:title],
        disabled: attributes[:disabled] || false,
        form_id: attributes[:form_id].to_s.presence,
      )
    end

    normalize_page_hero_actions(normalized_actions)
  end

  def normalize_page_hero_actions(actions)
    delete_actions, remaining_actions = actions.partition(&:delete_action?)
    delete_actions + promote_page_hero_primary_action(remaining_actions)
  end

  def promote_page_hero_primary_action(actions)
    return actions if actions.empty?

    primary_index = page_hero_primary_action_index(actions)
    return actions if primary_index.nil?

    normalized_actions = actions.map.with_index do |action, index|
      normalize_page_hero_action(action, index:, primary_index:)
    end

    primary_action = normalized_actions.find(&:primary_action?)
    normalized_actions.reject(&:primary_action?) + [primary_action]
  end

  def page_hero_primary_action_index(actions)
    actions.index(&:primary_action?) || actions.rindex(&:promotable_primary?)
  end

  def normalize_page_hero_action(action, index:, primary_index:)
    return action unless action.promotable_primary? || action.primary_action?
    return action.with(style: :primary) if index == primary_index
    return action.with(style: :secondary) if action.primary_action?

    action
  end

  def normalize_page_hero_title_lines(title)
    combined_title = Array(title).filter_map do |line|
      value = line.to_s.strip
      value.presence
    end.join(" ")

    combined_title.present? ? [combined_title] : []
  end
end
