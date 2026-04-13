# frozen_string_literal: true

module Admin
  class GlobalSettingsController < BaseController
    skip_authorization_check only: :show
  end
end
