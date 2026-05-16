# frozen_string_literal: true

# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
Rails.root.glob("plugins/**/app/javascript/controllers").each do |plugin_controllers_path|
  pin_all_from plugin_controllers_path, under: "controllers"
end
pin_all_from "app/javascript/utils", under: "utils"
pin "choices.js" # @11.2.3
pin "overtype", to: "overtype.js" # @2.3.10
pin "stream-markdown-parser" # @0.0.95
pin "@hotwired/turbo-rails", to: "@hotwired--turbo-rails.js" # @8.0.23
pin "@hotwired/turbo", to: "@hotwired--turbo.js" # @8.0.23
pin "@rails/actioncable/src", to: "@rails--actioncable--src.js" # @8.1.300
pin "chartkick" # @5.0.1
pin "highcharts" # @12.6.0
pin "lexxy", to: "lexxy.js"
pin "@rails/activestorage", to: "activestorage.esm.js"
