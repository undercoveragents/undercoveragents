# frozen_string_literal: true

module Missions
  module Nodes
    module HttpRequestInstructions
      TEMPLATE = <<~INSTRUCTIONS.strip.freeze
        ## HTTP Request (type: "http_request")
        Makes an external HTTP API call. %<timeout>s timeout, %<max_body_mb>sMB max response.

        ### Configuration
        ```json
        {
          "url": "https://api.example.com/search",
          "method": "POST",
          "params": {"q": "{{query}}"},
          "auth_type": "bearer",
          "auth_bearer_token": "{{api_token}}",
          "headers": {"X-Trace": "{{trace_id}}"},
          "body_mode": "json",
          "body": "{\\u0022query\\u0022: \\u0022{{user_input}}\\u0022}",
          "verify_ssl": true,
          "connect_timeout": 10,
          "read_timeout": 30,
          "retry_enabled": true,
          "max_retries": 3,
          "retry_interval_ms": 250
        }
        ```
        - `url` (required): Request URL. Supports {{variable}} interpolation.
        - `method` (required): %<methods>s
        - `params`: Query params hash. Values support interpolation.
        - `auth_type`: `none`, `bearer`, `basic`, or `api_key`.
        - `headers`: Header hash. Values support interpolation.
        - `body_mode`: `none`, `json`, `raw`, `form_urlencoded`, `multipart`, or `binary`.
        - `body`: Raw or JSON body text.
        - `form_urlencoded_body`: Hash encoded as `application/x-www-form-urlencoded`.
        - `multipart_form_data`: Hash encoded as `multipart/form-data`. Any value that resolves to a file metadata hash uploads that file.
        - `binary_source`: Template reference such as `{{write_file_1.file}}` for binary uploads.
        - `verify_ssl`, `connect_timeout`, `read_timeout`, `write_timeout`: Transport controls.
        - `retry_enabled`, `max_retries`, `retry_interval_ms`: Retry transport failures and retryable 4xx/5xx responses.

        ### Output Ports
        - `success`: HTTP 2xx responses
        - `error`: Non-2xx responses

        ### Runtime Branch Pruning
        - When the request completes, only one of `success` or `error` stays enabled.
        - The non-selected port is disabled at runtime.
        - Downstream joins wait only on predecessors that still have enabled paths into the join.

        ### Output Variables
        - `status` (number): HTTP status code
        - `body` (string): Response body
        - `headers` (hash): Response headers

        ### Tips
        - Use JSON Extract node after HTTP Request to parse JSON responses instead of Code unless custom Ruby logic is genuinely required.
        - Use full-template file references like `{{generate_image_1.image}}` in multipart or binary modes.
        - Connect both `success` and `error` ports for robust error handling.
      INSTRUCTIONS

      def designer_instructions
        format(
          TEMPLATE,
          timeout: "#{self::REQUEST_TIMEOUT}s",
          max_body_mb: self::MAX_BODY_SIZE / 1_048_576,
          methods: self::ALLOWED_METHODS.join(", "),
        )
      end
    end
  end
end
