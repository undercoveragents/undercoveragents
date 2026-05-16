# frozen_string_literal: true

# Disable HTTP Basic Authentication for Mission Control Jobs dashboard.
# In production, consider enabling authentication or setting credentials via:
#   bin/rails mission_control:jobs:authentication:configure
MissionControl::Jobs.http_basic_auth_enabled = false
