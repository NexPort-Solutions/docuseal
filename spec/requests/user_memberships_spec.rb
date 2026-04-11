# frozen_string_literal: true

RSpec.describe 'User memberships' do
  let(:account) { create(:account, name: 'Northwind') }
  let(:other_account) { create(:account, name: 'Contoso') }
  let(:account_admin) { create(:user, account:) }

  describe 'POST /users' do
    it 'adds an existing user to the current account with the selected membership role' do
      # Arrange
      existing_user = create(:user, account: other_account, email: 'member@example.com',
                                    first_name: 'Existing', last_name: 'Member')
      sign_in(account_admin)

      params = {
        user: {
          first_name: 'Jamie',
          last_name: 'Rivers',
          email: 'member@example.com',
          membership_role: AccountAccess::VIEWER_ROLE
        }
      }

      # Initial Assert
      expect(existing_user.can_access_account?(account)).to be(false)

      # Act
      post users_path, params: params

      # Assert
      expect(response).to redirect_to(settings_users_path)
      expect(existing_user.reload.account_access_for(account)&.role).to eq(AccountAccess::VIEWER_ROLE)
      expect(existing_user.first_name).to eq('Existing')
      expect(existing_user.last_name).to eq('Member')
      expect(existing_user.archived_at).to be_nil
    end
  end

  describe 'DELETE /users/:id' do
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
      delete user_path(member)

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
      delete user_path(member)

      # Assert
      expect(response).to redirect_to(settings_users_path)
      expect(member.reload.archived_at).to be_present
    end
  end
end
