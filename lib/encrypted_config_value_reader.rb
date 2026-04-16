# frozen_string_literal: true

module EncryptedConfigValueReader
  Result = Struct.new(:value, :unreadable, keyword_init: true)

  HANDLED_ERRORS = [
    ActiveRecord::Encryption::Errors::Decryption,
    OpenSSL::Cipher::CipherError,
    OpenSSL::Cipher::AuthTagError,
    ActiveSupport::MessageEncryptor::InvalidMessage,
    JSON::ParserError
  ].freeze

  module_function

  def fetch(record, source:, key:)
    return Result.new(value: nil, unreadable: false) if record.blank?

    Result.new(value: record.value, unreadable: false)
  rescue *HANDLED_ERRORS => e
    Rails.logger.warn("Unreadable encrypted config #{source}: #{key}") if defined?(Rails)
    Rollbar.warning(e) if defined?(Rollbar)

    Result.new(value: nil, unreadable: true)
  end
end
