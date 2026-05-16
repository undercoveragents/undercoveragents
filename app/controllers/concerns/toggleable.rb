# frozen_string_literal: true

# Shared concern that extracts the common `toggle` action pattern.
#
# All toggle actions follow the same structure:
#   1. Authorize the record
#   2. Flip the `enabled` boolean
#   3. Build an i18n notice key
#   4. Redirect
#
# Usage:
#   class MyController < ApplicationController
#     include Toggleable
#   end
#
# Requires the including controller to define:
#   - `toggle_record`    → the record to toggle (e.g. @agent)
#   - `toggle_redirect_path` → where to redirect after toggling
#   - `toggle_i18n_prefix`   → e.g. "agents", "tools"
#
# Optionally override `toggle_authorize_action` (defaults to :toggle?).
#
module Toggleable
  extend ActiveSupport::Concern

  def toggle
    record = toggle_record
    authorize record, toggle_authorize_action

    record.update!(enabled: !record.enabled?)
    notice_key = record.enabled? ? "#{toggle_i18n_prefix}.enabled" : "#{toggle_i18n_prefix}.disabled"
    redirect_to toggle_redirect_path, notice: t(notice_key)
  end

  private

  def toggle_authorize_action
    :toggle?
  end

  # Subclasses must implement these:

  # :nocov:
  def toggle_record
    raise NotImplementedError, "#{self.class}#toggle_record must be defined"
  end

  def toggle_redirect_path
    raise NotImplementedError, "#{self.class}#toggle_redirect_path must be defined"
  end

  def toggle_i18n_prefix
    raise NotImplementedError, "#{self.class}#toggle_i18n_prefix must be defined"
  end
  # :nocov:
end
