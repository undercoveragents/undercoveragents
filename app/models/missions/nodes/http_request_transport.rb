# frozen_string_literal: true

module Missions
  module Nodes
    module HttpRequestTransport
      private

      def perform_request(method, uri, headers, payload, node_data)
        http = build_http_client(uri, node_data)
        request = build_net_http_request(method, uri, headers)
        apply_payload!(request, payload)
        execute_request_with_retries(http, request, payload, node_data)
      ensure
        cleanup_tempfiles(payload.tempfiles)
      end

      def build_http_client(uri, node_data)
        Net::HTTP.new(uri.host, uri.port).tap do |http|
          use_ssl = uri.scheme == "https"
          http.use_ssl = use_ssl
          apply_ssl_verify_mode!(http, node_data) if use_ssl
          http.open_timeout = timeout_value(node_data["connect_timeout"])
          http.read_timeout = timeout_value(node_data["read_timeout"])
          http.write_timeout = timeout_value(node_data["write_timeout"]) if http.respond_to?(:write_timeout=)
        end
      end

      def apply_ssl_verify_mode!(http, node_data)
        return if verify_ssl?(node_data)

        http.verify_mode = OpenSSL::SSL.const_get(:VERIFY_NONE)
      end

      def execute_request_with_retries(http, request, payload, node_data)
        retry_options = request_retry_options(node_data)
        attempts = 0

        loop do
          attempts += 1
          response = request_once(http, request, payload, attempts, retry_options)
          next if response == :retry

          return response unless retryable_response?(response) && attempts <= retry_options[:max_retries]

          sleep_before_retry(retry_options[:interval])
        end
      end

      def request_once(http, request, payload, attempts, retry_options)
        rewind_payload!(payload)
        http.request(request)
      rescue *self.class::RETRYABLE_ERRORS
        raise if attempts > retry_options[:max_retries]

        sleep_before_retry(retry_options[:interval])
        :retry
      end

      def request_retry_options(node_data)
        {
          max_retries: retry_enabled?(node_data) ? retry_count(node_data["max_retries"]) : 0,
          interval: retry_interval_seconds(node_data["retry_interval_ms"]),
        }
      end

      def sleep_before_retry(interval)
        Kernel.sleep(interval) if interval.positive?
      end

      def build_net_http_request(method, uri, headers)
        request = net_http_request_class(method).new(uri.request_uri)
        headers.each { |key, value| request[key] = value }
        request
      end

      def net_http_request_class(method)
        {
          "GET" => Net::HTTP::Get,
          "POST" => Net::HTTP::Post,
          "PUT" => Net::HTTP::Put,
          "PATCH" => Net::HTTP::Patch,
          "DELETE" => Net::HTTP::Delete,
          "HEAD" => Net::HTTP::Head,
          "OPTIONS" => Net::HTTP::Options,
        }[method]
      end

      def apply_payload!(request, payload)
        return if payload.nil?

        if payload.body_stream
          request.body_stream = payload.body_stream
          request.content_length = payload.content_length
        elsif payload.body.present?
          request.body = payload.body
        end
      end

      def rewind_payload!(payload)
        return unless payload&.body_stream.respond_to?(:rewind)

        payload.body_stream.rewind
      end

      def cleanup_tempfiles(tempfiles)
        Array(tempfiles).each do |tempfile|
          tempfile.close unless tempfile.closed?
          tempfile.unlink if tempfile.respond_to?(:unlink)
        rescue IOError
          nil
        end
      end

      def timeout_value(value)
        numeric = Float(value, exception: false)
        numeric&.positive? ? numeric : self.class::REQUEST_TIMEOUT
      end

      def retry_count(value)
        numeric = Integer(value, exception: false)
        numeric&.positive? ? numeric : self.class::DEFAULT_MAX_RETRIES
      end

      def retry_interval_seconds(value)
        numeric = Integer(value, exception: false)
        (numeric || self.class::DEFAULT_RETRY_INTERVAL_MS).clamp(0, 60_000) / 1000.0
      end

      def retry_enabled?(node_data)
        normalize_boolean(node_data["retry_enabled"], false)
      end

      def verify_ssl?(node_data)
        normalize_boolean(node_data["verify_ssl"], self.class::DEFAULT_VERIFY_SSL)
      end

      def retryable_response?(response)
        self.class::RETRYABLE_STATUS_CODES.include?(response.code.to_i)
      end
    end
  end
end
