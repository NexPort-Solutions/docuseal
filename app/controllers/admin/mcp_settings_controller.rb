# frozen_string_literal: true

module Admin
  class McpSettingsController < BaseController
    before_action :load_global_config

    def show; end

    def update
      @global_config.update!(global_config_params)

      redirect_to admin_mcp_settings_path, notice: I18n.t('changes_have_been_saved')
    rescue ActiveRecord::RecordInvalid
      render :show, status: :unprocessable_content
    end

    private

    def load_global_config
      @global_config = GlobalConfig.find_or_initialize_by(key: GlobalConfig::ENABLE_MCP_KEY)
    end

    def global_config_params
      params.require(:global_config).permit(:value).tap do |attrs|
        attrs[:value] = attrs[:value] == '1' if attrs[:value].in?(%w[1 0])
      end
    end
  end
end
