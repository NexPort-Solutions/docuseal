# frozen_string_literal: true

module Admin
  class BaseController < ApplicationController
    before_action :authorize_platform_admin!

    private

    def authorize_platform_admin!
      raise CanCan::AccessDenied, I18n.t('you_are_not_authorized_to_manage_divisions') unless current_user&.platform_admin?

      authorize!(:manage, :all)
    end
  end
end
