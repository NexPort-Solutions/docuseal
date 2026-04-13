# frozen_string_literal: true

FactoryBot.define do
  factory :global_encrypted_config do
    key { GlobalEncryptedConfig::APP_URL_KEY }
    value { 'https://example.invalid' }
  end
end
