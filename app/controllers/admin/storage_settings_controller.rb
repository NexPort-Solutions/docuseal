# frozen_string_literal: true

module Admin
  class StorageSettingsController < BaseController
    before_action :load_encrypted_config

    def index; end

    def create
      if @encrypted_config.update(storage_configs)
        LoadActiveStorageConfigs.reload

        redirect_to admin_storage_index_path, notice: I18n.t('changes_have_been_saved')
      else
        render :index, status: :unprocessable_content
      end
    end

    private

    def load_encrypted_config
      @encrypted_config = GlobalEncryptedConfig.find_or_initialize_by(key: GlobalEncryptedConfig::FILES_STORAGE_KEY)
    end

    def storage_configs
      params.require(:global_encrypted_config).permit(value: {}).tap do |e|
        e[:value].compact_blank!
        e.dig(:value, :configs)&.compact_blank!
      end
    end
  end
end
