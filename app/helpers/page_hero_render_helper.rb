# frozen_string_literal: true

module PageHeroRenderHelper
  def render_page_hero(hero_options = nil, title: nil, **options)
    normalized_options = hero_options.respond_to?(:to_h) ? hero_options.to_h.symbolize_keys : {}
    normalized_options = normalized_options.merge(options)
    resolved_title = title || normalized_options.delete(:title)
    hero = build_page_hero(title: resolved_title, **normalized_options)

    render partial: "shared/page_hero/hero", locals: { hero: }
  end
end
