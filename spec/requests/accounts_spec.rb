# frozen_string_literal: true

RSpec.describe 'Accounts' do
  let(:account) { create(:account, name: 'Northwind') }
  let(:account_admin) { create(:user, account:) }

  describe 'PATCH /settings/account' do
    it 'does not persist branding changes when the app url is invalid' do
      # Arrange
      sign_in(account_admin)

      params = {
        account: {
          name: account.name,
          timezone: account.timezone,
          locale: account.locale
        },
        branding: {
          display_name: 'Northwind Docs'
        },
        encrypted_config: {
          value: 'not a valid url'
        }
      }

      # Initial Assert
      expect(account.branding_settings['display_name']).to be_blank

      # Act
      patch settings_account_path, params: params

      # Assert
      expect(response).to have_http_status(:unprocessable_content)
      expect(account.reload.branding_settings['display_name']).to be_blank
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
end
