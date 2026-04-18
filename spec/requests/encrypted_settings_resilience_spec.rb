# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Encrypted settings resilience' do
  let(:account) { create(:account) }
  let(:user) { create(:user, account:) }
  let(:platform_admin) { create(:user, account:, role: User::PLATFORM_ADMIN_ROLE) }
  let(:warning_message) { 'Stored settings could not be read. Re-enter them and save again.' }

  def corrupt_encrypted_value!(record)
    table_name = record.class.connection.quote_table_name(record.class.table_name)
    raw_value = record.class.connection.select_value("SELECT value FROM #{table_name} WHERE id = #{record.id}")
    tampered_value = raw_value.sub(/.$/, raw_value[-1] == 'A' ? 'B' : 'A')
    quoted_value = record.class.connection.quote(tampered_value)

    record.class.connection.execute("UPDATE #{table_name} SET value = #{quoted_value} WHERE id = #{record.id}")
  end

  def stub_undecryptable_account_config(account:, key:, value:)
    broken_config = create(:encrypted_config, account:, key:, value:)

    allow(broken_config).to receive(:value).and_raise(ActiveRecord::Encryption::Errors::Decryption)

    allow(EncryptedConfig).to receive(:find_or_initialize_by).and_wrap_original do |original, *args, **kwargs|
      record = original.call(*args, **kwargs)

      next record unless kwargs[:account] == account && kwargs[:key] == key

      broken_config
    end

    broken_config
  end

  def stub_undecryptable_global_config(key:, value:)
    broken_config = create(:global_encrypted_config, key:, value:)

    allow(broken_config).to receive(:value).and_raise(ActiveRecord::Encryption::Errors::Decryption)

    allow(GlobalEncryptedConfig).to receive(:find_or_initialize_by).and_wrap_original do |original, *args, **kwargs|
      record = original.call(*args, **kwargs)

      next record unless kwargs[:key] == key

      broken_config
    end

    broken_config
  end

  def build_pkcs12_upload
    cert_data = GenerateCertificate.call
    pkcs = GenerateCertificate.load_pkcs(cert_data)
    tempfile = Tempfile.new(['esign-cert', '.p12'])
    tempfile.binmode
    tempfile.write(pkcs.to_der)
    tempfile.rewind

    Rack::Test::UploadedFile.new(tempfile.path, 'application/x-pkcs12')
  end

  describe 'GET /admin/email' do
    it 'renders the SMTP page with a warning when the global config is unreadable' do
      # Arrange
      sign_in(platform_admin)
      stub_undecryptable_global_config(key: GlobalEncryptedConfig::EMAIL_SMTP_KEY, value: { 'host' => 'smtp.example.com' })

      # Initial Assert
      expect(GlobalEncryptedConfig.find_by(key: GlobalEncryptedConfig::EMAIL_SMTP_KEY)).to be_present

      # Act
      get admin_email_index_path

      # Assert
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Email SMTP')
      expect(response.body).to include(warning_message)
      expect(response.body).to include(%(name="global_encrypted_config[value][host]"))
    end

    it 'overwrites an unreadable global SMTP config and clears the warning on the next load' do
      # Arrange
      sign_in(platform_admin)
      encrypted_config = create(:global_encrypted_config, key: GlobalEncryptedConfig::EMAIL_SMTP_KEY, value: { 'host' => 'broken.example.com' })
      corrupt_encrypted_value!(encrypted_config)

      params = {
        global_encrypted_config: {
          value: {
            host: 'smtp.example.com',
            port: '587',
            username: 'ops@example.com',
            password: 'new-password',
            domain: 'example.com',
            authentication: 'plain',
            security: 'tls',
            from_email: 'ops@example.com'
          }
        }
      }

      # Initial Assert
      expect { encrypted_config.reload.value }.to raise_error(ActiveRecord::Encryption::Errors::Decryption)

      # Act
      post admin_email_index_path, params: params
      follow_redirect!

      # Assert
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(warning_message)
      replacement_config = GlobalEncryptedConfig.find_by(key: GlobalEncryptedConfig::EMAIL_SMTP_KEY)
      expect(replacement_config&.value&.dig('host')).to eq('smtp.example.com')
      expect(replacement_config&.value&.dig('from_email')).to eq('ops@example.com')
    end

    it 'saves global SMTP settings when only MAIL_FROM is configured in the environment' do
      # Arrange
      sign_in(platform_admin)
      original_delivery_method = Rails.application.config.action_mailer.delivery_method
      ActionMailer::Base.deliveries.clear
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))
      Rails.application.config.action_mailer.delivery_method = :test
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('SMTP_FROM').and_return(nil)
      allow(ENV).to receive(:[]).with('MAIL_FROM').and_return('ops@example.com')

      params = {
        global_encrypted_config: {
          value: {
            host: 'smtp.example.com',
            port: '587',
            username: 'ops@example.com',
            password: 'new-password',
            domain: 'example.com',
            authentication: 'plain',
            security: 'tls',
            from_email: 'ops@example.com'
          }
        }
      }

      # Initial Assert
      expect(GlobalEncryptedConfig.find_by(key: GlobalEncryptedConfig::EMAIL_SMTP_KEY)).to be_nil

      # Act
      post admin_email_index_path, params: params

      # Assert
      expect(response).to redirect_to(admin_email_index_path)
      expect(flash[:notice]).to eq(I18n.t('changes_have_been_saved'))
      expect(GlobalEncryptedConfig.find_by(key: GlobalEncryptedConfig::EMAIL_SMTP_KEY)&.value&.dig('host')).to eq('smtp.example.com')
      expect(ActionMailer::Base.deliveries.last&.from).to eq(['ops@example.com'])
    ensure
      Rails.application.config.action_mailer.delivery_method = original_delivery_method
    end
  end

  describe 'GET /settings/email' do
    it 'renders the account SMTP page with a warning when the account config is unreadable' do
      # Arrange
      sign_in(user)
      stub_undecryptable_account_config(account:,
                                        key: EncryptedConfig::EMAIL_SMTP_KEY,
                                        value: { 'host' => 'smtp.example.com' })

      # Initial Assert
      expect(EncryptedConfig.find_by(account:, key: EncryptedConfig::EMAIL_SMTP_KEY)).to be_present

      # Act
      get settings_email_index_path

      # Assert
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Email SMTP')
      expect(response.body).to include(warning_message)
      expect(response.body).to include(%(name="encrypted_config[value][host]"))
    end

    it 'overwrites an unreadable account SMTP config and clears the warning on the next load' do
      # Arrange
      sign_in(user)
      encrypted_config = create(:encrypted_config,
                                account:,
                                key: EncryptedConfig::EMAIL_SMTP_KEY,
                                value: { 'host' => 'broken.example.com' })
      corrupt_encrypted_value!(encrypted_config)

      params = {
        encrypted_config: {
          value: {
            host: 'smtp.example.com',
            port: '587',
            username: 'ops@example.com',
            password: 'new-password',
            domain: 'example.com',
            authentication: 'plain',
            security: 'tls',
            from_email: 'ops@example.com'
          }
        }
      }

      # Initial Assert
      expect { encrypted_config.reload.value }.to raise_error(ActiveRecord::Encryption::Errors::Decryption)

      # Act
      post settings_email_index_path, params: params
      follow_redirect!

      # Assert
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(warning_message)
      replacement_config = EncryptedConfig.find_by(account:, key: EncryptedConfig::EMAIL_SMTP_KEY)
      expect(replacement_config&.value&.dig('host')).to eq('smtp.example.com')
      expect(replacement_config&.value&.dig('from_email')).to eq('ops@example.com')
    end
  end

  describe 'GET /admin/application_settings' do
    it 'renders the application settings page with a warning when the global config is unreadable' do
      # Arrange
      sign_in(platform_admin)
      encrypted_config = create(:global_encrypted_config,
                                key: GlobalEncryptedConfig::APP_URL_KEY,
                                value: 'https://broken.example.com')
      corrupt_encrypted_value!(encrypted_config)

      # Initial Assert
      expect { encrypted_config.reload.value }.to raise_error(ActiveRecord::Encryption::Errors::Decryption)

      # Act
      get admin_application_settings_path

      # Assert
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Application')
      expect(response.body).to include(warning_message)
      expect(response.body).to include(%(name="global_encrypted_config[value]"))
    end

    it 'overwrites an unreadable application config and clears the warning on the next load' do
      # Arrange
      sign_in(platform_admin)
      encrypted_config = create(:global_encrypted_config,
                                key: GlobalEncryptedConfig::APP_URL_KEY,
                                value: 'https://broken.example.com')
      corrupt_encrypted_value!(encrypted_config)
      params = {
        global_encrypted_config: {
          value: 'https://docuseal.nexportsolutions.com'
        }
      }

      # Initial Assert
      expect { encrypted_config.reload.value }.to raise_error(ActiveRecord::Encryption::Errors::Decryption)

      # Act
      patch admin_application_settings_path, params: params
      follow_redirect!

      # Assert
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(warning_message)
      expect(encrypted_config.class.find_by(key: GlobalEncryptedConfig::APP_URL_KEY)&.value)
        .to eq('https://docuseal.nexportsolutions.com')
    end
  end

  describe 'GET /settings/esign' do
    it 'renders the e-sign settings page with a warning when the cert config is unreadable' do
      # Arrange
      sign_in(user)
      stub_undecryptable_account_config(account:,
                                        key: EncryptedConfig::ESIGN_CERTS_KEY,
                                        value: GenerateCertificate.call.transform_values(&:to_pem).stringify_keys)

      # Initial Assert
      expect(EncryptedConfig.find_by(account:, key: EncryptedConfig::ESIGN_CERTS_KEY)).to be_present

      # Act
      get settings_esign_path

      # Assert
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('PDF Signature')
      expect(response.body).to include(warning_message)
      expect(response.body).to include(EsignSettingsController::DEFAULT_CERT_NAME)
      expect(response.body).to include('Upload signed PDF file to validate its signature')
    end

    it 'uploads a replacement certificate when the previous cert config is unreadable' do
      # Arrange
      sign_in(user)
      encrypted_config = create(:encrypted_config,
                                account:,
                                key: EncryptedConfig::ESIGN_CERTS_KEY,
                                value: GenerateCertificate.call.transform_values(&:to_pem).stringify_keys)
      upload = build_pkcs12_upload
      corrupt_encrypted_value!(encrypted_config)

      params = {
        esign_settings_controller_cert_form_record: {
          name: 'Recovered Cert',
          file: upload,
          password: ''
        }
      }

      # Initial Assert
      expect { encrypted_config.reload.value }.to raise_error(ActiveRecord::Encryption::Errors::Decryption)

      # Act
      post settings_esign_path, params: params
      follow_redirect!

      # Assert
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(warning_message)
      replacement_config = EncryptedConfig.find_by(account:, key: EncryptedConfig::ESIGN_CERTS_KEY)
      expect(replacement_config&.value&.fetch('custom', [])&.map { |entry| entry['name'] }).to include('Recovered Cert')
    end
  end
end
