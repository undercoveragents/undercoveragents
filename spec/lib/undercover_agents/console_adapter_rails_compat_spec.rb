# frozen_string_literal: true

require "rails_helper"

RSpec.describe "UndercoverAgents::ConsoleAdapterRailsCompat::MiddlewareStackDeletePatch" do
  describe ".apply!" do
    it "does not prepend the patch twice" do
      patch_count = lambda {
        ActionDispatch::MiddlewareStack.ancestors.count do |ancestor|
          ancestor == UndercoverAgents::ConsoleAdapterRailsCompat::MiddlewareStackDeletePatch
        end
      }

      expect do
        UndercoverAgents::ConsoleAdapterRailsCompat.apply!
      end.not_to change(&patch_count)
    end
  end

  describe "ActionDispatch::MiddlewareStack#delete" do
    it "retries the rescued deletion path for Rails::Rack::Logger" do
      stack = ActionDispatch::MiddlewareStack.new
      stack.use(Rails::Rack::Logger)
      stack.use(Rack::Head)

      original_middlewares = stack.middlewares
      original_middlewares.define_singleton_method(:reject!) do |*_args, &_block|
        raise FrozenError, "frozen"
      end

      expect { stack.delete(Rails::Rack::Logger) }.not_to raise_error
      expect(stack.middlewares).not_to equal(original_middlewares)
      expect(stack.map(&:klass)).to eq([Rack::Head])
    end

    it "re-raises the rescued deletion path for unrelated targets" do
      stack = ActionDispatch::MiddlewareStack.new
      stack.use(Rack::Head)
      stack.middlewares.define_singleton_method(:reject!) do |*_args, &_block|
        raise FrozenError, "frozen"
      end

      expect { stack.delete(Rack::Head) }.to raise_error(FrozenError)
    end

    it "duplicates a frozen stack when console-adapter-rails removes Rails::Rack::Logger" do
      stack = ActionDispatch::MiddlewareStack.new
      stack.use(Rails::Rack::Logger)
      stack.use(Rack::Head)

      original_middlewares = stack.middlewares
      original_middlewares.freeze

      expect { stack.delete(Rails::Rack::Logger) }.not_to raise_error
      expect(stack.middlewares).not_to equal(original_middlewares)
      expect(stack.map(&:klass)).to eq([Rack::Head])
    end

    it "still raises for unrelated deletions on a frozen stack" do
      stack = ActionDispatch::MiddlewareStack.new
      stack.use(Rack::Head)
      stack.middlewares.freeze

      expect { stack.delete(Rack::Head) }.to raise_error(FrozenError)
    end
  end
end
