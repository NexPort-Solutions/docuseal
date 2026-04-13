# frozen_string_literal: true

require Rails.root.join('db/migrate/20260412170200_backfill_global_configs')

RSpec.describe BackfillGlobalConfigs do
  subject(:migration) { described_class.new }

  let!(:account) { create(:account) }

  before do
    GlobalConfig.delete_all
    GlobalEncryptedConfig.delete_all
  end

  it 'skips undecryptable encrypted configs while backfilling readable values' do
    create(:account_config, account:, key: AccountConfig::ENABLE_MCP_KEY, value: true)
    create(:encrypted_config, account:, key: GlobalEncryptedConfig::APP_URL_KEY, value: 'https://docuseal.nexportsolutions.com')
    broken_config = create(:encrypted_config, account:, key: GlobalEncryptedConfig::EMAIL_SMTP_KEY, value: { address: 'smtp.example.com' })

    relation = EncryptedConfig.order(:account_id)

    allow(EncryptedConfig).to receive(:order).with(:account_id).and_return(relation)
    allow(relation).to receive(:find_by).and_wrap_original do |original, **args|
      record = original.call(**args)

      if args[:key] == broken_config.key
        allow(record).to receive(:value).and_raise(OpenSSL::Cipher::AuthTagError)
      end

      record
    end

    expect { migration.up }.not_to raise_error

    expect(GlobalConfig.find_by(key: GlobalConfig::ENABLE_MCP_KEY)&.value).to eq(true)
    expect(GlobalEncryptedConfig.find_by(key: GlobalEncryptedConfig::APP_URL_KEY)&.value).to eq('https://docuseal.nexportsolutions.com')
    expect(GlobalEncryptedConfig.find_by(key: GlobalEncryptedConfig::EMAIL_SMTP_KEY)).to be_nil
  end
end
