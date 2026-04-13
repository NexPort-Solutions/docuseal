# frozen_string_literal: true

module Admin
  class UsersSendResetPasswordController < BaseController
    LIMIT_DURATION = 10.minutes

    def update
      @user = User.find(params[:user_id])

      if @user.reset_password_sent_at && @user.reset_password_sent_at > LIMIT_DURATION.ago
        redirect_back fallback_location: admin_users_path, notice: I18n.t('email_has_been_sent_already')
      else
        @user.send_reset_password_instructions

        redirect_back fallback_location: admin_users_path,
                      notice: I18n.t('an_email_with_password_reset_instructions_has_been_sent')
      end
    end
  end
end
