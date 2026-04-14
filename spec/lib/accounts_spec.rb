# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Accounts do
  let!(:account) { create(:account) }

  def stub_undecryptable_account_config(account:, key:, value:)
    broken_config = create(:encrypted_config, account:, key:, value:)

    allow(broken_config).to receive(:value).and_raise(ActiveRecord::Encryption::Errors::Decryption)

    allow(EncryptedConfig).to receive(:find_by).and_wrap_original do |original, *args, **kwargs|
      record = original.call(*args, **kwargs)

      next record unless kwargs[:account] == account && kwargs[:key] == key

      broken_config
    end
  end

  describe '.load_signing_pkcs' do
    it 'falls back to global encrypted config when account config is undecryptable' do
      cert_data = GenerateCertificate.call.transform_values(&:to_pem).stringify_keys
      expected_pkcs = GenerateCertificate.load_pkcs(cert_data)

      create(:global_encrypted_config,
             key: GlobalEncryptedConfig::ESIGN_CERTS_KEY,
             value: cert_data)

      stub_undecryptable_account_config(account:,
                                        key: EncryptedConfig::ESIGN_CERTS_KEY,
                                        value: cert_data)

      expect(described_class.load_signing_pkcs(account).certificate.to_der).to eq(expected_pkcs.certificate.to_der)
    end

    it 'falls back to generated cert data when encrypted config sources are unavailable' do
      stub_undecryptable_account_config(account:,
                                        key: EncryptedConfig::ESIGN_CERTS_KEY,
                                        value: GenerateCertificate.call.transform_values(&:to_pem).stringify_keys)

      allow(GlobalEncryptedConfig).to receive(:find_by)
        .with(key: GlobalEncryptedConfig::ESIGN_CERTS_KEY)
        .and_return(nil)

      allow(EncryptedConfig).to receive(:find_by).and_wrap_original do |original, *args, **kwargs|
        next nil if kwargs[:account].nil? && kwargs[:key] == EncryptedConfig::ESIGN_CERTS_KEY

        original.call(*args, **kwargs)
      end

      pkcs = described_class.load_signing_pkcs(account)

      expect(pkcs.certificate).to be_a(OpenSSL::X509::Certificate)
    end
  end

  describe '.load_timeserver_url' do
    it 'falls back to global encrypted config when account config is undecryptable' do
      create(:global_encrypted_config,
             key: GlobalEncryptedConfig::TIMESTAMP_SERVER_URL_KEY,
             value: 'https://tsa.example.com')

      stub_undecryptable_account_config(account:,
                                        key: EncryptedConfig::TIMESTAMP_SERVER_URL_KEY,
                                        value: 'https://legacy.example.com')

      expect(described_class.load_timeserver_url(account)).to eq('https://tsa.example.com')
    end
  end

  describe '.load_trusted_certs' do
    it 'falls back to global encrypted config when account config is undecryptable' do
      cert_data = GenerateCertificate.call.transform_values(&:to_pem).stringify_keys
      expected_pkcs = GenerateCertificate.load_pkcs(cert_data)

      create(:global_encrypted_config,
             key: GlobalEncryptedConfig::ESIGN_CERTS_KEY,
             value: cert_data)

      stub_undecryptable_account_config(account:,
                                        key: EncryptedConfig::ESIGN_CERTS_KEY,
                                        value: cert_data)

      trusted_certs = described_class.load_trusted_certs(account)

      expect(trusted_certs.map(&:to_der)).to include(expected_pkcs.certificate.to_der)
    end
  end
end
