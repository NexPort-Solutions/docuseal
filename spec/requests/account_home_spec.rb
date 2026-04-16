# frozen_string_literal: true

RSpec.describe 'Account home' do
  describe 'GET /home' do
    it 'renders the default account home content and templates link' do
      user = create(:user)
      sign_in(user)

      get account_home_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(user.account.branded_name)
      expect(response.body).to include('Go to Templates')
      expect(response.body).to include(%(href="#{templates_path}"))
    end

    it 'renders saved home page content for the current account' do
      user = create(:user)
      create(:account_config, account: user.account, key: AccountConfig::HOME_PAGE_CONTENT_KEY, value: '**Custom welcome**')
      sign_in(user)

      get account_home_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Custom welcome')
    end

    it 'changes content when switching accounts' do
      primary_account = create(:account, name: 'Northwind')
      secondary_account = create(:account, name: 'Tailspin')
      user = create(:user, account: primary_account, role: User::PLATFORM_ADMIN_ROLE)
      create(:account_config, account: primary_account, key: AccountConfig::HOME_PAGE_CONTENT_KEY, value: 'Primary content')
      create(:account_config, account: secondary_account, key: AccountConfig::HOME_PAGE_CONTENT_KEY, value: 'Secondary content')
      sign_in(user)

      post select_account_path(secondary_account), params: { redirect_to: account_home_path }
      follow_redirect!

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Secondary content')
      expect(response.body).not_to include('Primary content')
    end
  end
end
