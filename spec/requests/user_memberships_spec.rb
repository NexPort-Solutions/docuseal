# frozen_string_literal: true

RSpec.describe 'User memberships' do
  let(:account) { create(:account, name: 'Northwind') }
  let(:other_account) { create(:account, name: 'Contoso') }
  let(:account_admin) { create(:user, account:) }
  let(:platform_admin) { create(:user, account:, role: User::PLATFORM_ADMIN_ROLE) }

  describe 'PATCH /members/:id' do
    it 'updates only the current account membership role' do
      # Arrange
      member = create(:user, account:, first_name: 'Jamie', last_name: 'Rivers')
      member.account_accesses.find_by!(account: account).update!(role: AccountAccess::CONTRIBUTOR_ROLE)
      sign_in(account_admin)

      params = {
        member: {
          membership_role: AccountAccess::VIEWER_ROLE,
          first_name: 'Should',
          email: 'ignored@example.com'
        }
      }

      # Initial Assert
      expect(member.account_access_for(account)&.role).to eq(AccountAccess::CONTRIBUTOR_ROLE)
      expect(member.first_name).to eq('Jamie')
      expect(member.email).not_to eq('ignored@example.com')

      # Act
      patch member_path(member), params: params

      # Assert
      expect(response).to redirect_to(settings_users_path)
      expect(member.reload.account_access_for(account)&.role).to eq(AccountAccess::VIEWER_ROLE)
      expect(member.first_name).to eq('Jamie')
      expect(member.email).not_to eq('ignored@example.com')
    end
  end

  describe 'DELETE /members/:id' do
    it 'removes only the current account membership when the user still belongs elsewhere' do
      # Arrange
      member = create(:user, account:)
      member.account_accesses.find_or_create_by!(account: other_account) do |membership|
        membership.role = AccountAccess::CONTRIBUTOR_ROLE
      end
      sign_in(account_admin)

      # Initial Assert
      expect(member.accessible_accounts).to include(account, other_account)

      # Act
      delete member_path(member)

      # Assert
      expect(response).to redirect_to(settings_users_path)
      expect(member.reload.can_access_account?(account)).to be(false)
      expect(member.can_access_account?(other_account)).to be(true)
      expect(member.archived_at).to be_nil
    end

    it 'archives the user when the last membership is removed' do
      # Arrange
      member = create(:user, account:)
      sign_in(account_admin)

      # Initial Assert
      expect(member.account_accesses.count).to eq(1)

      # Act
      delete member_path(member)

      # Assert
      expect(response).to redirect_to(settings_users_path)
      expect(member.reload.archived_at).to be_present
    end
  end

  describe 'POST /admin/users' do
    it 'creates one global user with memberships in multiple accounts' do
      # Arrange
      sign_in(platform_admin)

      params = {
        user: {
          first_name: 'Morgan',
          last_name: 'Lee',
          email: 'morgan.lee@example.com',
          password: 'password123',
          role: User::ADMIN_ROLE,
          memberships: {
            account.id.to_s => { selected: '1', role: AccountAccess::ACCOUNT_ADMIN_ROLE },
            other_account.id.to_s => { selected: '1', role: AccountAccess::VIEWER_ROLE }
          }
        }
      }

      # Initial Assert
      expect(User.find_by(email: 'morgan.lee@example.com')).to be_nil

      # Act
      post admin_users_path, params: params

      # Assert
      expect(response).to redirect_to(admin_users_path)
      user = User.find_by!(email: 'morgan.lee@example.com')
      expect(user.account_access_for(account)&.role).to eq(AccountAccess::ACCOUNT_ADMIN_ROLE)
      expect(user.account_access_for(other_account)&.role).to eq(AccountAccess::VIEWER_ROLE)
      expect(user.accessible_accounts).to match_array([account, other_account])
    end

    it 'rejects account admins from creating users in account settings' do
      # Arrange
      sign_in(account_admin)

      params = {
        user: {
          first_name: 'Blocked',
          last_name: 'User',
          email: 'blocked@example.com',
          password: 'password123',
          memberships: {
            account.id.to_s => { selected: '1', role: AccountAccess::CONTRIBUTOR_ROLE }
          }
        }
      }

      # Initial Assert
      expect(User.find_by(email: 'blocked@example.com')).to be_nil

      # Act
      post admin_users_path, params: params

      # Assert
      expect(response).to redirect_to(root_path)
      expect(User.find_by(email: 'blocked@example.com')).to be_nil
    end
  end
end
