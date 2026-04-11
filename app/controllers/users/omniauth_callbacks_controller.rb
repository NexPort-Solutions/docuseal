# frozen_string_literal: true

module Users
  class OmniauthCallbacksController < Devise::OmniauthCallbacksController
    skip_authorization_check

    def google_oauth2
      hinted_account_id = request.env.dig('omniauth.params', 'account_id')
      result = GoogleOidcAuthenticator.call(auth: request.env['omniauth.auth'],
                                            hinted_account_id:)

      if result.success?
        session[:google_sso_authenticated] = true
        session[:selected_account_id] = hinted_account_id if hinted_account_id.present? &&
                                                       result.user.can_access_account?(Account.find_by(id: hinted_account_id))
        sign_in(result.user)
        redirect_to after_sign_in_path_for(result.user), notice: I18n.t('successfully_signed_in_with_google')
      else
        redirect_to new_user_session_path, alert: result.error
      end
    rescue ActiveRecord::RecordInvalid => e
      redirect_to new_user_session_path, alert: e.record.errors.full_messages.to_sentence
    end
  end
end
