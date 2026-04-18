# frozen_string_literal: true

class EmailSmtpSettingsController < ApplicationController
  include EncryptedConfigRecovery

  before_action :load_encrypted_config
  authorize_resource :encrypted_config, only: :index
  authorize_resource :encrypted_config, parent: false, only: :create

  def index
    show_unreadable_config_alert
  end

  def create
    @encrypted_config = recover_unreadable_encrypted_config(@encrypted_config, unreadable: @config_unreadable)

    if @encrypted_config.update(email_configs)
      unless Docuseal.multitenant?
        SettingsMailer.smtp_successful_setup(@encrypted_config.value['from_email'] || current_user.email).deliver_now!
      end

      redirect_to settings_email_index_path, notice: I18n.t('changes_have_been_saved')
    else
      @config_value = email_configs.fetch(:value, {})
      render :index, status: :unprocessable_content
    end
  rescue StandardError => e
    @config_value = email_configs.fetch(:value, {}) if params[:encrypted_config].present?
    flash.now[:alert] = e.message

    render :index, status: :unprocessable_content
  end

  private

  def load_encrypted_config
    @encrypted_config =
      EncryptedConfig.find_or_initialize_by(account: current_account, key: EncryptedConfig::EMAIL_SMTP_KEY)
    result = EncryptedConfigValueReader.fetch(@encrypted_config,
                                              source: "account #{current_account.id}",
                                              key: EncryptedConfig::EMAIL_SMTP_KEY)
    @config_value = result.value || {}
    @config_unreadable = result.unreadable
  end

  def email_configs
    params.require(:encrypted_config).permit(value: {}).tap do |e|
      e[:value].compact_blank!
    end
  end

  def show_unreadable_config_alert
    return unless @config_unreadable

    flash.now[:alert] = I18n.t('stored_settings_are_unreadable_reenter_and_save',
                               default: 'Stored settings could not be read. Re-enter them and save again.')
  end
end
