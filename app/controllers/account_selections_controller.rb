# frozen_string_literal: true

class AccountSelectionsController < ApplicationController
  skip_authorization_check only: :create

  def create
    account = accessible_accounts.find(params[:account_id])

    if account.force_sso_auth? && !current_user.platform_admin? && !session[:google_sso_authenticated]
      return redirect_to user_google_oauth2_omniauth_authorize_path(account_id: account.id, login_hint: current_user.email),
                         alert: I18n.t('sign_in_with_google_workspace_for_your_division')
    end

    select_current_account!(account)

    redirect_to safe_redirect_path, notice: I18n.t('switched_to_account_name', name: account.branded_name)
  end

  private

  def safe_redirect_path
    path = params[:redirect_to].to_s

    return path if path.start_with?('/') && !path.start_with?('//')

    root_path
  end
end
