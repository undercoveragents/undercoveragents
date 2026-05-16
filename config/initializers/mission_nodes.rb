# frozen_string_literal: true

# Built-in mission node registrations live at the bottom of
# app/models/concerns/mission_node_plugin.rb so they run every time
# Zeitwerk loads or reloads that file — no initializer timing needed.
