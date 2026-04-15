# frozen_string_literal: true

# == Schema Information
#
# Table name: users
#
#  id                     :bigint           not null, primary key
#  archived_at            :datetime
#  confirmation_sent_at   :datetime
#  confirmation_token     :string
#  confirmed_at           :datetime
#  consumed_timestep      :integer
#  current_sign_in_at     :datetime
#  current_sign_in_ip     :string
#  email                  :string           not null
#  encrypted_password     :string           not null
#  failed_attempts        :integer          default(0), not null
#  first_name             :string
#  last_name              :string
#  last_sign_in_at        :datetime
#  last_sign_in_ip        :string
#  locked_at              :datetime
#  otp_required_for_login :boolean          default(FALSE), not null
#  otp_secret             :string
#  provider               :string
#  remember_created_at    :datetime
#  reset_password_sent_at :datetime
#  reset_password_token   :string
#  role                   :string           not null
#  sign_in_count          :integer          default(0), not null
#  uid                    :string
#  unconfirmed_email      :string
#  unlock_token           :string
#  uuid                   :string           not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  account_id             :bigint           not null
#
# Indexes
#
#  index_users_on_account_id            (account_id)
#  index_users_on_email                 (email) UNIQUE
#  index_users_on_provider_and_uid      (provider,uid) UNIQUE
#  index_users_on_reset_password_token  (reset_password_token) UNIQUE
#  index_users_on_unlock_token          (unlock_token) UNIQUE
#  index_users_on_uuid                  (uuid) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class User < ApplicationRecord
  ROLES = [
    ADMIN_ROLE = 'admin',
    PLATFORM_ADMIN_ROLE = 'platform_admin'
  ].freeze

  EMAIL_REGEXP = /[^@;,<>\s]+@[^@;,<>\s]+/

  FULL_EMAIL_REGEXP =
    /\A[a-z0-9][.']?(?:(?:[a-z0-9_-]+[.+'])*[a-z0-9_-]+)*@(?:[a-z0-9]+[.-])*[a-z0-9]+\.[a-z]{2,}\z/i

  has_one_attached :signature
  has_one_attached :initials

  belongs_to :account
  has_many :account_accesses, dependent: :destroy
  has_many :membership_accounts, through: :account_accesses, source: :account
  has_one :access_token, dependent: :destroy
  has_many :access_tokens, dependent: :destroy
  has_many :mcp_tokens, dependent: :destroy
  has_many :templates, dependent: :destroy, foreign_key: :author_id, inverse_of: :author
  has_many :template_folders, dependent: :destroy, foreign_key: :author_id, inverse_of: :author
  has_many :user_configs, dependent: :destroy
  has_many :encrypted_configs, dependent: :destroy, class_name: 'EncryptedUserConfig'
  has_many :email_messages, dependent: :destroy, foreign_key: :author_id, inverse_of: :author

  devise :two_factor_authenticatable, :recoverable, :rememberable, :validatable, :trackable, :lockable,
         :omniauthable, omniauth_providers: [:google_oauth2]

  attribute :role, :string, default: ADMIN_ROLE
  attribute :membership_role, :string, default: AccountAccess::CONTRIBUTOR_ROLE
  attribute :uuid, :string, default: -> { SecureRandom.uuid }

  scope :active, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }
  scope :admins, -> { where(role: ADMIN_ROLE) }

  validates :email, format: { with: /\A[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\z/ }

  after_commit :ensure_primary_account_access!, on: :create
  after_commit :sync_membership_state!, on: %i[create update]

  def access_token
    super || build_access_token.tap(&:save!)
  end

  def active_for_authentication?
    super && !archived_at? && active_accessible_accounts.exists?
  end

  def remember_me
    true
  end

  def sidekiq?
    return true if Rails.env.development?

    role.in?([ADMIN_ROLE, PLATFORM_ADMIN_ROLE])
  end

  def platform_admin?
    role == PLATFORM_ADMIN_ROLE
  end

  def admin?
    role.in?([ADMIN_ROLE, PLATFORM_ADMIN_ROLE])
  end

  def accessible_accounts
    if platform_admin?
      Account.active.order(:name)
    else
      Account.active.where(id: account_accesses.select(:account_id)).order(:name)
    end
  end

  def active_accessible_accounts
    accessible_accounts
  end

  def active_account_accesses
    account_accesses
      .select { |membership| membership.account.present? && !membership.account.archived_at? }
      .sort_by { |membership| membership.account.branded_name.downcase }
  end

  def active_membership_count
    active_account_accesses.count
  end

  def google_profile_linked?
    provider == 'google_oauth2' && uid.present?
  end

  def force_sso_membership_accounts
    active_account_accesses.filter_map do |membership|
      membership.account if membership.account&.force_sso_auth?
    end
  end

  def accessible_account_ids
    if platform_admin?
      Account.active.select(:id)
    else
      account_accesses.select(:account_id)
    end
  end

  def admin_managed_accounts
    if platform_admin?
      accessible_accounts
    else
      Account.active.where(id: account_accesses.account_admins.select(:account_id)).order(:name)
    end
  end

  def account_access_for(account)
    return if account.blank? || platform_admin?

    account_accesses.find_by(account_id: account.id)
  end

  def membership_role_for(account)
    return AccountAccess::ACCOUNT_ADMIN_ROLE if platform_admin?

    account_access_for(account)&.role
  end

  def can_access_account?(account)
    return false if account.blank?
    return true if platform_admin?

    account_access_for(account).present?
  end

  def contributor_for?(account)
    return false if account.blank?
    return true if platform_admin?

    account_access_for(account)&.contributor?
  end

  def account_admin_for?(account)
    return false if account.blank?
    return true if platform_admin?

    account_access_for(account)&.account_admin?
  end

  def sync_membership_state!
    return if destroyed?

    membership_account = preferred_membership_account

    if membership_account
      updates = {}
      updates[:account_id] = membership_account.id if account_id != membership_account.id
      update_columns(updates) if updates.present?
    elsif !platform_admin? && archived_at.blank?
      update_columns(archived_at: Time.current)
    end
  end

  def self.google_oauth_available?
    ENV['GOOGLE_OAUTH_CLIENT_ID'].present? && ENV['GOOGLE_OAUTH_CLIENT_SECRET'].present?
  end

  def self.sign_in_after_reset_password
    if PasswordsController::Current.user.present?
      !PasswordsController::Current.user.otp_required_for_login
    else
      true
    end
  end

  def initials
    [first_name&.first, last_name&.first].compact_blank.join.upcase
  end

  def full_name
    [first_name, last_name].compact_blank.join(' ')
  end

  def friendly_name
    if full_name.present?
      %("#{full_name.delete('"')}" <#{email}>)
    else
      email
    end
  end

  private

  def ensure_primary_account_access!
    return if account_id.blank? || account_accesses.exists?(account_id:)

    account_accesses.create!(account_id:, role: AccountAccess::ACCOUNT_ADMIN_ROLE)
  end

  def preferred_membership_account
    if account_id.present?
      account = accessible_accounts.find_by(id: account_id)
      return account if account
    end

    accessible_accounts.first
  end
end
