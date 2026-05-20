# frozen_string_literal: true

module WebSearch
  class SearchService
    MAX_RESULTS = 8
    MAX_PAGE = 5

    def initialize(provider: nil, client: nil)
      @provider = provider
      @client = client
    end

    def search(query:, page: 1, max_results: 5)
      search_client.search(
        query: query.to_s.strip,
        page: normalize_page(page),
        max_results: normalize_result_limit(max_results),
      )
    end

    private

    def search_client
      @search_client ||= @client || SearchClientRegistry.fetch(@provider)
    end

    def normalize_page(page)
      numeric = Integer(page, exception: false) || 1
      numeric.clamp(1, MAX_PAGE)
    end

    def normalize_result_limit(max_results)
      numeric = Integer(max_results, exception: false) || 5
      numeric.clamp(1, MAX_RESULTS)
    end
  end
end
