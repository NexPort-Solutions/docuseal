# frozen_string_literal: true

RSpec.describe ContentPermissions::Resolver do
  let(:account) { create(:account) }
  let(:folder_admin) { create(:user, account:, email: 'folder-admin@example.com') }
  let(:viewer_user) { create(:user, account:, email: 'viewer@example.com') }
  let(:contributor_user) { create(:user, account:, email: 'contributor@example.com') }
  let(:author) { create(:user, account:, email: 'author@example.com') }
  let(:root_folder) { create(:template_folder, account:, author:, name: 'Root Folder') }
  let(:child_folder) { create(:template_folder, account:, author:, parent_folder: root_folder, name: 'Child Folder') }
  let(:template) { create(:template, account:, author:, folder: child_folder, name: 'Scoped Template') }
  let(:submission) { create(:submission, template:, account:, created_by_user: author, name: 'Scoped Submission') }

  before do
    viewer_user.account_access_for(account).update!(role: AccountAccess::VIEWER_ROLE)
    contributor_user.account_access_for(account).update!(role: AccountAccess::CONTRIBUTOR_ROLE)
    folder_admin.account_access_for(account).update!(role: AccountAccess::CONTRIBUTOR_ROLE)
  end

  describe '#resolve_template and #resolve_submission' do
    it 'inherits folder permissions for nested templates and submissions' do
      # Arrange
      create(
        :content_access,
        user: folder_admin,
        securable: root_folder,
        template_permission: ContentAccess::VIEWER_PERMISSION,
        submission_permission: ContentAccess::ADMIN_PERMISSION
      )
      resolver = described_class.new(folder_admin, account:)

      # Initial Assert
      expect(template.folder).to eq(child_folder)
      expect(submission.template).to eq(template)

      # Act
      template_result = resolver.resolve_template(template)
      submission_result = resolver.resolve_submission(submission)

      # Assert
      expect(template_result.template_permission).to eq(ContentAccess::VIEWER_PERMISSION)
      expect(template_result.submission_permission).to eq(ContentAccess::ADMIN_PERMISSION)
      expect(submission_result.submission_permission).to eq(ContentAccess::ADMIN_PERMISSION)
      expect(template_result.template_source.record_type).to eq('TemplateFolder')
      expect(template_result.template_source.record_id).to eq(root_folder.id)
    end

    it 'lets an explicit template override beat inherited folder access' do
      # Arrange
      create(
        :content_access,
        user: contributor_user,
        securable: root_folder,
        template_permission: ContentAccess::VIEWER_PERMISSION,
        submission_permission: ContentAccess::VIEWER_PERMISSION
      )
      create(
        :content_access,
        user: contributor_user,
        securable: template,
        template_permission: ContentAccess::EDITOR_PERMISSION,
        submission_permission: ContentAccess::ADMIN_PERMISSION
      )
      resolver = described_class.new(contributor_user, account:)

      # Initial Assert
      expect(template.folder).to eq(child_folder)

      # Act
      result = resolver.resolve_template(template)

      # Assert
      expect(result.template_permission).to eq(ContentAccess::EDITOR_PERMISSION)
      expect(result.submission_permission).to eq(ContentAccess::ADMIN_PERMISSION)
      expect(result.template_source.record_type).to eq('Template')
      expect(result.template_source.record_id).to eq(template.id)
    end

    it 'falls back to the account role when access is inherit through the chain' do
      # Arrange
      create(
        :content_access,
        user: viewer_user,
        securable: root_folder,
        template_permission: ContentAccess::INHERIT_PERMISSION,
        submission_permission: ContentAccess::INHERIT_PERMISSION
      )
      resolver = described_class.new(viewer_user, account:)

      # Initial Assert
      expect(viewer_user.membership_role_for(account)).to eq(AccountAccess::VIEWER_ROLE)

      # Act
      result = resolver.resolve_template(template)

      # Assert
      expect(result.template_permission).to eq(ContentAccess::VIEWER_PERMISSION)
      expect(result.submission_permission).to eq(ContentAccess::VIEWER_PERMISSION)
      expect(result.template_source.kind).to eq(:account_role)
    end

    it 'treats explicit no access on a template as a deny for the template and its submissions' do
      # Arrange
      create(
        :content_access,
        user: contributor_user,
        securable: root_folder,
        template_permission: ContentAccess::ADMIN_PERMISSION,
        submission_permission: ContentAccess::ADMIN_PERMISSION
      )
      create(
        :content_access,
        user: contributor_user,
        securable: template,
        template_permission: ContentAccess::NO_ACCESS_PERMISSION,
        submission_permission: ContentAccess::INHERIT_PERMISSION
      )
      resolver = described_class.new(contributor_user, account:)

      # Initial Assert
      expect(resolver.resolve_folder(root_folder).template_permission).to eq(ContentAccess::ADMIN_PERMISSION)

      # Act
      template_result = resolver.resolve_template(template)
      submission_result = resolver.resolve_submission(submission)

      # Assert
      expect(template_result.template_permission).to eq(ContentAccess::NO_ACCESS_PERMISSION)
      expect(template_result.submission_permission).to eq(ContentAccess::NO_ACCESS_PERMISSION)
      expect(submission_result.submission_permission).to eq(ContentAccess::NO_ACCESS_PERMISSION)
    end
  end

  describe 'role ceilings' do
    it 'keeps account viewers read only even if an item ACL says admin' do
      # Arrange
      create(
        :content_access,
        user: viewer_user,
        securable: template,
        template_permission: ContentAccess::ADMIN_PERMISSION,
        submission_permission: ContentAccess::ADMIN_PERMISSION
      )
      resolver = described_class.new(viewer_user, account:)

      # Initial Assert
      expect(viewer_user.membership_role_for(account)).to eq(AccountAccess::VIEWER_ROLE)

      # Act
      result = resolver.resolve_template(template)

      # Assert
      expect(result.template_permission).to eq(ContentAccess::VIEWER_PERMISSION)
      expect(result.submission_permission).to eq(ContentAccess::VIEWER_PERMISSION)
      expect(resolver.can_edit_template?(template)).to be(false)
      expect(resolver.can_archive_submission?(submission)).to be(false)
    end
  end
end
