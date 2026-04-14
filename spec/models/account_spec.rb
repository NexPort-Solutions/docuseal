# frozen_string_literal: true

# == Schema Information
#
# Table name: accounts
#
#  id          :bigint           not null, primary key
#  archived_at :datetime
#  locale      :string           not null
#  name        :string           not null
#  timezone    :string           not null
#  uuid        :string           not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
# Indexes
#
#  index_accounts_on_uuid  (uuid) UNIQUE
#
RSpec.describe Account do
  describe 'branding helpers' do
    it 'falls back to global defaults when branding settings are missing' do
      # Arrange
      account = create(:account, name: 'Northwind')

      # Initial Assert
      expect(account.account_configs.find_by(key: AccountConfig::BRANDING_SETTINGS_KEY)).to be_nil

      # Act
      branded_name = account.branded_name
      support_email = account.support_email
      sender_name = account.sender_name
      default_reply_to = account.default_reply_to
      primary_color = account.primary_color
      secondary_color = account.secondary_color

      # Assert
      expect(branded_name).to eq('Northwind')
      expect(support_email).to eq(Docuseal::SUPPORT_EMAIL)
      expect(sender_name).to eq('Northwind')
      expect(default_reply_to).to be_nil
      expect(primary_color).to eq(Docuseal::DEFAULT_PRIMARY_COLOR)
      expect(secondary_color).to eq(Docuseal::DEFAULT_SECONDARY_COLOR)
    end

    it 'uses division branding values when they are configured' do
      # Arrange
      account = create(:account, name: 'Northwind')
      create(:account_config,
             account:,
             key: AccountConfig::BRANDING_SETTINGS_KEY,
             value: {
               'display_name' => 'Northwind Health',
               'support_email' => 'support@northwind.example',
               'sender_name' => 'Northwind Notifications',
               'default_reply_to' => 'reply@northwind.example',
               'primary_color' => '#112233',
               'secondary_color' => '#ddeeff'
             })

      # Initial Assert
      expect(account.branding_settings).to include('display_name' => 'Northwind Health')

      # Act / Assert
      expect(account.branded_name).to eq('Northwind Health')
      expect(account.support_email).to eq('support@northwind.example')
      expect(account.sender_name).to eq('Northwind Notifications')
      expect(account.default_reply_to).to eq('reply@northwind.example')
      expect(account.primary_color).to eq('#112233')
      expect(account.secondary_color).to eq('#ddeeff')
    end
  end

  describe 'google oidc settings' do
    it 'normalizes hosted domains and explicit role allowlists' do
      # Arrange
      account = create(:account)
      create(:account_config,
             account:,
             key: AccountConfig::GOOGLE_OIDC_SETTINGS_KEY,
             value: {
               'enabled' => true,
               'hosted_domains' => 'Example.com; example.org  EXAMPLE.NET',
               'allowed_viewer_emails' => 'Viewer@Example.com, auditor@example.org',
               'allowed_contributor_emails' => 'Editor@Example.com;writer@example.org',
               'allowed_admin_emails' => 'Admin@Example.com, owner@example.org;ADMIN@example.com',
             })

      # Initial Assert
      expect(account.google_oidc_enabled?).to be(true)

      # Act / Assert
      expect(account.google_oidc_hosted_domains).to contain_exactly('example.com', 'example.org', 'example.net')
      expect(account.google_oidc_allowed_viewer_emails).to contain_exactly('viewer@example.com', 'auditor@example.org')
      expect(account.google_oidc_allowed_contributor_emails).to contain_exactly('editor@example.com', 'writer@example.org')
      expect(account.google_oidc_allowed_admin_emails).to contain_exactly('admin@example.com', 'owner@example.org')
      expect(account.google_oidc_role_for('admin@example.com')).to eq(AccountAccess::ACCOUNT_ADMIN_ROLE)
      expect(account.google_oidc_role_for('editor@example.com')).to eq(AccountAccess::CONTRIBUTOR_ROLE)
      expect(account.google_oidc_role_for('viewer@example.com')).to eq(AccountAccess::VIEWER_ROLE)
      expect(account.google_oidc_role_for('member@example.net')).to eq(AccountAccess::VIEWER_ROLE)
    end
  end
end
