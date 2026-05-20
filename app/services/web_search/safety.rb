# frozen_string_literal: true

require "ipaddr"
require "resolv"
require "uri"

module WebSearch
  class Safety
    class Error < StandardError; end

    ALLOWED_SCHEMES = ["http", "https"].freeze
    BLOCKED_HOSTS = ["localhost", "localhost.localdomain"].freeze
    BLOCKED_IPV4_RANGES = [
      "0.0.0.0/8",
      "10.0.0.0/8",
      "100.64.0.0/10",
      "127.0.0.0/8",
      "169.254.0.0/16",
      "172.16.0.0/12",
      "192.0.0.0/24",
      "192.0.2.0/24",
      "192.168.0.0/16",
      "198.18.0.0/15",
      "198.51.100.0/24",
      "203.0.113.0/24",
      "224.0.0.0/4",
      "240.0.0.0/4",
      "255.255.255.255/32",
    ].map { |range| IPAddr.new(range) }.freeze
    BLOCKED_IPV6_RANGES = [
      "::/128",
      "::1/128",
      "64:ff9b:1::/48",
      "100::/64",
      "2001:db8::/32",
      "fc00::/7",
      "fe80::/10",
      "ff00::/8",
    ].map { |range| IPAddr.new(range) }.freeze

    def self.validate_public_url!(url, resolver: Resolv)
      new(url, resolver:).validate!
    end

    def initialize(url, resolver: Resolv)
      @url = url.to_s.strip
      @resolver = resolver
    end

    def validate!
      raise Error, "URL is required." if @url.blank?

      uri = URI.parse(@url)
      raise Error, "Only http and https URLs are allowed." unless ALLOWED_SCHEMES.include?(uri.scheme)
      raise Error, "URLs with embedded credentials are not allowed." if uri.userinfo.present?

      validate_host!(uri.host.to_s.downcase)

      uri
    rescue URI::InvalidURIError
      raise Error, "The URL is not valid."
    end

    private

    def validate_host!(host)
      raise Error, "A public host name is required." if host.blank?
      raise Error, "Local or private hosts are not allowed." if blocked_host?(host)

      return validate_public_ip!(host) if ip_literal?(host)

      raise Error, "A public host name is required." unless host.include?(".")

      addresses = Array(@resolver.getaddresses(host)).compact_blank
      raise Error, "Unable to resolve the requested host." if addresses.empty?

      addresses.each { |address| validate_public_ip!(address) }
    end

    def blocked_host?(host)
      return true if BLOCKED_HOSTS.include?(host)

      host.end_with?(".local", ".internal")
    end

    def ip_literal?(host)
      IPAddr.new(host)
      true
    rescue IPAddr::InvalidAddressError
      false
    end

    def validate_public_ip!(address)
      ip = IPAddr.new(address)
      blocked_ranges = ip.ipv4? ? BLOCKED_IPV4_RANGES : BLOCKED_IPV6_RANGES
      return unless blocked_ranges.any? { |range| range.include?(ip) }

      raise Error, "Local or private network targets are not allowed."
    end
  end
end
