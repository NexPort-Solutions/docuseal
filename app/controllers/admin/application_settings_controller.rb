# frozen_string_literal: true

module Admin
  class ApplicationSettingsController < BaseController
    before_action :load_encrypted_config

    def show; end

    def update
      @encrypted_config.assign_attributes(application_settings_params)

      unless valid_http_url?(@encrypted_config.value.to_s)
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
    end

    def application_settings_params
      params.require(:global_encrypted_config).permit(:value)
    end

    def valid_http_url?(value)
      URI.parse(value).class.in?([URI::HTTP, URI::HTTPS])
    rescue URI::InvalidURIError
      false
    end
  end
end
