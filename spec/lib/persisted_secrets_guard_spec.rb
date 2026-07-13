# frozen_string_literal: true

require 'persisted_secrets_guard'

RSpec.describe PersistedSecretsGuard do
  describe '.validate!' do
    it 'accepts persisted secrets' do
      # Arrange
      env = {
        'REQUIRE_PERSISTED_SECRETS' => 'true',
        'SECRET_KEY_BASE' => 'stable-secret-key-base',
        'ENCRYPTION_SECRET' => 'stable-encryption-secret'
      }

      # Initial Assert
      expect(env.values_at('SECRET_KEY_BASE', 'ENCRYPTION_SECRET')).to eq(
        %w[stable-secret-key-base stable-encryption-secret]
      )

      # Act
      result = described_class.validate!(env)

      # Assert
      expect(result).to be_nil
    end

    it 'rejects a missing secret without generating a replacement' do
      # Arrange
      env = {
        'REQUIRE_PERSISTED_SECRETS' => 'true',
        'SECRET_KEY_BASE' => 'stable-secret-key-base'
      }

      # Initial Assert
      expect(env).not_to have_key('ENCRYPTION_SECRET')

      # Act
      validate = -> { described_class.validate!(env) }

      # Assert
      expect(&validate).to raise_error(RuntimeError, /ENCRYPTION_SECRET/)
      expect(env).not_to have_key('ENCRYPTION_SECRET')
    end

    it 'rejects an unresolved Key Vault reference' do
      # Arrange
      env = {
        'REQUIRE_PERSISTED_SECRETS' => 'true',
        'SECRET_KEY_BASE' => '@Microsoft.KeyVault(SecretUri=https://example.vault.azure.net/secrets/key/)',
        'ENCRYPTION_SECRET' => 'stable-encryption-secret'
      }

      # Initial Assert
      expect(env.fetch('SECRET_KEY_BASE')).to start_with('@Microsoft.KeyVault(')

      # Act
      validate = -> { described_class.validate!(env) }

      # Assert
      expect(&validate).to raise_error(RuntimeError, /SECRET_KEY_BASE/)
    end

    it 'does not change the default self-hosted startup behavior' do
      # Arrange
      env = {}

      # Initial Assert
      expect(env['REQUIRE_PERSISTED_SECRETS']).to be_nil

      # Act
      result = described_class.validate!(env)

      # Assert
      expect(result).to be_nil
    end
  end
end
