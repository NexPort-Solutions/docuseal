# frozen_string_literal: true

class SettingsHomeController < ApplicationController
  skip_authorization_check only: :show

  def show
    if current_user.platform_admin? || current_user.account_admin_for?(current_account)
      return redirect_to settings_account_path
    end

    if admin_managed_accounts.one?
      select_current_account!(admin_managed_accounts.first)

      return redirect_to settings_account_path,
                         notice: I18n.t('switched_to_account_name', name: current_account.branded_name)
    end

    raise CanCan::AccessDenied, 'You are not authorized to access this page.' if admin_managed_accounts.blank?

    @accounts = admin_managed_accounts
  end
end
