# frozen_string_literal: true

class SafeWebSearchTool < RubyLLM::Tool
  ACTIONS = ["search", "read"].freeze

  description(
    "Safely search the public web and read a very small number of public pages. " \
    "Search first, then read only the most relevant URLs. " \
    "The tool blocks local/private hosts, follows only a few safe redirects, " \
    "downloads only a capped amount of text, and returns focused snippets instead of whole pages.",
  )

  param :action,
        desc: "Required. One of: search, read.",
        type: :string,
        required: true

  param :query,
        desc: "Search query for action=search.",
        type: :string,
        required: false

  param :page,
        desc: "Optional search page number for action=search. Defaults to 1.",
        required: false

  param :max_results,
        desc: "Optional search result limit for action=search. Defaults to 5 and is capped for safety.",
        required: false

  param :url,
        desc: "Single URL to read for action=read.",
        type: :string,
        required: false

  param :urls,
        desc: "Optional array of URLs to read for action=read. Use at most a few highly relevant pages.",
        type: :array,
        required: false

  param :focus,
        desc: "Optional topic or question used to rank the most relevant snippets and same-site links.",
        type: :string,
        required: false

  def initialize(client: WebSearch::Client.new)
    super()
    @client = client
  end

  def name
    "safe_web_search"
  end

  def execute(**arguments)
    action = arguments[:action].to_s

    case action
    when "search"
      search_response(arguments)
    when "read"
      read_response(arguments)
    else
      "Unknown action #{action.inspect}. Use one of: #{ACTIONS.join(", ")}."
    end
  rescue WebSearch::Safety::Error, WebSearch::Client::Error => e
    "Web search failed: #{e.message}"
  end

  private

  def search_response(arguments)
    format_search(
      query: arguments[:query],
      page: arguments[:page],
      results: @client.search(
        query: arguments[:query],
        page: arguments[:page],
        max_results: arguments[:max_results],
      ),
    )
  end

  def read_response(arguments)
    format_read(
      focus: arguments[:focus],
      pages: @client.read(
        urls: [arguments[:url], arguments[:urls]].flatten,
        focus: arguments[:focus],
      ),
    )
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
      lines << 'Next step: call safe_web_search with action="read" for only the most relevant URL or small URL set.'
    end

    lines.join("\n")
  end

  def format_read(focus:, pages:)
    lines = []
    lines << "Focus: #{focus}" if focus.present?
    lines << "Pages read: #{pages.size}"

    pages.each_with_index do |page, index|
      append_page(lines, page, index:)
    end

    lines.join("\n")
  end

  def append_page(lines, page, index:)
    lines << ""
    lines << "## Page #{index + 1}"
    lines << "URL: #{page.url}"
    lines << "Title: #{page.title}" if page.title.present?
    lines << "Description: #{page.description}" if page.description.present?
    lines << "Content type: #{page.content_type}"
    lines << "Fetched only the initial capped page content." if page.truncated
    append_snippets(lines, page)
    append_links(lines, page)
  end

  def append_snippets(lines, page)
    if page.snippets.any?
      lines << "Relevant snippets:"
      page.snippets.each_with_index do |snippet, snippet_index|
        lines << "#{snippet_index + 1}. #{snippet}"
      end
    else
      lines << "Relevant snippets: none extracted."
    end
  end

  def append_links(lines, page)
    return unless page.links.any?

    lines << "Related same-site links:"
    page.links.each { |link| lines << "- #{link.text}: #{link.url}" }
  end
end
