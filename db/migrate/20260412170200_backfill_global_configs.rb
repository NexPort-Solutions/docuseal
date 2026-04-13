# frozen_string_literal: true

class BackfillGlobalConfigs < ActiveRecord::Migration[8.0]
  def up
    if table_exists?(:account_configs)
      account_config = AccountConfig.order(:account_id).find_by(key: AccountConfig::ENABLE_MCP_KEY)

      if account_config
        GlobalConfig.find_or_initialize_by(key: GlobalConfig::ENABLE_MCP_KEY).tap do |config|
          config.value = account_config.value
          config.save!
        end
      end
    end

    return unless table_exists?(:encrypted_configs)

    GlobalEncryptedConfig::CONFIG_KEYS.each do |key|
      encrypted_config = EncryptedConfig.order(:account_id).find_by(key:)
      next unless encrypted_config

      value = read_encrypted_value(encrypted_config)
      next unless value

      GlobalEncryptedConfig.find_or_initialize_by(key:).tap do |config|
        config.value = value
        config.save!
      end
    end
  end

  def down
    GlobalConfig.where(key: GlobalConfig::CONFIG_KEYS).delete_all
    GlobalEncryptedConfig.where(key: GlobalEncryptedConfig::CONFIG_KEYS).delete_all
  end

  private

  def read_encrypted_value(encrypted_config)
    encrypted_config.value
  rescue OpenSSL::Cipher::CipherError,
         OpenSSL::Cipher::AuthTagError,
         ActiveRecord::Encryption::Errors::Decryption,
         ActiveSupport::MessageEncryptor::InvalidMessage,
         JSON::ParserError => e
    say "Skipping encrypted config #{encrypted_config.key} for account #{encrypted_config.account_id}: #{e.class}", true

    nil
  end
end
