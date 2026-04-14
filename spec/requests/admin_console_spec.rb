# frozen_string_literal: true

RSpec.describe 'Admin console' do
  let(:account) { create(:account, name: 'Northwind') }
  let(:second_account) { create(:account, name: 'Tailspin') }
  let(:archived_account) { create(:account, name: 'Archive Only', archived_at: Time.current) }
  let(:platform_admin) { create(:user, account:, role: User::PLATFORM_ADMIN_ROLE) }
  let(:account_admin) { create(:user, account:) }
  let!(:listed_user) { create(:user, account:, first_name: 'Casey', last_name: 'Jones', email: 'casey@example.com') }
  let!(:active_membership) { create(:account_access, user: listed_user, account: second_account, role: AccountAccess::VIEWER_ROLE) }
  let!(:archived_membership) { create(:account_access, user: listed_user, account: archived_account, role: AccountAccess::CONTRIBUTOR_ROLE) }
  let!(:archived_user) do
    create(:user, account:, first_name: 'Archived', last_name: 'Member', email: 'archived@example.com', archived_at: Time.current)
  end

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

  describe 'GET /admin/users' do
    it 'shows a memberships column instead of role and accounts columns' do
      # Arrange
      sign_in(platform_admin)

      # Initial Assert
      expect(listed_user.active_membership_count).to eq(2)
      expect(archived_user.archived_at).to be_present

      # Act
      get admin_users_path

      # Assert
      expect(response).to have_http_status(:ok)

      document = Nokogiri::HTML.parse(response.body)
      headers = document.css('table thead th').map { |header| header.text.strip }
      membership_link = document.at_css("a[href='#{memberships_admin_user_path(listed_user)}']")

      expect(headers).to include(I18n.t('memberships'))
      expect(headers).not_to include(I18n.t('role'))
      expect(headers).not_to include(I18n.t('accounts'))
      expect(membership_link.text.strip).to eq('2')
      expect(membership_link['data-turbo-frame']).to eq('modal')
      expect(response.body).to include(archived_user.full_name)
      expect(response.body).to include(I18n.t('archived'))
    end
  end

  describe 'GET /admin/users/:id/memberships' do
    it 'shows active memberships in a read-only modal with a link to edit the user' do
      # Arrange
      sign_in(platform_admin)

      # Initial Assert
      expect(listed_user.active_account_accesses.map { |membership| membership.account.branded_name }).to contain_exactly('Northwind', 'Tailspin')
      expect(listed_user.account_accesses.find_by(account: archived_account)).to be_present

      # Act
      get memberships_admin_user_path(listed_user)

      # Assert
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('<turbo-frame id="modal">')
      expect(response.body).to include(account.branded_name)
      expect(response.body).to include(second_account.branded_name)
      expect(response.body).to include(I18n.t(AccountAccess::ACCOUNT_ADMIN_ROLE))
      expect(response.body).to include(I18n.t(AccountAccess::VIEWER_ROLE))
      expect(response.body).not_to include(archived_account.branded_name)
      expect(response.body).to include(edit_admin_user_path(listed_user))
    end
  end
end
