# frozen_string_literal: true

class SafeWebSearchTool < RubyLLM::Tool
  description(
    "Safely search the public web through a plugin-backed search client. " \
    "Use it to discover relevant public URLs, then call web_fetch for only the smallest useful set of pages.",
  )

  param :query,
        desc: "Search query.",
        type: :string,
        required: true

  param :page,
        desc: "Optional search page number. Defaults to 1.",
        required: false

  param :max_results,
        desc: "Optional search result limit. Defaults to 5 and is capped for safety.",
        required: false

  param :provider,
        desc: "Optional plugin-backed search provider. Defaults to the configured registry default.",
        type: :string,
        required: false

  def initialize(service: WebSearch::SearchService.new)
    super()
    @service = service
  end

  def name
    "safe_web_search"
  end

  def execute(query:, page: nil, max_results: nil, provider: nil)
    format_search(query:, page:, results: search_results(query:, page:, max_results:, provider:))
  rescue WebSearch::Error => e
    "Web search failed: #{e.message}"
  end

  private

  def search_results(query:, page:, max_results:, provider:)
    return @service.search(query:, page:, max_results:) if provider.blank?

    WebSearch::SearchService.new(provider:).search(query:, page:, max_results:)
  end

  def format_search(query:, page:, results:)
    current_page = Integer(page, exception: false) || 1
    lines = [
      "Search query: #{query}",
      "Page: #{current_page}",
      "Results: #{results.size}",
    ]

    if results.empty?
      lines << "No public search results were returned."
    else
      results.each_with_index do |result, index|
        lines << ""
        lines << "#{index + 1}. #{result.title}"
        lines << "   URL: #{result.url}"
        lines << "   Site: #{result.display_url}" if result.display_url.present?
        lines << "   Snippet: #{result.snippet}" if result.snippet.present?
      end
      lines << ""
      lines << "Next step: call web_fetch for only the most relevant URL or small URL set."
    end

    lines.join("\n")
  end
end
