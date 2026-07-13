# frozen_string_literal: true

module PersistedSecretsGuard
  REQUIRED_KEYS = %w[SECRET_KEY_BASE ENCRYPTION_SECRET].freeze
  KEY_VAULT_REFERENCE_PREFIX = '@Microsoft.KeyVault('.freeze

  module_function

  def validate!(env)
    return unless env['REQUIRE_PERSISTED_SECRETS'] == 'true'

    invalid_keys = REQUIRED_KEYS.select do |key|
      value = env[key].to_s

      value.empty? || value.start_with?(KEY_VAULT_REFERENCE_PREFIX)
    end

    return if invalid_keys.empty?

    raise "Persisted production secrets are missing or unresolved: #{invalid_keys.join(', ')}"
  end
end
