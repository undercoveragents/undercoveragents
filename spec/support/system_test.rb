# frozen_string_literal: true

require "rackup"
require "async/http/protocol/http1"
require "falcon/server"
require "io/endpoint/host_endpoint"
require "kernel/sync"
require "protocol/rack/adapter"

Capybara.register_server :falcon do |app, port, host|
  rack_app = Protocol::Rack::Adapter.new(app)

  Sync do
    endpoint = IO::Endpoint.tcp(host, port)
    server = Falcon::Server.new(rack_app, endpoint, protocol: Async::HTTP::Protocol::HTTP1, scheme: "http")
    server_task = server.run
    server_task.wait
  ensure
    server_task&.stop
  end
end

Capybara.server = :falcon
Capybara.default_max_wait_time = 5

RSpec.configure do |config|
  config.before(:each, :js) do
    driven_by :selenium, using: :headless_chrome, screen_size: [1440, 1200]
  end
end
