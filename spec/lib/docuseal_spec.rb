# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Docuseal do
  describe '.default_url_options' do
    after do
      described_class.refresh_default_url_options!
    end

    it 'falls back without raising when the persisted application URL is unreadable' do
      # Arrange
      encrypted_config = instance_double(GlobalEncryptedConfig)
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('APP_URL').and_return(nil)
      allow(GlobalEncryptedConfig).to receive(:find_by)
        .with(key: GlobalEncryptedConfig::APP_URL_KEY)
        .and_return(encrypted_config)
      allow(encrypted_config).to receive(:value)
        .and_raise(ActiveRecord::Encryption::Errors::Decryption)
      stub_const('Docuseal::DEFAULT_APP_URL', 'https://fallback.example.com')

      # Initial Assert
      expect { encrypted_config.value }.to raise_error(ActiveRecord::Encryption::Errors::Decryption)

      # Act
      result = described_class.default_url_options

      # Assert
      expect(result).to eq(host: 'fallback.example.com', port: nil, protocol: 'https')
    end
  end
end
