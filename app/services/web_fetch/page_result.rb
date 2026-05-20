# frozen_string_literal: true

module WebFetch
  RelatedLink = Data.define(:text, :url)
  PageResult = Data.define(:url, :title, :description, :snippets, :links, :content_type, :truncated)
end
