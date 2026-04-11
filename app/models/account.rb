# frozen_string_literal: true

# == Schema Information
#
# Table name: accounts
#
#  id          :bigint           not null, primary key
#  archived_at :datetime
#  locale      :string           not null
#  name        :string           not null
#  timezone    :string           not null
#  uuid        :string           not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#
# Indexes
#
#  index_accounts_on_uuid  (uuid) UNIQUE
#
class Account < ApplicationRecord
  attribute :uuid, :string, default: -> { SecureRandom.uuid }

  has_one_attached :logo

  has_many :users, dependent: :destroy
  has_many :account_accesses, dependent: :destroy
  has_many :members, through: :account_accesses, source: :user
  has_many :encrypted_configs, dependent: :destroy
  has_many :account_configs, dependent: :destroy
  has_many :email_messages, dependent: :destroy
  has_many :templates, dependent: :destroy
  has_many :template_folders, dependent: :destroy
  has_one :default_template_folder, -> { where(name: TemplateFolder::DEFAULT_NAME) },
          class_name: 'TemplateFolder', dependent: :destroy, inverse_of: :account
  has_many :submissions, dependent: :destroy
  has_many :submitters, dependent: :destroy
  has_many :account_linked_accounts, dependent: :destroy
  has_many :email_events, dependent: :destroy
  has_many :webhook_urls, dependent: :destroy
  has_many :webhook_events, dependent: nil
  has_many :account_testing_accounts, -> { testing }, dependent: :destroy,
                                                      class_name: 'AccountLinkedAccount',
                                                      inverse_of: :account
  has_one :linked_account_account, dependent: :destroy,
                                   foreign_key: :linked_account_id,
                                   class_name: 'AccountLinkedAccount',
                                   inverse_of: :linked_account
  has_many :linked_account_accounts, dependent: :destroy,
                                     foreign_key: :linked_account_id,
                                     class_name: 'AccountLinkedAccount',
                                     inverse_of: :linked_account
  has_many :linked_accounts, through: :account_linked_accounts
  has_many :testing_accounts, through: :account_testing_accounts, source: :linked_account
  has_many :active_users, -> { active }, dependent: :destroy,
                                         inverse_of: :account, class_name: 'User'

  attribute :timezone, :string, default: 'UTC'
  attribute :locale, :string, default: 'en-US'

  scope :active, -> { where(archived_at: nil) }

  def branding_settings
    account_configs.find_or_initialize_by(key: AccountConfig::BRANDING_SETTINGS_KEY).value.to_h
  end

  def branded_name
    branding_settings['display_name'].presence || name.presence || Docuseal.product_name
  end

  def support_email
    branding_settings['support_email'].presence || Docuseal::SUPPORT_EMAIL
  end

  def sender_name
    branding_settings['sender_name'].presence || branded_name
  end

  def default_reply_to
    branding_settings['default_reply_to'].presence
  end

  def primary_color
    branding_settings['primary_color'].presence || Docuseal::DEFAULT_PRIMARY_COLOR
  end

  def secondary_color
    branding_settings['secondary_color'].presence || Docuseal::DEFAULT_SECONDARY_COLOR
  end

  def google_oidc_settings
    account_configs.find_or_initialize_by(key: AccountConfig::GOOGLE_OIDC_SETTINGS_KEY).value.to_h
  end

  def google_oidc_enabled?
    google_oidc_settings['enabled'] == true
  end

  def force_sso_auth?
    account_configs.find_or_initialize_by(key: AccountConfig::FORCE_SSO_AUTH_KEY).value == true
  end

  def google_oidc_hosted_domains
    Array(google_oidc_settings['hosted_domains']).flat_map { |value| value.to_s.split(/[\s,;]+/) }
                                                 .map(&:downcase)
                                                 .reject(&:blank?)
                                                 .uniq
  end

  def google_oidc_allowed_admin_emails
    Array(google_oidc_settings['allowed_admin_emails']).flat_map { |value| value.to_s.split(/[\s,;]+/) }
                                                       .map(&:downcase)
                                                       .reject(&:blank?)
                                                       .uniq
  end

  def google_oidc_auto_provision?
    google_oidc_settings['auto_provision'] == true
  end

  def testing?
    linked_account_account&.testing?
  end

  def tz_info
    @tz_info ||= TZInfo::Timezone.get(ActiveSupport::TimeZone::MAPPING[timezone] || timezone)
  end

  def default_template_folder
    super || build_default_template_folder(name: TemplateFolder::DEFAULT_NAME,
                                           author_id: members.minimum(:id) || users.minimum(:id)).tap(&:save!)
  end
end
