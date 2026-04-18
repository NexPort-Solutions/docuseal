# frozen_string_literal: true

module Admin
  class EmailSettingsController < BaseController
    include EncryptedConfigRecovery

    before_action :load_encrypted_config

    def index
      show_unreadable_config_alert
    end

    def create
      @encrypted_config = recover_unreadable_encrypted_config(@encrypted_config, unreadable: @config_unreadable)

      if @encrypted_config.update(email_configs)
        send_smtp_confirmation!(@encrypted_config.value)

        redirect_to admin_email_index_path, notice: I18n.t('changes_have_been_saved')
      else
        @config_value = email_configs.fetch(:value, {})
        render :index, status: :unprocessable_content
      end
    rescue StandardError => e
      @config_value = email_configs.fetch(:value, {}) if params[:global_encrypted_config].present?
      flash.now[:alert] = e.message

      render :index, status: :unprocessable_content
    end

    private

    def load_encrypted_config
      @encrypted_config = GlobalEncryptedConfig.find_or_initialize_by(key: GlobalEncryptedConfig::EMAIL_SMTP_KEY)
      result = EncryptedConfigValueReader.fetch(@encrypted_config,
                                                source: 'global current',
                                                key: GlobalEncryptedConfig::EMAIL_SMTP_KEY)
      @config_value = result.value || {}
      @config_unreadable = result.unreadable
    end

    def email_configs
      params.require(:global_encrypted_config).permit(value: {}).tap do |e|
        e[:value].compact_blank!
      end
    end

    def show_unreadable_config_alert
      return unless @config_unreadable

      flash.now[:alert] = I18n.t('stored_settings_are_unreadable_reenter_and_save',
                                 default: 'Stored settings could not be read. Re-enter them and save again.')
    end

    def send_smtp_confirmation!(smtp_value)
      delivery = SettingsMailer.smtp_successful_setup(smtp_value['from_email'] || current_user.email)
      message = delivery.message
      message.instance_variable_set(ActionMailerConfigsInterceptor::SMTP_SETTINGS_MESSAGE_IVAR,
                                    ActionMailerConfigsInterceptor.build_smtp_configs_hash(smtp_value))
      message.instance_variable_set(ActionMailerConfigsInterceptor::SMTP_FROM_MESSAGE_IVAR, smtp_value['from_email'])
      message.deliver!
    end
  end
end
