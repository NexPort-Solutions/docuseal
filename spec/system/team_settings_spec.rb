# frozen_string_literal: true

RSpec.describe 'Team Settings' do
  let(:account) { create(:account) }
  let(:current_user) { create(:user, account:) }

  before do
    sign_in(current_user)
  end

  context 'when managing account members' do
    let!(:members) { create_list(:user, 2, account:) }
    let!(:other_user) { create(:user) }

    before do
      visit settings_users_path
    end

    it 'shows only current account members and does not expose new-user creation' do
      within '.table' do
        members.each do |member|
          expect(page).to have_content(member.full_name)
          expect(page).to have_content(member.email)
          expect(page).to have_link('Edit', href: edit_member_path(member))
        end

        expect(page).to have_button('Remove')
        expect(page).to have_no_content(other_user.full_name)
        expect(page).to have_no_content(other_user.email)
      end
      expect(page).to have_no_link('New User')
    end

    it 'updates only the membership role' do
      find(:link, 'Edit', href: edit_member_path(members.first)).click

      within '#modal' do
        select 'Viewer', from: 'Account role'

        click_button 'Update'
      end

      expect(members.first.reload.account_access_for(account)&.role).to eq(AccountAccess::VIEWER_ROLE)
    end

    it 'removes a membership' do
      expect do
        first(:button, 'Remove').click
      end.to change { account.members.active.count }.by(-1)

      expect(page).to have_content('User has been removed')
    end
  end

  context 'when single user' do
    before do
      visit settings_users_path
    end

    it 'does not allow to remove the current user' do
      expect(page).to have_no_content('User has been removed')
    end
  end
end
