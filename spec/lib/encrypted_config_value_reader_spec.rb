# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EncryptedConfigValueReader do
  describe '.fetch' do
    it 'returns a readable value without marking it unreadable' do
      # Arrange
      record = instance_double(GlobalEncryptedConfig, value: { 'host' => 'smtp.example.com' })

      # Act
      result = described_class.fetch(record, source: 'global current', key: GlobalEncryptedConfig::EMAIL_SMTP_KEY)

      # Assert
      expect(result.value).to eq({ 'host' => 'smtp.example.com' })
      expect(result.unreadable).to be(false)
    end

    it 'returns an unreadable result for supported decryption failures' do
      # Arrange
      handled_errors = [
        ActiveRecord::Encryption::Errors::Decryption.new,
        OpenSSL::Cipher::CipherError.new('cipher failure'),
        OpenSSL::Cipher::AuthTagError.new('tag failure'),
        ActiveSupport::MessageEncryptor::InvalidMessage.new('invalid message'),
        JSON::ParserError.new('unexpected token')
      ]

      # Initial Assert
      expect(handled_errors.size).to eq(5)

      # Act / Assert
      handled_errors.each do |error|
        record = instance_double(EncryptedConfig)
        allow(record).to receive(:value).and_raise(error)

        result = described_class.fetch(record, source: 'account 1', key: EncryptedConfig::EMAIL_SMTP_KEY)

        expect(result.value).to be_nil
        expect(result.unreadable).to be(true)
      end
    end
  end
end
