# frozen_string_literal: true

RSpec.describe 'Account Settings' do
  let!(:account) { create(:account) }
  let!(:user) { create(:user, account:) }

  before do
    sign_in(user)
    visit settings_account_path
  end

  it 'shows pre-filled account settings page' do
    expect(page).to have_content('Account')
    expect(page).to have_field('Company name', with: account.name)
    expect(page).to have_field('Time zone', with: account.timezone)
    expect(page).to have_field('Language', with: account.locale)
  end

  it 'updates the account settings' do
    fill_in 'Company name', with: 'New Company Name'
    select '(GMT+01:00) Berlin', from: 'Time zone'
    select 'Español', from: 'Language'

    find('#account_settings_update_button').click

    account.reload

    expect(account.name).to eq('New Company Name')
    expect(account.timezone).to eq('Berlin')
    expect(account.locale).to eq('es-ES')
  end

  it 'changes the account language' do
    select 'Deutsch', from: 'Language'

    find('#account_settings_update_button').click

    account.reload

    expect(account.locale).to eq('de-DE')
    expect(page).to have_current_path(settings_account_path, ignore_query: true)
    expect(page).to have_content('Konto')
    expect(page).to have_field('Firmenname', with: account.name)
    expect(page).to have_field('Zeitzone', with: account.timezone)
    expect(page).to have_field('Sprache', with: account.locale)
    expect(page).to have_button('Aktualisieren')
  end
end
