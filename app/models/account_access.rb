# frozen_string_literal: true

# == Schema Information
#
# Table name: account_accesses
#
#  id         :bigint           not null, primary key
#  role       :string           default("contributor"), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#  user_id    :bigint           not null
#
# Indexes
#
#  index_account_accesses_on_account_id_and_user_id  (account_id,user_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class AccountAccess < ApplicationRecord
  ROLES = [
    VIEWER_ROLE = 'viewer',
    CONTRIBUTOR_ROLE = 'contributor',
    ACCOUNT_ADMIN_ROLE = 'account_admin'
  ].freeze

  belongs_to :account
  belongs_to :user

  attribute :role, :string, default: CONTRIBUTOR_ROLE

  validates :role, inclusion: { in: ROLES }
  validates :account_id, uniqueness: { scope: :user_id }

  after_commit :sync_user_membership_state
  after_destroy_commit :sync_user_membership_state

  scope :account_admins, -> { where(role: ACCOUNT_ADMIN_ROLE) }

  def viewer?
    role == VIEWER_ROLE
  end

  def contributor?
    role.in?([CONTRIBUTOR_ROLE, ACCOUNT_ADMIN_ROLE])
  end

  def account_admin?
    role == ACCOUNT_ADMIN_ROLE
  end

  private

  def sync_user_membership_state
    user.sync_membership_state!
  end
end
