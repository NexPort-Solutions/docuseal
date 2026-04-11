# frozen_string_literal: true

class SessionsController < Devise::SessionsController
  before_action :configure_permitted_parameters

  around_action :with_browser_locale

  def create
    email = sign_in_params[:email].to_s.downcase
    user = User.find_by(email:)
    force_sso_accounts = user&.accessible_accounts&.select do |account|
      account.account_configs.find_or_initialize_by(key: AccountConfig::FORCE_SSO_AUTH_KEY).value == true
    end.to_a

    if user.present? && !user.platform_admin? && force_sso_accounts.present? &&
       force_sso_accounts.size == user.accessible_accounts.size
      return redirect_to user_google_oauth2_omniauth_authorize_path(
        { account_id: force_sso_accounts.one? ? force_sso_accounts.first.id : nil, login_hint: email }.compact
      ),
                         alert: I18n.t('sign_in_with_google_workspace_for_your_division')
    end

    if Docuseal.multitenant? && !User.exists?(email:)
      Rollbar.warning('Sign in new user') if defined?(Rollbar)

      return redirect_to new_registration_path(sign_up: true, user: sign_in_params.slice(:email)),
                         notice: I18n.t('create_a_new_account')
    end

    if User.exists?(email:, otp_required_for_login: true) && sign_in_params[:otp_attempt].blank?
      return render :otp, locals: { resource: User.new(sign_in_params) }, status: :unprocessable_content
    end

    session.delete(:google_sso_authenticated)

    super
  end

  private

  def after_sign_in_path_for(...)
    if params[:redir].present?
      return console_redirect_index_path(redir: params[:redir]) if params[:redir].starts_with?(Docuseal::CONSOLE_URL)

      return params[:redir]
    end

    root_path
  end

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_in, keys: [:otp_attempt])
  end

  def set_flash_message(key, kind, options = {})
    return if key == :alert && kind == 'already_authenticated'

    super
  end
end
