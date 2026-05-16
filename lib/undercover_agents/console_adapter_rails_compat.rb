# frozen_string_literal: true

module UndercoverAgents
  module ConsoleAdapterRailsCompat
    module MiddlewareStackDeletePatch
      def delete(target)
        super
      rescue FrozenError => e
        raise e unless target == ::Rails::Rack::Logger

        self.middlewares = middlewares.dup
        super
      end
    end

    def self.apply!
      return if ActionDispatch::MiddlewareStack < MiddlewareStackDeletePatch

      ActionDispatch::MiddlewareStack.prepend(MiddlewareStackDeletePatch)
    end
  end
end

UndercoverAgents::ConsoleAdapterRailsCompat.apply!
