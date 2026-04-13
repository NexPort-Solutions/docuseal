# frozen_string_literal: true

module Admin
  class HomeController < BaseController
    skip_authorization_check only: :show
  end
end
