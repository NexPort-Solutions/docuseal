# frozen_string_literal: true

class GoogleOidcAuthenticator
  Result = Struct.new(:user, :error, keyword_init: true) do
    def success?
      error.blank?
    end
  end

  def self.call(...)
    new(...).call
  end

  def initialize(auth:, hinted_account_id: nil)
    @auth = auth
    @hinted_account_id = hinted_account_id
  end

  def call
    return Result.new(error: I18n.t('google_sso_is_not_configured')) unless User.google_oauth_available?

    email = @auth.dig('info', 'email').to_s.downcase
    return Result.new(error: I18n.t('google_workspace_sign_in_failed')) if email.blank?
    return Result.new(error: I18n.t('google_email_must_be_verified')) unless @auth.dig('info', 'email_verified')

    matching_accounts = resolve_matching_accounts(email)
    return Result.new(error: I18n.t('unable_to_match_google_account_to_a_division')) if matching_accounts.blank?

    user, new_user = find_or_build_user(email, matching_accounts)

    ApplicationRecord.transaction do
      persist_google_identity!(user)
      provision_memberships!(user, matching_accounts, new_user:)
      user.sync_membership_state!
    end

    Result.new(user:)
  end

  private

  def find_or_build_user(email, matching_accounts)
    user = User.find_by(email:)
    return [user, false] if user

    primary_account = primary_account_for(nil, matching_accounts)
    user = primary_account.users.new(
      email:,
      first_name: @auth.dig('info', 'first_name').presence || @auth.dig('info', 'name').to_s.split.first,
      last_name: @auth.dig('info', 'last_name').presence || @auth.dig('info', 'name').to_s.split.drop(1).join(' '),
      password: SecureRandom.hex
    )

    [user, true]
  end

  def persist_google_identity!(user)
    user.provider = @auth['provider']
    user.uid = @auth['uid']
    user.archived_at = nil
    user.save!
  end

  def resolve_matching_accounts(email)
    matching_accounts = Account.active
                               .select(&:google_oidc_enabled?)
                               .select { |account| account.google_oidc_match?(email) }

    if @hinted_account_id.present?
      hinted_account = matching_accounts.find { |account| account.id.to_s == @hinted_account_id.to_s }
      return [] unless hinted_account

      return matching_accounts
    end

    matching_accounts
  end

  def primary_account_for(user, matching_accounts)
    hinted_account = matching_accounts.find { |account| account.id.to_s == @hinted_account_id.to_s }
    return hinted_account if hinted_account

    current_account = matching_accounts.find { |account| account.id == user&.account_id }
    current_account || matching_accounts.first
  end

  def provision_memberships!(user, matching_accounts, new_user:)
    matching_accounts.each do |account|
      role = account.google_oidc_role_for(user.email)
      next unless role

      membership = user.account_accesses.find_or_initialize_by(account:)
      membership.role = role if new_user || membership.new_record? || membership.role.blank?
      membership.save!
    end
  end
end
