# frozen_string_literal: true

RSpec.describe 'Profile' do
  let(:account) { create(:account, name: 'Northwind') }
  let(:user) { create(:user, account:, email: 'member@example.com') }

  describe 'GET /profile' do
    it 'renders the standalone profile page with the Google SSO section' do
      # Arrange
      sign_in(user)
      allow(User).to receive(:google_oauth_available?).and_return(true)

      # Act
      get profile_path

      # Assert
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Profile')
      expect(response.body).to include('SSO Profiles')
      expect(response.body).to include('Google Workspace')
      expect(response.body).not_to include('id="account_settings_menu"')
    end

    it 'shows the linked Google profile state when the user already linked Google' do
      # Arrange
      sign_in(user)
      user.update!(provider: 'google_oauth2', uid: 'google-uid-123')

      # Act
      get profile_path

      # Assert
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Linked as')
      expect(response.body).to include(user.email)
      expect(response.body).to include('Unlink Google')
    end
  end

  describe 'GET /settings/account' do
    it 'keeps a single profile entry point in the navbar and not the settings sidebar' do
      # Arrange
      sign_in(user)
      allow(User).to receive(:google_oauth_available?).and_return(true)

      # Act
      get settings_account_path

      # Assert
      expect(response).to have_http_status(:ok)
      expect(response.body.scan(%(href="#{profile_path}")).size).to eq(1)
    end
  end

  describe 'DELETE /profile/unlink_google' do
    it 'unlinks Google when the user does not belong to a force-sso account' do
      # Arrange
      sign_in(user)
      user.update!(provider: 'google_oauth2', uid: 'google-uid-123')

      # Act
      delete unlink_google_profile_path

      # Assert
      expect(response).to redirect_to(profile_path)
      expect(user.reload.provider).to be_nil
      expect(user.uid).to be_nil
    end

    it 'blocks unlinking when the user still belongs to a force-sso account' do
      # Arrange
      secure_account = create(:account, name: 'Secure')
      create(:account_config, account: secure_account, key: AccountConfig::FORCE_SSO_AUTH_KEY, value: true)
      create(:account_access, user:, account: secure_account, role: AccountAccess::VIEWER_ROLE)
      user.update!(provider: 'google_oauth2', uid: 'google-uid-123')
      sign_in(user)

      # Initial Assert
      expect(user.reload.force_sso_membership_accounts).to include(secure_account)

      # Act
      delete unlink_google_profile_path

      # Assert
      expect(response).to redirect_to(profile_path)
      expect(flash[:alert]).to eq('Google Workspace cannot be unlinked while you still belong to a force-SSO account.')
      expect(user.reload.provider).to eq('google_oauth2')
      expect(user.uid).to eq('google-uid-123')
    end
  end
end
