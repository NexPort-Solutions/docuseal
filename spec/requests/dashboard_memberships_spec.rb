# frozen_string_literal: true

RSpec.describe 'Dashboard memberships' do
  let(:primary_account) { create(:account, name: 'Northwind') }
  let(:secondary_account) { create(:account, name: 'Contoso') }
  let(:user) { create(:user, account: primary_account) }

  before do
    user.account_accesses.find_or_create_by!(account: secondary_account) do |membership|
      membership.role = AccountAccess::VIEWER_ROLE
    end
  end

  describe 'GET /' do
    it 'shows account roots when a user belongs to multiple accounts' do
      # Arrange
      sign_in(user)

      # Initial Assert
      expect(user.accessible_accounts.map(&:name)).to include('Northwind', 'Contoso')

      # Act
      get root_path

      # Assert
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Accounts')
      expect(response.body).to include('Northwind')
      expect(response.body).to include('Contoso')
      expect(response.body).to include('Home')
      expect(response.body).to include('Templates')
      expect(response.body).to include('Settings')
      expect(response.body).not_to include('Open Workspace')
    end
  end

  describe 'POST /accounts/:account_id/select' do
    it 'switches the selected account and updates the legacy primary account fallback' do
      # Arrange
      sign_in(user)

      # Initial Assert
      expect(user.reload.account).to eq(primary_account)

      # Act
      post select_account_path(secondary_account), params: { redirect_to: templates_path }

      # Assert
      expect(response).to redirect_to(templates_path)
      expect(user.reload.account).to eq(secondary_account)
    end

    it 'requires Google sign-in before switching into a force-sso account from a local session' do
      # Arrange
      create(:account_config, account: secondary_account, key: AccountConfig::FORCE_SSO_AUTH_KEY, value: true)
      sign_in(user)

      # Initial Assert
      expect(secondary_account.force_sso_auth?).to be(true)

      # Act
      post select_account_path(secondary_account), params: { redirect_to: templates_path }

      # Assert
      expect(response).to redirect_to(user_google_oauth2_omniauth_authorize_path(account_id: secondary_account.id,
                                                                                login_hint: user.email))
    end
  end
end
