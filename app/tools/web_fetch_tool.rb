# frozen_string_literal: true

class WebFetchTool < RubyLLM::Tool
  description(
    "Safely fetch a very small number of public web pages. " \
    "Use specific URLs, download only capped text content, and return focused snippets plus same-site links.",
  )

  param :url,
        desc: "Single URL to fetch.",
        type: :string,
        required: false

  param :urls,
        desc: "Optional array of URLs to fetch. Use at most a few highly relevant pages.",
        type: :array,
        required: false

  param :focus,
        desc: "Optional topic or question used to rank the most relevant snippets and same-site links.",
        type: :string,
        required: false

  def initialize(client: WebFetch::Client.new)
    super()
    @client = client
  end

  def name
    "web_fetch"
  end

  def execute(url: nil, urls: nil, focus: nil)
    pages = @client.read(urls: [url, urls].flatten, focus:)
    lines = []
    lines << "Focus: #{focus}" if focus.present?
    lines << "Pages read: #{pages.size}"
    append_pages(lines, pages)
    lines.join("\n")
  rescue WebSearch::Safety::Error, WebFetch::Error => e
    "Web fetch failed: #{e.message}"
  end

  private

  def append_pages(lines, pages)
    pages.each_with_index do |page, index|
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
  end

  def append_snippets(lines, page)
    if page.snippets.any?
      lines << "Relevant snippets:"
      page.snippets.each_with_index { |snippet, index| lines << "#{index + 1}. #{snippet}" }
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
