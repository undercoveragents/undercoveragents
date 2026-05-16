# frozen_string_literal: true

require Rails.root.join("lib/builtin_tools/registrations")

Rails.application.reloader.to_prepare do
  BuiltinTools::Registrations.register_all!
end
