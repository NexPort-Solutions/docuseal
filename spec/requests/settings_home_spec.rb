# frozen_string_literal: true

RSpec.describe 'Settings home' do
  let(:viewer_account) { create(:account, name: 'Viewer') }
  let(:admin_account) { create(:account, name: 'Admin') }
  let(:second_admin_account) { create(:account, name: 'Operations') }
  let(:user) { create(:user, account: viewer_account) }

  describe 'GET /settings' do
    it 'shows the settings entry link from the dashboard when the current account is viewer-only' do
      # Arrange
      user.account_accesses.find_by!(account: viewer_account).update!(role: AccountAccess::VIEWER_ROLE)
      user.account_accesses.find_or_create_by!(account: admin_account) do |membership|
        membership.role = AccountAccess::ACCOUNT_ADMIN_ROLE
      end
      sign_in(user)

      # Initial Assert
      expect(user.reload.account_admin_for?(viewer_account)).to be(false)
      expect(user.account_admin_for?(admin_account)).to be(true)

      # Act
      get root_path

      # Assert
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('account_settings_button')
    end

    it 'switches to the only admin-managed account before opening settings' do
      # Arrange
      user.account_accesses.find_by!(account: viewer_account).update!(role: AccountAccess::VIEWER_ROLE)
      user.account_accesses.find_or_create_by!(account: admin_account) do |membership|
        membership.role = AccountAccess::ACCOUNT_ADMIN_ROLE
      end
      sign_in(user)

      # Initial Assert
      expect(user.reload.account).to eq(viewer_account)

      # Act
      get settings_home_path

      # Assert
      expect(response).to redirect_to(settings_account_path)
      expect(user.reload.account).to eq(admin_account)
    end

    it 'renders an account chooser when the user admins multiple accounts' do
      # Arrange
      user.account_accesses.find_by!(account: viewer_account).update!(role: AccountAccess::VIEWER_ROLE)
      [admin_account, second_admin_account].each do |account|
        user.account_accesses.find_or_create_by!(account:) do |membership|
          membership.role = AccountAccess::ACCOUNT_ADMIN_ROLE
        end
      end
      sign_in(user)

      # Initial Assert
      expect(user.reload.admin_managed_accounts.map(&:name)).to contain_exactly('Admin', 'Operations')

      # Act
      get settings_home_path

      # Assert
      chooser_document = Nokogiri::HTML(response.body)
      chooser_actions = chooser_document.css("form[action^='/accounts/']")
                                       .select { |form| form.at_css("input[name='redirect_to'][value='#{settings_account_path}']") }
                                       .map { |form| form['action'] }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Admin')
      expect(response.body).to include('Operations')
      expect(chooser_actions).to contain_exactly("/accounts/#{admin_account.id}/select",
                                                 "/accounts/#{second_admin_account.id}/select")
    end
  end
end
