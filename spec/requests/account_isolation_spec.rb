# frozen_string_literal: true

RSpec.describe 'Account isolation' do
  let(:primary_account) { create(:account, name: 'Northwind') }
  let(:secondary_account) { create(:account, name: 'Contoso') }
  let(:outsider_account) { create(:account, name: 'Fabrikam') }
  let(:user) { create(:user, account: primary_account, email: 'operator@example.com') }
  let!(:secondary_membership) do
    user.account_accesses.find_or_create_by!(account: secondary_account) do |membership|
      membership.role = AccountAccess::ACCOUNT_ADMIN_ROLE
    end
  end

  let!(:primary_folder) { create(:template_folder, account: primary_account, author: user, name: 'Northwind Folder') }
  let!(:secondary_folder) { create(:template_folder, account: secondary_account, author: user, name: 'Contoso Folder') }
  let!(:primary_template) do
    create(:template, account: primary_account, author: user, folder: primary_folder, name: 'Northwind NDA')
  end
  let!(:secondary_template) do
    create(:template, account: secondary_account, author: user, folder: secondary_folder, name: 'Contoso MSA')
  end
  let!(:primary_root_template) do
    create(:template, account: primary_account, author: user, name: 'Northwind Root Template')
  end
  let!(:secondary_root_template) do
    create(:template, account: secondary_account, author: user, name: 'Contoso Root Template')
  end
  let!(:primary_submission) do
    create(:submission, template: primary_template, created_by_user: user, name: 'Northwind Submission')
  end
  let!(:secondary_submission) do
    create(:submission, template: secondary_template, created_by_user: user, name: 'Contoso Submission')
  end
  let!(:primary_member) do
    create(:user, account: primary_account, email: 'primary.member@example.com', first_name: 'Primary', last_name: 'Member')
  end
  let!(:secondary_member) do
    create(:user, account: secondary_account, email: 'secondary.member@example.com', first_name: 'Secondary',
                  last_name: 'Member')
  end

  before do
    create(:account_config, account: primary_account, key: AccountConfig::BRANDING_SETTINGS_KEY,
                            value: {
                              'display_name' => 'Northwind Docs',
                              'support_email' => 'northwind-support@example.com'
                            })
    create(:account_config, account: secondary_account, key: AccountConfig::BRANDING_SETTINGS_KEY,
                            value: {
                              'display_name' => 'Contoso Docs',
                              'support_email' => 'contoso-support@example.com'
                            })
  end

  describe 'GET /templates' do
    it 'shows only the selected account templates and folders' do
      # Arrange
      sign_in(user)

      # Initial Assert
      expect(user.reload.account).to eq(primary_account)

      # Act
      get templates_path

      # Assert
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Northwind Folder')
      expect(response.body).to include('Northwind Root Template')
      expect(response.body).not_to include('Contoso Folder')
      expect(response.body).not_to include('Contoso Root Template')

      post select_account_path(secondary_account), params: { redirect_to: templates_path }
      follow_redirect!

      expect(user.reload.account).to eq(secondary_account)
      expect(response.body).to include('Contoso Folder')
      expect(response.body).to include('Contoso Root Template')
      expect(response.body).not_to include('Northwind Folder')
      expect(response.body).not_to include('Northwind Root Template')
    end
  end

  describe 'GET /submissions' do
    it 'shows only the selected account submissions' do
      # Arrange
      sign_in(user)

      # Initial Assert
      expect(user.reload.account).to eq(primary_account)

      # Act
      get submissions_path

      # Assert
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Northwind Submission')
      expect(response.body).not_to include('Contoso Submission')

      post select_account_path(secondary_account), params: { redirect_to: submissions_path }
      follow_redirect!

      expect(user.reload.account).to eq(secondary_account)
      expect(response.body).to include('Contoso Submission')
      expect(response.body).not_to include('Northwind Submission')
    end
  end

  describe 'GET /settings/users' do
    it 'shows only members of the selected account' do
      # Arrange
      sign_in(user)

      # Initial Assert
      expect(user.reload.account_admin_for?(primary_account)).to be(true)
      expect(user.account_admin_for?(secondary_account)).to be(true)

      # Act
      get settings_users_path

      # Assert
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('primary.member@example.com')
      expect(response.body).not_to include('secondary.member@example.com')

      post select_account_path(secondary_account), params: { redirect_to: settings_users_path }
      follow_redirect!

      expect(response.body).to include('secondary.member@example.com')
      expect(response.body).not_to include('primary.member@example.com')
    end
  end

  describe 'GET /settings/account' do
    it 'shows branding values for the selected account only' do
      # Arrange
      sign_in(user)

      # Initial Assert
      expect(primary_account.branding_settings['display_name']).to eq('Northwind Docs')
      expect(secondary_account.branding_settings['display_name']).to eq('Contoso Docs')

      # Act
      get settings_account_path

      # Assert
      document = Nokogiri::HTML(response.body)

      expect(response).to have_http_status(:ok)
      expect(document.at_css("input[name='branding[display_name]']")&.[]('value')).to eq('Northwind Docs')
      expect(document.at_css("input[name='branding[support_email]']")&.[]('value')).to eq('northwind-support@example.com')

      post select_account_path(secondary_account), params: { redirect_to: settings_account_path }
      follow_redirect!

      document = Nokogiri::HTML(response.body)

      expect(document.at_css("input[name='branding[display_name]']")&.[]('value')).to eq('Contoso Docs')
      expect(document.at_css("input[name='branding[support_email]']")&.[]('value')).to eq('contoso-support@example.com')
    end
  end

  describe 'POST /accounts/:account_id/select' do
    it 'rejects switching into an inaccessible account' do
      # Arrange
      sign_in(user)

      # Initial Assert
      expect(user.reload.account).to eq(primary_account)
      expect(user.can_access_account?(outsider_account)).to be(false)

      # Act / Assert
      expect do
        post select_account_path(outsider_account), params: { redirect_to: templates_path }
      end.to raise_error(ActiveRecord::RecordNotFound)

      expect(user.reload.account).to eq(primary_account)
    end
  end
end
