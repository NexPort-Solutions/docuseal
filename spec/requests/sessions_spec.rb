# frozen_string_literal: true

RSpec.describe 'Sessions' do
  before do
    allow(User).to receive(:google_oauth_available?).and_return(true)
  end

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
      original_test_mode = OmniAuth.config.test_mode
      original_mock_auth = OmniAuth.config.mock_auth[:google_oauth2]
      original_params = Rails.application.env_config['omniauth.params']
      original_auth = Rails.application.env_config['omniauth.auth']

      OmniAuth.config.test_mode = true
      OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(auth_hash)
      Rails.application.env_config['omniauth.params'] = { 'account_id' => force_sso_account.id.to_s }
      Rails.application.env_config['omniauth.auth'] = OmniAuth::AuthHash.new(auth_hash)
      example.run
    ensure
      OmniAuth.config.test_mode = original_test_mode
      OmniAuth.config.mock_auth[:google_oauth2] = original_mock_auth
      Rails.application.env_config['omniauth.params'] = original_params
      Rails.application.env_config['omniauth.auth'] = original_auth
    end

    it 'allows switching into the hinted force-sso account after a successful Google callback' do
      # Arrange
      create(:account_config, account: force_sso_account, key: AccountConfig::FORCE_SSO_AUTH_KEY, value: true)
      create(:account_config,
             account: force_sso_account,
             key: AccountConfig::GOOGLE_OIDC_SETTINGS_KEY,
             value: { 'enabled' => true, 'allowed_viewer_emails' => user.email })
      user.account_accesses.find_or_create_by!(account: force_sso_account) do |membership|
        membership.role = AccountAccess::VIEWER_ROLE
      end

      # Initial Assert
      expect(force_sso_account.force_sso_auth?).to be(true)

      # Act
      post user_google_oauth2_omniauth_callback_path
      post select_account_path(force_sso_account), params: { redirect_to: templates_path }

      # Assert
      expect(response).to redirect_to(templates_path)
    end
  end

  describe 'POST /auth/google_oauth2/callback when linking a profile' do
    let(:account) { create(:account, name: 'Primary') }
    let(:user) { create(:user, account:, email: 'member@example.com', provider: nil, uid: nil) }
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
      original_test_mode = OmniAuth.config.test_mode
      original_mock_auth = OmniAuth.config.mock_auth[:google_oauth2]
      original_params = Rails.application.env_config['omniauth.params']
      original_auth = Rails.application.env_config['omniauth.auth']

      OmniAuth.config.test_mode = true
      OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(auth_hash)
      Rails.application.env_config['omniauth.params'] = { 'intent' => 'link_profile' }
      Rails.application.env_config['omniauth.auth'] = OmniAuth::AuthHash.new(auth_hash)
      example.run
    ensure
      OmniAuth.config.test_mode = original_test_mode
      OmniAuth.config.mock_auth[:google_oauth2] = original_mock_auth
      Rails.application.env_config['omniauth.params'] = original_params
      Rails.application.env_config['omniauth.auth'] = original_auth
    end

    it 'links the signed in user without changing memberships or creating another user' do
      # Arrange
      sign_in(user)
      memberships_before = user.account_accesses.order(:account_id).pluck(:account_id, :role)

      # Initial Assert
      expect(user.google_profile_linked?).to be(false)

      # Act
      post user_google_oauth2_omniauth_callback_path

      # Assert
      expect(response).to redirect_to(profile_path)
      expect(user.reload.provider).to eq('google_oauth2')
      expect(user.uid).to eq('google-uid-123')
      expect(user.account_accesses.order(:account_id).pluck(:account_id, :role)).to eq(memberships_before)
      expect(User.where(email: user.email).count).to eq(1)
    end

    it 'does not satisfy force-sso account switching until a real Google sign-in succeeds' do
      # Arrange
      secure_account = create(:account, name: 'Secure')
      create(:account_config, account: secure_account, key: AccountConfig::FORCE_SSO_AUTH_KEY, value: true)
      create(:account_access, user:, account: secure_account, role: AccountAccess::VIEWER_ROLE)
      sign_in(user)

      # Initial Assert
      expect(user.reload.google_profile_linked?).to be(false)

      # Act
      post user_google_oauth2_omniauth_callback_path
      post select_account_path(secure_account), params: { redirect_to: templates_path }

      # Assert
      expect(response).to redirect_to(user_google_oauth2_omniauth_authorize_path(account_id: secure_account.id,
                                                                                login_hint: user.email))
    end

    it 'rejects linking when the Google email differs from the signed in profile email' do
      # Arrange
      sign_in(user)
      auth_hash['info']['email'] = 'other@example.com'
      Rails.application.env_config['omniauth.auth'] = OmniAuth::AuthHash.new(auth_hash)

      # Act
      post user_google_oauth2_omniauth_callback_path

      # Assert
      expect(response).to redirect_to(profile_path)
      expect(flash[:alert]).to eq('Google Workspace email must match your current profile email.')
      expect(user.reload.google_profile_linked?).to be(false)
    end

    it 'rejects linking when the Google identity is already linked to another user' do
      # Arrange
      sign_in(user)
      create(:user, account: create(:account), email: 'other@example.com', provider: 'google_oauth2', uid: 'google-uid-123')

      # Act
      post user_google_oauth2_omniauth_callback_path

      # Assert
      expect(response).to redirect_to(profile_path)
      expect(flash[:alert]).to eq('This Google Workspace profile is already linked to another user.')
      expect(user.reload.google_profile_linked?).to be(false)
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

  describe 'GET /sign_in' do
    it 'renders the Google sign-in request form' do
      # Arrange
      create(:user, account: create(:account))
      Warden.test_reset!

      # Act
      get new_user_session_path
      follow_redirect! if response.redirect?

      # Assert
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('action="/auth/google_oauth2"')
      expect(response.body).to include('method="post"')
    end
  end
end
