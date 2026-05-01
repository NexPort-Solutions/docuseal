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

  it 'provisions memberships for multiple matching hosted-domain divisions' do
    # Arrange
    accounts = [create(:account), create(:account)]
    accounts.each do |account|
      create(:account_config,
             account:,
             key: AccountConfig::GOOGLE_OIDC_SETTINGS_KEY,
             value: { 'enabled' => true, 'hosted_domains' => 'example.com' })
    end

    # Initial Assert
    expect(Account.active.count).to be >= 2
    expect(User.find_by(email: 'admin@example.com')).to be_nil

    # Act
    result = described_class.call(auth:)

    # Assert
    expect(result).to be_success
    expect(result.user.account_accesses.where(account: accounts).pluck(:role)).to contain_exactly(
      AccountAccess::VIEWER_ROLE,
      AccountAccess::VIEWER_ROLE
    )
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

  it 'provisions a new user into every matching division with the configured SSO roles' do
    # Arrange
    viewer_account = create(:account)
    contributor_account = create(:account)
    admin_account = create(:account)
    create(:account_config,
           account: viewer_account,
           key: AccountConfig::GOOGLE_OIDC_SETTINGS_KEY,
           value: { 'enabled' => true, 'hosted_domains' => 'example.com' })
    create(:account_config,
           account: contributor_account,
           key: AccountConfig::GOOGLE_OIDC_SETTINGS_KEY,
           value: { 'enabled' => true, 'allowed_contributor_emails' => 'admin@example.com' })
    create(:account_config,
           account: admin_account,
           key: AccountConfig::GOOGLE_OIDC_SETTINGS_KEY,
           value: { 'enabled' => true, 'allowed_admin_emails' => 'admin@example.com' })

    # Initial Assert
    expect(User.find_by(email: 'admin@example.com')).to be_nil

    # Act
    result = described_class.call(auth:)

    # Assert
    expect(result).to be_success
    expect(result.user.account_access_for(viewer_account)&.role).to eq(AccountAccess::VIEWER_ROLE)
    expect(result.user.account_access_for(contributor_account)&.role).to eq(AccountAccess::CONTRIBUTOR_ROLE)
    expect(result.user.account_access_for(admin_account)&.role).to eq(AccountAccess::ACCOUNT_ADMIN_ROLE)
    expect(result.user).not_to be_platform_admin
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

  it 'preserves existing roles and provisions missing memberships for an existing multi-division user' do
    # Arrange
    admin_account = create(:account)
    contributor_account = create(:account)
    create(:account_config,
           account: admin_account,
           key: AccountConfig::GOOGLE_OIDC_SETTINGS_KEY,
           value: { 'enabled' => true, 'hosted_domains' => 'example.com' })
    create(:account_config,
           account: contributor_account,
           key: AccountConfig::GOOGLE_OIDC_SETTINGS_KEY,
           value: { 'enabled' => true, 'allowed_contributor_emails' => 'admin@example.com' })
    user = create(:user, email: 'admin@example.com', account: admin_account)
    user.account_access_for(admin_account).update!(role: AccountAccess::ACCOUNT_ADMIN_ROLE)

    # Initial Assert
    expect(user.account_access_for(admin_account)&.role).to eq(AccountAccess::ACCOUNT_ADMIN_ROLE)
    expect(user.can_access_account?(contributor_account)).to be(false)

    # Act
    result = described_class.call(auth:)

    # Assert
    expect(result).to be_success
    expect(user.reload.account_access_for(admin_account)&.role).to eq(AccountAccess::ACCOUNT_ADMIN_ROLE)
    expect(user.account_access_for(contributor_account)&.role).to eq(AccountAccess::CONTRIBUTOR_ROLE)
  end

  it 'uses a matching hinted division as the primary account while provisioning all matching divisions' do
    # Arrange
    primary_account = create(:account)
    hinted_account = create(:account)
    [primary_account, hinted_account].each do |account|
      create(:account_config,
             account:,
             key: AccountConfig::GOOGLE_OIDC_SETTINGS_KEY,
             value: { 'enabled' => true, 'hosted_domains' => 'example.com' })
    end

    # Initial Assert
    expect(User.find_by(email: 'admin@example.com')).to be_nil

    # Act
    result = described_class.call(auth:, hinted_account_id: hinted_account.id)

    # Assert
    expect(result).to be_success
    expect(result.user.account).to eq(hinted_account)
    expect(result.user.account_accesses.where(account: [primary_account, hinted_account]).count).to eq(2)
  end

  it 'rejects a hinted division that does not match the Google account' do
    # Arrange
    matching_account = create(:account)
    hinted_account = create(:account)
    create(:account_config,
           account: matching_account,
           key: AccountConfig::GOOGLE_OIDC_SETTINGS_KEY,
           value: { 'enabled' => true, 'hosted_domains' => 'example.com' })
    create(:account_config,
           account: hinted_account,
           key: AccountConfig::GOOGLE_OIDC_SETTINGS_KEY,
           value: { 'enabled' => true, 'hosted_domains' => 'other.example' })

    # Initial Assert
    expect(matching_account.google_oidc_match?('admin@example.com')).to be(true)
    expect(hinted_account.google_oidc_match?('admin@example.com')).to be(false)

    # Act
    result = described_class.call(auth:, hinted_account_id: hinted_account.id)

    # Assert
    expect(result).not_to be_success
    expect(result.error).to eq(I18n.t('unable_to_match_google_account_to_a_division'))
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
