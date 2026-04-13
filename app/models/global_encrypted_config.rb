# frozen_string_literal: true

# == Schema Information
#
# Table name: global_encrypted_configs
#
#  id         :bigint           not null, primary key
#  key        :string           not null
#  value      :text             not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_global_encrypted_configs_on_key  (key) UNIQUE
#
class GlobalEncryptedConfig < ApplicationRecord
  CONFIG_KEYS = [
    FILES_STORAGE_KEY = EncryptedConfig::FILES_STORAGE_KEY,
    EMAIL_SMTP_KEY = EncryptedConfig::EMAIL_SMTP_KEY,
    ESIGN_CERTS_KEY = EncryptedConfig::ESIGN_CERTS_KEY,
    TIMESTAMP_SERVER_URL_KEY = EncryptedConfig::TIMESTAMP_SERVER_URL_KEY,
    APP_URL_KEY = EncryptedConfig::APP_URL_KEY
  ].freeze

  encrypts :value

  serialize :value, coder: JSON
end
