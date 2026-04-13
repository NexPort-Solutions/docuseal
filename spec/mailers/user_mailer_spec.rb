# frozen_string_literal: true

RSpec.describe UserMailer do
  describe '.invitation_email' do
    it 'applies division sender name and reply-to branding to invitation emails' do
      # Arrange
      account = create(:account, locale: 'en-US')
      create(:account_config,
             account:,
             key: AccountConfig::BRANDING_SETTINGS_KEY,
             value: {
               'display_name' => 'Northwind Health',
               'sender_name' => 'Northwind Notifications',
               'default_reply_to' => 'reply@northwind.example'
             })
      user = create(:user, account:, email: 'invitee@example.com')

      # Initial Assert
      expect(account.sender_name).to eq('Northwind Notifications')
      expect(account.default_reply_to).to eq('reply@northwind.example')

      # Act
      mail = described_class.invitation_email(user)

      # Assert
      expect(mail.from).to eq([Docuseal::SUPPORT_EMAIL])
      expect(mail[:from].display_names).to eq(['Northwind Notifications'])
      expect(mail.reply_to).to eq(['reply@northwind.example'])
    end

    it 'falls back to the account branded name when no sender name is configured' do
      # Arrange
      account = create(:account, name: 'Northwind')
      create(:account_config,
             account:,
             key: AccountConfig::BRANDING_SETTINGS_KEY,
             value: { 'display_name' => 'Northwind Health' })
      user = create(:user, account:, email: 'invitee@example.com')

      # Initial Assert
      expect(account.sender_name).to eq('Northwind Health')

      # Act
      mail = described_class.invitation_email(user)

      # Assert
      expect(mail.from).to eq([Docuseal::SUPPORT_EMAIL])
      expect(mail[:from].display_names).to eq(['Northwind Health'])
      expect(mail.reply_to).to be_blank
    end
  end

  describe 'Devise password reset mailer' do
    it 'applies division branding and locale to reset password instructions' do
      # Arrange
      account = create(:account, locale: 'de')
      create(:account_config,
             account:,
             key: AccountConfig::BRANDING_SETTINGS_KEY,
             value: {
               'display_name' => 'Nordwind Dokumente',
               'sender_name' => 'Nordwind Benachrichtigungen',
               'support_email' => 'support@nordwind.example',
               'default_reply_to' => 'reply@nordwind.example'
             })
      user = create(:user, account:, first_name: 'Greta', email: 'greta@example.com')

      # Initial Assert
      expect(account.sender_name).to eq('Nordwind Benachrichtigungen')
      expect(account.support_email).to eq('support@nordwind.example')
      expect(account.default_reply_to).to eq('reply@nordwind.example')

      # Act
      mail = Devise::Mailer.reset_password_instructions(user, 'reset-token-123')

      # Assert
      expect(mail.from).to eq(['support@nordwind.example'])
      expect(mail[:from].display_names).to eq(['Nordwind Benachrichtigungen'])
      expect(mail.reply_to).to eq(['reply@nordwind.example'])
      expect(mail.body.encoded).to include(I18n.t('change_my_password', locale: :de))
      expect(mail.body.encoded).to include(I18n.t('hello_name', locale: :de, name: 'Greta'))
    end
  end

  describe 'production SMTP interceptor' do
    it 'keeps the branded sender display name when global SMTP settings are applied' do
      # Arrange
      original_delivery_method = Rails.application.config.action_mailer.delivery_method
      account = create(:account)
      create(:account_config,
             account:,
             key: AccountConfig::BRANDING_SETTINGS_KEY,
             value: {
               'display_name' => 'Northwind Health',
               'sender_name' => 'Northwind Notifications',
               'support_email' => 'support@northwind.example'
             })
      create(:global_encrypted_config,
             key: GlobalEncryptedConfig::EMAIL_SMTP_KEY,
             value: {
               'from_email' => 'smtp@delivery.example',
               'host' => 'smtp.example.com',
               'port' => 587,
               'username' => 'mailer',
               'password' => 'secret'
             })
      user = create(:user, account:, email: 'invitee@example.com')
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))
      allow(Docuseal).to receive(:multitenant?).and_return(false)
      Rails.application.config.action_mailer.delivery_method = nil

      # Initial Assert
      expect(account.sender_name).to eq('Northwind Notifications')

      # Act
      mail = described_class.invitation_email(user)
      ActionMailerConfigsInterceptor.delivering_email(mail)

      # Assert
      expect(mail.from).to eq(['smtp@delivery.example'])
      expect(mail[:from].display_names).to eq(['Northwind Notifications'])
    ensure
      Rails.application.config.action_mailer.delivery_method = original_delivery_method
    end
  end
end
