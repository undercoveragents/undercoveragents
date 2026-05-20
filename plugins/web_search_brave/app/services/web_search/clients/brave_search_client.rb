# frozen_string_literal: true

require "json"
require "uri"

module WebSearch
  module Clients
    class BraveSearchClient
      SEARCH_HOST = "api.search.brave.com"
      SEARCH_PATH = "/res/v1/web/search"
      MAX_SEARCH_BYTES = 180_000
      ALLOWED_CONTENT_TYPES = ["application/json"].freeze

      def initialize(http_client: WebSearch::HttpClient.new, connector: nil, connector_class: Connectors::BraveSearch)
        @http_client = http_client
        @connector = connector
        @connector_class = connector_class
      end

      def search(query:, page:, max_results:)
        raise Error, "A search query is required." if query.blank?

        response = @http_client.fetch_text(
          search_uri(query:, page:, max_results:),
          max_bytes: MAX_SEARCH_BYTES,
          allowed_content_types: ALLOWED_CONTENT_TYPES,
          headers: { "X-Subscription-Token" => connector.api_key },
          range_request: false,
        )
        parse_search_results(response.body, max_results:)
      rescue ActiveRecord::Encryption::Errors::Decryption
        raise Error,
              "Cannot decrypt Brave Search credentials. Re-enter the API key in the Brave Search connector settings."
      rescue JSON::ParserError
        raise Error, "Brave Search returned an invalid JSON response."
      end

      private

      def connector
        current_connector = @connector || @connector_class.current_connector
        if current_connector.blank?
          raise Error, "Brave Search requires an enabled Brave Search connector for the current tenant."
        end

        current_connector
      end

      def search_uri(query:, page:, max_results:)
        URI::HTTPS.build(
          host: SEARCH_HOST,
          path: SEARCH_PATH,
          query: URI.encode_www_form(q: query, offset: (page - 1) * max_results, count: max_results),
        )
      end

      def parse_search_results(body, max_results:)
        Array(JSON.parse(body).dig("web", "results")).filter_map do |entry|
          url = entry["url"].to_s
          next if url.blank?
          next unless public_result_url?(url)

          SearchResult.new(
            title: normalize_text(entry["title"]).presence || url,
            url:,
            display_url: display_url_for(entry, url),
            snippet: normalize_text(entry["description"]),
          )
        end.first(max_results)
      end

      def display_url_for(entry, url)
        normalize_text(entry.dig("meta_url", "hostname")).presence || URI.parse(url).host
      rescue URI::InvalidURIError
        nil
      end

      def public_result_url?(url)
        WebSearch::Safety.validate_public_url!(url)
        true
      rescue WebSearch::Safety::Error
        false
      end

      def normalize_text(text)
        text.to_s.gsub(/\s+/, " ").strip
      end
    end
  end
end
