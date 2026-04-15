# frozen_string_literal: true

module Users
  class OmniauthCallbacksController < Devise::OmniauthCallbacksController
    skip_authorization_check

    def google_oauth2
      return link_google_profile if link_google_profile_intent?

      auth = request.env['omniauth.auth']
      unless auth
        redirect_to new_user_session_path, alert: I18n.t('google_workspace_sign_in_failed')
        return
      end

      hinted_account_id = request.env.dig('omniauth.params', 'account_id')
      result = GoogleOidcAuthenticator.call(auth:,
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
      redirect_to link_google_profile_intent? ? profile_path : new_user_session_path,
                  alert: e.record.errors.full_messages.to_sentence
    rescue ActiveRecord::RecordNotUnique
      redirect_to link_google_profile_intent? ? profile_path : new_user_session_path,
                  alert: 'This Google Workspace profile is already linked to another user.'
    end

    private

    def link_google_profile_intent?
      request.env.dig('omniauth.params', 'intent') == 'link_profile'
    end

    def link_google_profile
      unless current_user
        redirect_to new_user_session_path, alert: 'You need to sign in before linking a Google Workspace profile.'
        return
      end

      auth = request.env['omniauth.auth']
      unless auth
        redirect_to profile_path, alert: I18n.t('google_workspace_sign_in_failed')
        return
      end

      email = auth.dig('info', 'email').to_s.downcase

      if email.blank?
        redirect_to profile_path, alert: I18n.t('google_workspace_sign_in_failed')
        return
      end

      unless auth.dig('info', 'email_verified')
        redirect_to profile_path, alert: I18n.t('google_email_must_be_verified')
        return
      end

      if email != current_user.email.to_s.downcase
        redirect_to profile_path, alert: 'Google Workspace email must match your current profile email.'
        return
      end

      linked_user = User.find_by(provider: auth['provider'], uid: auth['uid'])

      if linked_user.present? && linked_user != current_user
        redirect_to profile_path, alert: 'This Google Workspace profile is already linked to another user.'
        return
      end

      current_user.update!(provider: auth['provider'], uid: auth['uid'])

      redirect_to profile_path, notice: 'Google Workspace has been linked to your profile.'
    end
  end
end
