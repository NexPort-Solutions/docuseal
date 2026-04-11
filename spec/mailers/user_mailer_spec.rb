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
      expect(mail.from).to eq(['info@docuseal.com'])
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
      expect(mail[:from].display_names).to eq(['Northwind Health'])
      expect(mail.reply_to).to be_blank
    end
  end
end
