# frozen_string_literal: true

module Admin
  class ApplicationSettingsController < BaseController
    include EncryptedConfigRecovery

    before_action :load_encrypted_config

    def show
      show_unreadable_config_alert
    end

    def update
      @encrypted_config = recover_unreadable_encrypted_config(@encrypted_config, unreadable: @config_unreadable)
      @config_value = application_settings_params[:value].to_s
      @encrypted_config.assign_attributes(value: @config_value)

      unless valid_http_url?(@config_value)
        @encrypted_config.errors.add(:value, I18n.t('should_be_a_valid_url'))

        return render :show, status: :unprocessable_content
      end

      @encrypted_config.save!
      Docuseal.refresh_default_url_options!

      redirect_to admin_application_settings_path, notice: I18n.t('changes_have_been_saved')
    rescue ActiveRecord::RecordInvalid
      render :show, status: :unprocessable_content
    end

    private

    def load_encrypted_config
      @encrypted_config = GlobalEncryptedConfig.find_or_initialize_by(key: GlobalEncryptedConfig::APP_URL_KEY)
      result = EncryptedConfigValueReader.fetch(@encrypted_config,
                                                source: 'global current',
                                                key: GlobalEncryptedConfig::APP_URL_KEY)
      @config_value = result.value.to_s
      @config_unreadable = result.unreadable
    end

    def application_settings_params
      params.require(:global_encrypted_config).permit(:value)
    end

    def show_unreadable_config_alert
      return unless @config_unreadable

      flash.now[:alert] = I18n.t('stored_settings_are_unreadable_reenter_and_save',
                                 default: 'Stored settings could not be read. Re-enter them and save again.')
    end

    def valid_http_url?(value)
      URI.parse(value).class.in?([URI::HTTP, URI::HTTPS])
    rescue URI::InvalidURIError
      false
    end
  end
end
