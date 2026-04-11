# frozen_string_literal: true

RSpec.describe 'Divisions' do
  let(:platform_account) { create(:account) }
  let(:platform_admin) { create(:user, account: platform_account, role: User::PLATFORM_ADMIN_ROLE) }

  describe 'GET /settings/divisions' do
    it 'redirects non-platform admins away from division management' do
      # Arrange
      admin = create(:user)

      # Initial Assert
      expect(admin.platform_admin?).to be(false)

      sign_in(admin)

      # Act
      get settings_divisions_path

      # Assert
      expect(response).to redirect_to(root_path)

      follow_redirect!

      expect(response.body).to include('You are not authorized to manage divisions.')
    end
  end

  describe 'POST /settings/divisions' do
    it 'creates a division, first admin, and branding settings' do
      # Arrange
      sign_in(platform_admin)

      params = {
        account: {
          name: 'Acme Health',
          locale: 'en-US',
          timezone: 'UTC'
        },
        division_admin: {
          first_name: 'Dana',
          last_name: 'Owens',
          email: 'dana.owens@example.com'
        },
        branding: {
          display_name: 'Acme Health Docs',
          sender_name: 'Acme Notifications',
          support_email: 'support@acme-health.example',
          default_reply_to: 'reply@acme-health.example',
          primary_color: '#123456',
          secondary_color: '#abcdef'
        }
      }

      # Initial Assert
      expect(Account.where(name: 'Acme Health')).to be_empty
      expect(User.where(email: 'dana.owens@example.com')).to be_empty

      # Act
      expect do
        post settings_divisions_path, params:
      end.to change(Account, :count).by(1).and change(User, :count).by(1)

      # Assert
      expect(response).to redirect_to(settings_divisions_path)
      expect(flash[:notice]).to eq('Division has been created.')

      division = Account.find_by!(name: 'Acme Health')
      admin = User.find_by!(email: 'dana.owens@example.com')

      expect(admin.account).to eq(division)
      expect(admin.role).to eq(User::ADMIN_ROLE)
      expect(admin.account_access_for(division)&.role).to eq(AccountAccess::ACCOUNT_ADMIN_ROLE)
      expect(division.branding_settings).to include(
        'display_name' => 'Acme Health Docs',
        'sender_name' => 'Acme Notifications',
        'support_email' => 'support@acme-health.example',
        'default_reply_to' => 'reply@acme-health.example',
        'primary_color' => '#123456',
        'secondary_color' => '#abcdef'
      )
    end
  end

  describe 'POST /settings/divisions/:id/archive' do
    it 'archives a division' do
      # Arrange
      division = create(:account, archived_at: nil)
      sign_in(platform_admin)

      # Initial Assert
      expect(division.archived_at).to be_nil

      # Act
      post archive_settings_division_path(division)

      # Assert
      expect(response).to redirect_to(settings_divisions_path)
      expect(flash[:notice]).to eq('Division has been archived.')
      expect(division.reload.archived_at).to be_present
    end
  end

  describe 'POST /settings/divisions/:id/restore' do
    it 'restores an archived division' do
      # Arrange
      division = create(:account, archived_at: Time.current)
      sign_in(platform_admin)

      # Initial Assert
      expect(division.archived_at).to be_present

      # Act
      post restore_settings_division_path(division)

      # Assert
      expect(response).to redirect_to(settings_divisions_path)
      expect(flash[:notice]).to eq('Division has been restored.')
      expect(division.reload.archived_at).to be_nil
    end
  end

  describe 'POST /settings/divisions/:id/impersonate' do
    it 'lets a platform admin support an active division admin' do
      # Arrange
      division = create(:account)
      division_admin = create(:user, account: division, role: User::ADMIN_ROLE)
      sign_in(platform_admin)

      # Initial Assert
      expect(division.active_users.find_by(role: User::ADMIN_ROLE)).to eq(division_admin)

      # Act
      post impersonate_settings_division_path(division)

      # Assert
      expect(response).to redirect_to(root_path)
      expect(flash[:notice]).to eq("Now supporting #{division.name}.")

      get settings_divisions_path

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq('You are not authorized to manage divisions.')
    end

    it 'refuses support mode when the division has no active admin' do
      # Arrange
      division = create(:account)
      create(:user, account: division, role: User::ADMIN_ROLE).tap do |user|
        user.update_column(:archived_at, Time.current)
      end
      sign_in(platform_admin)

      # Initial Assert
      expect(division.active_users.find_by(role: User::ADMIN_ROLE)).to be_nil

      # Act
      post impersonate_settings_division_path(division)

      # Assert
      expect(response).to redirect_to(settings_divisions_path)
      expect(flash[:alert]).to eq('This division does not have an active admin to impersonate.')
    end
  end
end
