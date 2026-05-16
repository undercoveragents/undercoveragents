# frozen_string_literal: true

# Load the actioncable-next RSpec integration. This patches HaveStream to use
# `stream_names` (Rails 8 API) and patches ChannelExampleGroup.connection_class
# to fall back to the server's default connection class. The actioncable-next
# gem's own patch adds an instance method which doesn't override the class method
# defined in ChannelExampleGroup::ClassMethods, so we fix that explicitly below.
require "action_cable/next/rspec"

# Override the class method directly — the actioncable-next prepend targets
# instance methods and doesn't affect this ClassMethods class method.
if defined?(RSpec::Rails::ChannelExampleGroup)
  RSpec::Rails::ChannelExampleGroup::ClassMethods.module_eval do
    def connection_class
      (_connection_class || described_class).then do |klass|
        next klass if klass && klass <= ActionCable::Connection::Base

        # Fall back to the server-configured connection class
        connection = ActionCable.server.config.connection_class.call
        self._connection_class = connection
        connection
      end
    end
  end
end
