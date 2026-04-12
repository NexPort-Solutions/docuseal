# frozen_string_literal: true

RSpec.describe 'Divisions' do
  let(:platform_account) { create(:account, name: 'Platform') }
  let(:platform_admin) { create(:user, account: platform_account, role: User::PLATFORM_ADMIN_ROLE) }

  before do
    sign_in(platform_admin)
  end

  it 'lets a platform admin create, archive, restore, and support a division' do
    # Arrange
    visit settings_divisions_path

    # Initial Assert
    expect(page).to have_content('Divisions')
    expect(page).to have_link('Add division')

    # Act
    click_link 'Add division'

    fill_in 'Division name', with: 'Acme Health'
    fill_in 'First name', with: 'Dana'
    fill_in 'Last name', with: 'Owens'
    fill_in 'Email', with: 'dana.owens@example.com'
    fill_in 'Display name', with: 'Acme Health Docs'
    fill_in 'Support email', with: 'support@acme-health.example'
    click_button 'Create'

    # Assert
    expect(page).to have_current_path(settings_divisions_path, ignore_query: true)
    expect(page).to have_content('Division has been created.')
    expect(page).to have_content('Acme Health Docs')
    expect(page).to have_content('Acme Health')

    division = Account.find_by!(name: 'Acme Health')
    division_admin = User.find_by!(email: 'dana.owens@example.com')

    expect(division_admin.account).to eq(division)
    expect(division_admin.account_access_for(division)&.role).to eq(AccountAccess::ACCOUNT_ADMIN_ROLE)

    within(:xpath, "//div[contains(@class,'rounded-box')][.//div[contains(.,'Acme Health')]]") do
      click_button 'Archive'
    end

    expect(page).to have_content('Division has been archived.')
    within(:xpath, "//div[contains(@class,'rounded-box')][.//div[contains(.,'Acme Health')]]") do
      expect(page).to have_content('Archived')
      click_button 'Restore'
    end

    expect(page).to have_content('Division has been restored.')
    within(:xpath, "//div[contains(@class,'rounded-box')][.//div[contains(.,'Acme Health')]]") do
      expect(page).to have_no_content('Archived')
      click_button 'Support'
    end

    expect(page).to have_current_path(root_path, ignore_query: true)
    expect(page).to have_content('Now supporting Acme Health.')
    expect(page).to have_link('Settings')
    visit settings_divisions_path
    expect(page).to have_content('You are not authorized to manage divisions.')
  end

  it 'shows an error when the division has no active admin to impersonate' do
    # Arrange
    division = create(:account, name: 'Dormant Division')
    create(:user, account: division, role: User::ADMIN_ROLE).tap do |user|
      user.update_column(:archived_at, Time.current)
    end

    # Act
    visit settings_divisions_path

    within(:xpath, "//div[contains(@class,'rounded-box')][.//div[contains(.,'Dormant Division')]]") do
      click_button 'Support'
    end

    # Assert
    expect(page).to have_current_path(settings_divisions_path, ignore_query: true)
    expect(page).to have_content('This division does not have an active admin to impersonate.')
  end
end
