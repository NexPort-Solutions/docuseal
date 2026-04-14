# frozen_string_literal: true

RSpec.describe 'Sessions' do
  describe 'POST /sign_in' do
    it 'redirects to Google Workspace when all accessible accounts enforce force-sso' do
      # Arrange
      account = create(:account)
      create(:account_config, account:, key: AccountConfig::FORCE_SSO_AUTH_KEY, value: true)
      user = create(:user, account:, email: 'member@example.com', password: 'Password123!')

      # Initial Assert
      expect(user.accessible_accounts).to contain_exactly(account)
      expect(account.force_sso_auth?).to be(true)

      # Act
      post user_session_path, params: { user: { email: user.email, password: 'Password123!' } }

      # Assert
      expect(response).to redirect_to(user_google_oauth2_omniauth_authorize_path(account_id: account.id,
                                                                                login_hint: user.email))
    end
  end

  describe 'POST /auth/google_oauth2/callback' do
    let(:primary_account) { create(:account, name: 'Primary') }
    let(:force_sso_account) { create(:account, name: 'Secure') }
    let(:user) { create(:user, account: primary_account, email: 'member@example.com') }
    let(:auth_hash) do
      {
        'provider' => 'google_oauth2',
        'uid' => 'google-uid-123',
        'info' => {
          'email' => user.email,
          'email_verified' => true,
          'first_name' => user.first_name,
          'last_name' => user.last_name,
          'name' => user.full_name
        }
      }
    end

    around do |example|
      original_auth = Rails.application.env_config['omniauth.auth']
      original_params = Rails.application.env_config['omniauth.params']
      Rails.application.env_config['omniauth.auth'] = auth_hash
      Rails.application.env_config['omniauth.params'] = { 'account_id' => force_sso_account.id.to_s }
      example.run
    ensure
      Rails.application.env_config['omniauth.auth'] = original_auth
      Rails.application.env_config['omniauth.params'] = original_params
    end

    it 'allows switching into the hinted force-sso account after a successful Google callback' do
      # Arrange
      create(:account_config, account: force_sso_account, key: AccountConfig::FORCE_SSO_AUTH_KEY, value: true)
      user.account_accesses.find_or_create_by!(account: force_sso_account) do |membership|
        membership.role = AccountAccess::VIEWER_ROLE
      end

      result = GoogleOidcAuthenticator::Result.new(user:)
      allow(GoogleOidcAuthenticator).to receive(:call)
        .with(auth: auth_hash, hinted_account_id: force_sso_account.id.to_s)
        .and_return(result)

      # Initial Assert
      expect(force_sso_account.force_sso_auth?).to be(true)

      # Act
      post user_google_oauth2_omniauth_callback_path
      post select_account_path(force_sso_account), params: { redirect_to: templates_path }

      # Assert
      expect(response).to redirect_to(templates_path)
    end
  end

  describe 'GET /settings/sso' do
    it 'shows the updated account-only role descriptions and no auto-provision toggle' do
      # Arrange
      account = create(:account)
      user = create(:user, account:)
      sign_in(user)

      # Act
      get settings_sso_path

      # Assert
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Account access only')
      expect(response.body).to include('Allowed viewer emails')
      expect(response.body).to include('Allowed contributor emails')
      expect(response.body).not_to include('Auto-provision matched admins')
     end
  end
end
