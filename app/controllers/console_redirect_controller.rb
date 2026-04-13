# frozen_string_literal: true

class ConsoleRedirectController < ApplicationController
  skip_before_action :authenticate_user!
  skip_authorization_check

  def index
    return redirect_to(new_user_session_path) if true_user.blank?

    redirect_target =
      if current_user.platform_admin?
        admin_root_path
      elsif request.path == '/manage' && can?(:read, AccessToken)
        settings_api_index_path
      elsif can?(:manage, EncryptedConfig)
        settings_account_path
      else
        root_path
      end

    redirect_to redirect_target
  end
end
