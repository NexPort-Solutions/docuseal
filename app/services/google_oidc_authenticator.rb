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

    account = resolve_account(email)
    return Result.new(error: I18n.t('unable_to_match_google_account_to_a_division')) unless account

    user = User.find_by(email:)

    unless user
      return Result.new(error: I18n.t('google_account_is_not_allowed_for_this_division')) unless account.google_oidc_auto_provision?

      user = account.users.new(
        email:,
        first_name: @auth.dig('info', 'first_name').presence || @auth.dig('info', 'name').to_s.split.first,
        last_name: @auth.dig('info', 'last_name').presence || @auth.dig('info', 'name').to_s.split.drop(1).join(' '),
        password: SecureRandom.hex,
        role: User::ADMIN_ROLE
      )
    end

    return Result.new(error: I18n.t('google_account_is_not_allowed_for_this_division')) unless account_user_allowed?(account, email, user)

    user.provider = @auth['provider']
    user.uid = @auth['uid']
    user.archived_at = nil
    user.save!
    membership = user.account_accesses.find_or_initialize_by(account:)
    membership.role = AccountAccess::ACCOUNT_ADMIN_ROLE if membership.new_record? || membership.role.blank?
    membership.save!
    user.sync_membership_state!

    Result.new(user:)
  end

  private

  def resolve_account(email)
    if @hinted_account_id.present?
      account = Account.find_by(id: @hinted_account_id)
      return account if account&.google_oidc_enabled? && account_matches?(account, email)

      return nil
    end

    matching_accounts = Account.active.select(&:google_oidc_enabled?).select { |account| account_matches?(account, email) }

    matching_accounts.one? ? matching_accounts.first : nil
  end

  def account_matches?(account, email)
    return true if account.google_oidc_allowed_admin_emails.include?(email)

    domain = email.split('@', 2).last
    account.google_oidc_hosted_domains.include?(domain)
  end

  def account_user_allowed?(account, email, user)
    return true if user.platform_admin?

    user.can_access_account?(account) || account_matches?(account, email)
  end
end
