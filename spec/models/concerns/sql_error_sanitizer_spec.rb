# frozen_string_literal: true

require "rails_helper"

RSpec.describe SqlErrorSanitizer do
  let(:source_host) do
    Class.new do
      include SqlErrorSanitizer

      def call(message)
        sanitize_error(message)
      end
    end
  end

  let(:storage_host) do
    Class.new do
      include SqlErrorSanitizer

      def call(message)
        sanitize_error(message)
      end
    end
  end

  it "filters passwords, URL credentials, and secrets for source wrapper" do
    raw = "postgres://user:pass@host/db password=abc secret:token"
    result = source_host.new.call(raw)

    expect(result).to include("://[FILTERED]@")
    expect(result).to include("password=[FILTERED]")
    expect(result).to include("secret=[FILTERED]")
    expect(result).not_to include("abc")
    expect(result).not_to include("token")
  end

  it "applies the same sanitization rules for storage wrapper" do
    raw = "postgres://user:pass@host/db password=abc secret=token"
    result = storage_host.new.call(raw)

    expect(result).to include("://[FILTERED]@")
    expect(result).to include("password=[FILTERED]")
    expect(result).to include("secret=[FILTERED]")
    expect(result).not_to include("abc")
    expect(result).not_to include("token")
  end

  it "truncates long error messages" do
    long_message = "a" * 700
    result = source_host.new.call(long_message)

    expect(result.length).to eq(500)
  end

  it "handles nil messages safely" do
    expect(source_host.new.call(nil)).to eq("")
  end
end
