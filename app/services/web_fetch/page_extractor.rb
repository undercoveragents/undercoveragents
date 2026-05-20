# frozen_string_literal: true

require "nokogiri"
require "public_suffix"
require "uri"

module WebFetch
  class PageExtractor
    LINK_LIMIT = 6
    SNIPPET_LIMIT = 6
    BLOCK_LIMIT = 450
    TEXT_MIN_LENGTH = 35
    REMOVED_HTML_SELECTORS = "script,style,noscript,iframe,svg,canvas,form,button,input,nav,footer,aside"

    def self.call(response, focus: nil)
      new(response, focus:).call
    end

    def initialize(response, focus: nil)
      @response = response
      @focus_tokens = tokenize(focus)
    end

    def call
      return extract_plain_text_page if @response.content_type == "text/plain"

      extract_html_page
    end

    private

    def extract_html_page
      document = Nokogiri::HTML5(@response.body)
      document.css(REMOVED_HTML_SELECTORS).remove
      root = document_root(document)

      PageResult.new(
        url: @response.uri,
        title: normalize_text(document.at_css("title")&.text),
        description: normalize_text(document.at_css("meta[name='description']")&.[]("content")),
        snippets: select_snippets(text_blocks_from(root), fallback_text: normalize_text(root.text)),
        links: extract_related_links(root, base_url: @response.uri),
        content_type: @response.content_type.presence || "text/html",
        truncated: @response.truncated,
      )
    end

    def document_root(document)
      document.at_css("main, article, [role='main']") || document.at_css("body") || document
    end

    def extract_plain_text_page
      blocks = @response.body.to_s.split(/\n{2,}/).map.with_index do |text, index|
        cleaned = normalize_text(text)
        next if cleaned.length < TEXT_MIN_LENGTH

        { text: truncate_block(cleaned), score: score_text(cleaned, index:, heading: index.zero?) }
      end.compact

      PageResult.new(
        url: @response.uri,
        title: "",
        description: "",
        snippets: select_snippets(blocks, fallback_text: @response.body.to_s),
        links: [],
        content_type: "text/plain",
        truncated: @response.truncated,
      )
    end

    def text_blocks_from(root)
      seen = {}

      root.css("h1, h2, h3, p, li, blockquote, pre, code").map.with_index do |node, index|
        text = normalize_text(node.text)
        next if text.length < TEXT_MIN_LENGTH || seen[text]

        seen[text] = true
        { text: truncate_block(text), score: score_text(text, index:, heading: node.name.start_with?("h")) }
      end.compact
    end

    def select_snippets(blocks, fallback_text:)
      chosen = blocks.sort_by { |block| [-block[:score], block[:text].length] }.pluck(:text).first(SNIPPET_LIMIT)
      return chosen if chosen.any?

      fallback = normalize_text(fallback_text)
      fallback.present? ? [truncate_block(fallback)] : []
    end

    def score_text(text, index:, heading:)
      score = [20 - index, 1].max
      score += 15 if heading

      downcased = text.downcase
      @focus_tokens.each do |token|
        score += downcased.scan(/\b#{Regexp.escape(token)}\b/).size * 10
      end

      score + [text.length / 120, 6].min
    end

    def extract_related_links(root, base_url:)
      base_uri = URI.parse(base_url)
      seen = {}

      ranked_links = root.css("a[href]").filter_map do |node|
        text = normalize_text(node.text)
        next if text.length < 3

        absolute_url = same_site_link(base_uri, node["href"])
        next if absolute_url.blank? || seen[absolute_url]

        seen[absolute_url] = true
        { link: RelatedLink.new(text:, url: absolute_url), score: score_text(text, index: 0, heading: false) }
      end

      ranked_links.sort_by { |entry| -entry[:score] }.pluck(:link).first(LINK_LIMIT)
    end

    def same_site_link(base_uri, raw_href)
      href = raw_href.to_s.strip
      return if href.blank? || href.start_with?("#", "javascript:", "mailto:", "tel:")

      uri = URI.parse(href)
      candidate = uri.host.present? ? uri : base_uri.merge(uri)
      return unless same_registrable_domain?(base_uri.host, candidate.host)

      candidate.fragment = nil
      candidate.to_s
    rescue URI::InvalidURIError
      nil
    end

    def same_registrable_domain?(left_host, right_host)
      left = registrable_domain(left_host)
      right = registrable_domain(right_host)
      left.present? && left == right
    end

    def registrable_domain(host)
      PublicSuffix.domain(host.to_s)
    rescue PublicSuffix::Error
      host.to_s.downcase.presence
    end

    def tokenize(text)
      text.to_s.downcase.scan(/[a-z0-9]{3,}/).uniq.first(8)
    end

    def normalize_text(text)
      text.to_s.gsub(/\s+/, " ").strip
    end

    def truncate_block(text)
      return text if text.length <= BLOCK_LIMIT

      "#{text[0, BLOCK_LIMIT - 15]}... (truncated)"
    end
  end
end
