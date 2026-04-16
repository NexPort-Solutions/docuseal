# frozen_string_literal: true

# == Schema Information
#
# Table name: content_accesses
#
#  id                    :bigint           not null, primary key
#  securable_type        :string           not null
#  submission_permission :string           default("inherit"), not null
#  template_permission   :string           default("inherit"), not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  securable_id          :bigint           not null
#  user_id               :bigint           not null
#
# Indexes
#
#  index_content_accesses_on_securable           (securable_type,securable_id)
#  index_content_accesses_on_user_and_securable  (user_id,securable_type,securable_id) UNIQUE
#  index_content_accesses_on_user_id             (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class ContentAccess < ApplicationRecord
  TEMPLATE_PERMISSIONS = [
    INHERIT_PERMISSION = 'inherit',
    NO_ACCESS_PERMISSION = 'no_access',
    VIEWER_PERMISSION = 'viewer',
    EDITOR_PERMISSION = 'editor',
    ADMIN_PERMISSION = 'admin'
  ].freeze

  SUBMISSION_PERMISSIONS = [
    INHERIT_PERMISSION,
    NO_ACCESS_PERMISSION,
    VIEWER_PERMISSION,
    ADMIN_PERMISSION
  ].freeze

  belongs_to :user
  belongs_to :securable, polymorphic: true

  validates :securable_type, inclusion: { in: %w[Template TemplateFolder] }
  validates :template_permission, inclusion: { in: TEMPLATE_PERMISSIONS }
  validates :submission_permission, inclusion: { in: SUBMISSION_PERMISSIONS }
  validates :user_id, uniqueness: { scope: %i[securable_type securable_id] }
  validate :user_has_membership_for_securable_account

  scope :for_templates, -> { where(securable_type: 'Template') }
  scope :for_folders, -> { where(securable_type: 'TemplateFolder') }

  def inherited?
    template_permission == INHERIT_PERMISSION && submission_permission == INHERIT_PERMISSION
  end

  private

  def user_has_membership_for_securable_account
    return if user.blank? || securable.blank?
    return if user.platform_admin? || user.can_access_account?(securable.account)

    errors.add(:user_id, :invalid)
  end
end
