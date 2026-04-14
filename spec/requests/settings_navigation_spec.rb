# frozen_string_literal: true

RSpec.describe 'Settings navigation' do
  let(:primary_account) { create(:account, name: 'Northwind') }
  let!(:secondary_account) { create(:account, name: 'Tailspin') }
  let(:platform_admin) { create(:user, account: primary_account, role: User::PLATFORM_ADMIN_ROLE) }

  describe 'GET /settings/account' do
    it 'removes redundant settings switching controls while keeping the navbar selector' do
      # Arrange
      sign_in(platform_admin)

      # Initial Assert
      expect(Account.active.count).to be >= 2
      expect(platform_admin.accessible_accounts.map(&:branded_name)).to include('Northwind', 'Tailspin')

      # Act
      get settings_account_path

      # Assert
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(settings_divisions_path)
      expect(response.body).not_to include(I18n.t('switch_account'))
      expect(response.body).to include(select_account_path(secondary_account))
      expect(response.body).to include(secondary_account.branded_name)
    end
  end
end
