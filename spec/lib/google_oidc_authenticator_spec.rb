# frozen_string_literal: true

RSpec.describe GoogleOidcAuthenticator do
  let(:auth) do
    {
      'provider' => 'google_oauth2',
      'uid' => 'google-uid-123',
      'info' => {
        'email' => 'admin@example.com',
        'email_verified' => true,
        'first_name' => 'Ada',
        'last_name' => 'Lovelace',
        'name' => 'Ada Lovelace'
      }
    }
  end

  before do
    allow(User).to receive(:google_oauth_available?).and_return(true)
  end

  it 'links an existing admin when exactly one enabled division matches by hosted domain' do
    # Arrange
    account = create(:account)
    create(:account_config,
           account:,
           key: AccountConfig::GOOGLE_OIDC_SETTINGS_KEY,
           value: { 'enabled' => true, 'hosted_domains' => 'example.com' })
    user = create(:user, account:, email: 'admin@example.com', provider: nil, uid: nil)

    # Initial Assert
    expect(user.provider).to be_nil
    expect(user.uid).to be_nil

    # Act
    result = described_class.call(auth:)

    # Assert
    expect(result).to be_success
    expect(result.user).to eq(user)
    expect(user.reload.provider).to eq('google_oauth2')
    expect(user.uid).to eq('google-uid-123')
  end

  it 'rejects ambiguous hosted domain matches across divisions' do
    # Arrange
    [create(:account), create(:account)].each do |account|
      create(:account_config,
             account:,
             key: AccountConfig::GOOGLE_OIDC_SETTINGS_KEY,
             value: { 'enabled' => true, 'hosted_domains' => 'example.com' })
    end

    # Initial Assert
    expect(Account.active.count).to be >= 2

    # Act
    result = described_class.call(auth:)

    # Assert
    expect(result).not_to be_success
    expect(result.error).to eq(I18n.t('unable_to_match_google_account_to_a_division'))
  end

  it 'adds a new viewer membership for an existing user when the google account matches another division by domain' do
    # Arrange
    matching_account = create(:account)
    create(:account_config,
           account: matching_account,
           key: AccountConfig::GOOGLE_OIDC_SETTINGS_KEY,
           value: { 'enabled' => true, 'hosted_domains' => 'example.com' })
    user = create(:user, email: 'admin@example.com', account: create(:account))

    # Initial Assert
    expect(user.can_access_account?(matching_account)).to be(false)

    # Act
    result = described_class.call(auth:)

    # Assert
    expect(result).to be_success
    expect(result.user.reload.account_access_for(matching_account)&.role).to eq(AccountAccess::VIEWER_ROLE)
  end

  it 'auto provisions a new viewer when the hosted domain matches' do
    # Arrange
    account = create(:account)
    create(:account_config,
           account:,
           key: AccountConfig::GOOGLE_OIDC_SETTINGS_KEY,
           value: { 'enabled' => true, 'hosted_domains' => 'example.com' })

    # Initial Assert
    expect(User.find_by(email: 'admin@example.com')).to be_nil

    # Act
    result = described_class.call(auth:)

    # Assert
    expect(result).to be_success
    expect(result.user).to be_persisted
    expect(result.user.account).to eq(account)
    expect(result.user.role).to eq(User::ADMIN_ROLE)
    expect(result.user).not_to be_platform_admin
    expect(result.user.account_access_for(account)&.role).to eq(AccountAccess::VIEWER_ROLE)
    expect(result.user.first_name).to eq('Ada')
    expect(result.user.last_name).to eq('Lovelace')
  end

  it 'assigns contributor access for explicitly allowed contributor emails outside hosted domains' do
    # Arrange
    account = create(:account)
    create(:account_config,
           account:,
           key: AccountConfig::GOOGLE_OIDC_SETTINGS_KEY,
           value: { 'enabled' => true, 'allowed_contributor_emails' => 'admin@example.com' })

    # Act
    result = described_class.call(auth:)

    # Assert
    expect(result).to be_success
    expect(result.user.account_access_for(account)&.role).to eq(AccountAccess::CONTRIBUTOR_ROLE)
  end

  it 'assigns account admin access only for explicitly allowed admin emails' do
    # Arrange
    account = create(:account)
    create(:account_config,
           account:,
           key: AccountConfig::GOOGLE_OIDC_SETTINGS_KEY,
           value: { 'enabled' => true, 'allowed_admin_emails' => 'admin@example.com' })

    # Act
    result = described_class.call(auth:)

    # Assert
    expect(result).to be_success
    expect(result.user.account_access_for(account)&.role).to eq(AccountAccess::ACCOUNT_ADMIN_ROLE)
    expect(result.user).not_to be_platform_admin
  end

  it 'does not downgrade an existing membership role on later Google logins' do
    # Arrange
    account = create(:account)
    create(:account_config,
           account:,
           key: AccountConfig::GOOGLE_OIDC_SETTINGS_KEY,
           value: { 'enabled' => true, 'hosted_domains' => 'example.com' })
    user = create(:user, email: 'admin@example.com', account:)
    user.account_access_for(account).update!(role: AccountAccess::ACCOUNT_ADMIN_ROLE)

    # Act
    result = described_class.call(auth:)

    # Assert
    expect(result).to be_success
    expect(user.reload.account_access_for(account)&.role).to eq(AccountAccess::ACCOUNT_ADMIN_ROLE)
  end

  it 'rejects unverified google emails' do
    # Arrange
    unverified_auth = auth.deep_dup
    unverified_auth['info']['email_verified'] = false

    # Initial Assert
    expect(unverified_auth.dig('info', 'email_verified')).to be(false)

    # Act
    result = described_class.call(auth: unverified_auth)

    # Assert
    expect(result).not_to be_success
    expect(result.error).to eq(I18n.t('google_email_must_be_verified'))
  end
end
