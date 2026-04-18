# frozen_string_literal: true

RSpec.describe 'Accounts' do
  let(:account) { create(:account, name: 'Northwind') }
  let(:account_admin) { create(:user, account:) }
  let(:platform_admin) { create(:user, account:, role: User::PLATFORM_ADMIN_ROLE) }

  describe 'PATCH /admin/application_settings' do
    it 'does not persist the global app url when the value is invalid' do
      # Arrange
      sign_in(platform_admin)

      params = {
        global_encrypted_config: {
          value: 'not a valid url'
        }
      }

      # Initial Assert
      expect(GlobalEncryptedConfig.find_by(key: GlobalEncryptedConfig::APP_URL_KEY)).to be_nil

      # Act
      patch admin_application_settings_path, params: params

      # Assert
      expect(response).to have_http_status(:unprocessable_content)
      expect(GlobalEncryptedConfig.find_by(key: GlobalEncryptedConfig::APP_URL_KEY)).to be_nil
    end
  end

  describe 'DELETE /settings/account' do
    it 'does not let a non-platform account admin archive the whole account' do
      # Arrange
      sign_in(account_admin)

      # Initial Assert
      expect(account.archived_at).to be_nil

      # Act
      delete settings_account_path

      # Assert
      expect(response).to redirect_to(root_path)
      expect(account.reload.archived_at).to be_nil
    end
  end

  describe 'GET /settings/account' do
    it 'does not show the dedicated SMS settings navigation entry' do
      # Arrange
      sign_in(account_admin)

      # Initial Assert
      expect(account_admin.account).to eq(account)

      # Act
      get settings_account_path

      # Assert
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(%(href="#{settings_sms_path}"))
    end

    it 'shows the account home page editor' do
      sign_in(account_admin)

      get settings_account_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Home Page')
      expect(response.body).to include('account_home_page_update_button')
    end
  end

  describe 'PATCH /settings/account' do
    it 'persists account home page content independently of account profile fields' do
      sign_in(account_admin)

      patch settings_account_path, params: { home_page_content: 'Custom account home copy' }

      expect(response).to redirect_to(settings_account_path)
      expect(account.account_configs.find_by(key: AccountConfig::HOME_PAGE_CONTENT_KEY)&.value).to eq('Custom account home copy')
    end
  end

  describe 'GET /settings/sms' do
    it 'redirects back to account settings with the self-hosted SMS message' do
      # Arrange
      sign_in(account_admin)

      # Initial Assert
      expect(account_admin.account).to eq(account)

      # Act
      get settings_sms_path

      # Assert
      expect(response).to redirect_to(settings_account_path)
      expect(flash[:alert]).to eq(I18n.t('sms_delivery_is_not_enabled_for_this_deployment'))
    end
  end

  describe 'GET /settings/email' do
    it 'returns not found' do
      sign_in(account_admin)

      get settings_email_index_path

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST /settings/email' do
    it 'returns not found' do
      sign_in(account_admin)

      post settings_email_index_path, params: {
        encrypted_config: {
          value: {
            host: 'smtp.example.com'
          }
        }
      }

      expect(response).to have_http_status(:not_found)
    end
  end
end
