# frozen_string_literal: true

class SsoSettingsController < ApplicationController
  before_action :load_account_config
  authorize_resource :account_config, parent: false

  def show; end

  def update
    @account_config.value = sso_params.to_h.merge(
      'enabled' => sso_params[:enabled] == 'true',
      'auto_provision' => sso_params[:auto_provision] == 'true'
    )
    @account_config.save!

    redirect_to settings_sso_path, notice: I18n.t('settings_have_been_saved')
  end

  private

  def load_account_config
    @account_config =
      AccountConfig.find_or_initialize_by(account: current_account, key: AccountConfig::GOOGLE_OIDC_SETTINGS_KEY)
  end

  def sso_params
    params.fetch(:google_oidc, ActionController::Parameters.new).permit(:enabled, :auto_provision,
                                                                        :hosted_domains, :allowed_admin_emails)
  end
end
