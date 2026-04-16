# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Encrypted settings resilience' do
  let(:account) { create(:account) }
  let(:user) { create(:user, account:) }
  let(:platform_admin) { create(:user, account:, role: User::PLATFORM_ADMIN_ROLE) }
  let(:warning_message) { 'Stored settings could not be read. Re-enter them and save again.' }

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
      unreadable_result = EncryptedConfigValueReader::Result.new(value: nil, unreadable: true)
      fetch_calls = 0

      allow(EncryptedConfigValueReader).to receive(:fetch).and_wrap_original do |original, record, source:, key:|
        if record == encrypted_config && key == GlobalEncryptedConfig::EMAIL_SMTP_KEY && (fetch_calls += 1) == 1
          unreadable_result
        else
          original.call(record, source:, key:)
        end
      end

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
      expect(encrypted_config.value['host']).to eq('broken.example.com')

      # Act
      post admin_email_index_path, params: params
      follow_redirect!

      # Assert
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(warning_message)
      expect(encrypted_config.reload.value['host']).to eq('smtp.example.com')
      expect(encrypted_config.value['from_email']).to eq('ops@example.com')
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
      unreadable_result = EncryptedConfigValueReader::Result.new(value: nil, unreadable: true)
      fetch_calls = 0

      allow(EncryptedConfigValueReader).to receive(:fetch).and_wrap_original do |original, record, source:, key:|
        if record == encrypted_config && key == EncryptedConfig::EMAIL_SMTP_KEY && (fetch_calls += 1) == 1
          unreadable_result
        else
          original.call(record, source:, key:)
        end
      end

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
      expect(encrypted_config.value['host']).to eq('broken.example.com')

      # Act
      post settings_email_index_path, params: params
      follow_redirect!

      # Assert
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(warning_message)
      expect(encrypted_config.reload.value['host']).to eq('smtp.example.com')
      expect(encrypted_config.value['from_email']).to eq('ops@example.com')
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
      unreadable_result = EncryptedConfigValueReader::Result.new(value: nil, unreadable: true)
      fetch_calls = 0
      upload = build_pkcs12_upload

      allow(EncryptedConfigValueReader).to receive(:fetch).and_wrap_original do |original, record, source:, key:|
        if record == encrypted_config && key == EncryptedConfig::ESIGN_CERTS_KEY && (fetch_calls += 1) == 1
          unreadable_result
        else
          original.call(record, source:, key:)
        end
      end

      params = {
        esign_settings_controller_cert_form_record: {
          name: 'Recovered Cert',
          file: upload,
          password: ''
        }
      }

      # Initial Assert
      expect(encrypted_config.value['cert']).to be_present

      # Act
      post settings_esign_path, params: params
      follow_redirect!

      # Assert
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(warning_message)
      expect(encrypted_config.reload.value['custom'].map { |entry| entry['name'] }).to include('Recovered Cert')
    end
  end
end
