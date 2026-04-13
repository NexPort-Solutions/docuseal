# frozen_string_literal: true

RSpec.describe 'Admin console' do
  let(:account) { create(:account, name: 'Northwind') }
  let(:platform_admin) { create(:user, account:, role: User::PLATFORM_ADMIN_ROLE) }
  let(:account_admin) { create(:user, account:) }

  describe 'GET /admin' do
    it 'allows platform admins to open the admin console' do
      # Arrange
      sign_in(platform_admin)

      # Initial Assert
      expect(platform_admin.platform_admin?).to be(true)

      # Act
      get admin_root_path

      # Assert
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t('admin_console'))
      expect(response.body).to include(I18n.t('global_settings'))
    end

    it 'blocks non-platform users from the admin console' do
      # Arrange
      sign_in(account_admin)

      # Initial Assert
      expect(account_admin.platform_admin?).to be(false)

      # Act
      get admin_root_path

      # Assert
      expect(response).to redirect_to(root_path)
      follow_redirect!
      expect(flash[:alert]).to eq(I18n.t('you_are_not_authorized_to_manage_divisions'))
    end
  end

  describe 'PATCH /admin/application_settings' do
    it 'stores app url globally instead of per account' do
      # Arrange
      sign_in(platform_admin)

      params = {
        global_encrypted_config: {
          value: 'https://docs.example.com'
        }
      }

      # Initial Assert
      expect(GlobalEncryptedConfig.find_by(key: GlobalEncryptedConfig::APP_URL_KEY)).to be_nil
      expect(EncryptedConfig.find_by(key: EncryptedConfig::APP_URL_KEY)).to be_nil

      # Act
      patch admin_application_settings_path, params: params

      # Assert
      expect(response).to redirect_to(admin_application_settings_path)
      expect(GlobalEncryptedConfig.find_by!(key: GlobalEncryptedConfig::APP_URL_KEY).value).to eq('https://docs.example.com')
      expect(EncryptedConfig.find_by(key: EncryptedConfig::APP_URL_KEY)).to be_nil
    end
  end

  describe 'PATCH /admin/users/:id' do
    it 'blocks platform admins from archiving themselves' do
      # Arrange
      sign_in(platform_admin)

      params = {
        user: {
          archived_at: Time.current.iso8601
        }
      }

      # Initial Assert
      expect(platform_admin.archived_at).to be_nil

      # Act
      patch admin_user_path(platform_admin), params: params

      # Assert
      expect(response).to redirect_to(root_path)
      expect(platform_admin.reload.archived_at).to be_nil
    end
  end
end
