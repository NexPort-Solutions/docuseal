# frozen_string_literal: true

RSpec.describe 'Content permissions' do
  let(:account) { create(:account, name: 'Scoped Account') }
  let(:admin_user) { create(:user, account:, email: 'admin@example.com') }
  let(:viewer_user) { create(:user, account:, email: 'viewer@example.com') }
  let(:contributor_user) { create(:user, account:, email: 'contributor@example.com') }
  let!(:folder) { create(:template_folder, account:, author: admin_user, name: 'Protected Folder') }
  let!(:template) { create(:template, account:, author: admin_user, folder:, name: 'Protected Template') }
  let!(:submission) { create(:submission, template:, account:, created_by_user: admin_user, name: 'Protected Submission') }

  before do
    viewer_user.account_access_for(account).update!(role: AccountAccess::VIEWER_ROLE)
    contributor_user.account_access_for(account).update!(role: AccountAccess::CONTRIBUTOR_ROLE)
  end

  describe 'GET /templates and direct access' do
    it 'hides inaccessible templates and folders from viewer listings and blocks direct access' do
      # Arrange
      create(
        :content_access,
        user: viewer_user,
        securable: folder,
        template_permission: ContentAccess::NO_ACCESS_PERMISSION,
        submission_permission: ContentAccess::NO_ACCESS_PERMISSION
      )
      sign_in(viewer_user)

      # Initial Assert
      expect(viewer_user.membership_role_for(account)).to eq(AccountAccess::VIEWER_ROLE)

      # Act
      get templates_path

      # Assert
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('Protected Folder')
      expect(response.body).not_to include('Protected Template')

      get template_path(template)

      expect(response).to redirect_to(root_path)
    end
  end

  describe 'POST /content_accesses' do
    it 'prevents a contributor from removing their own ability to manage a template scope' do
      # Arrange
      create(
        :content_access,
        user: contributor_user,
        securable: template,
        template_permission: ContentAccess::ADMIN_PERMISSION,
        submission_permission: ContentAccess::ADMIN_PERMISSION
      )
      sign_in(contributor_user)

      # Initial Assert
      resolver = ContentPermissions::Resolver.new(contributor_user, account:)
      expect(resolver.can_manage_content_permissions?(template)).to be(true)

      # Act
      post content_accesses_path, params: {
        content_access: {
          user_id: contributor_user.id,
          securable_type: 'Template',
          securable_id: template.id,
          template_permission: ContentAccess::VIEWER_PERMISSION,
          submission_permission: ContentAccess::VIEWER_PERMISSION
        }
      }

      # Assert
      expect(response).to redirect_to(template_preferences_path(template))
      expect(flash[:alert]).to eq(I18n.t('content_access_self_lockout_prevented'))

      persisted_access = ContentAccess.find_by(user: contributor_user, securable: template)

      expect(persisted_access.template_permission).to eq(ContentAccess::ADMIN_PERMISSION)
      expect(persisted_access.submission_permission).to eq(ContentAccess::ADMIN_PERMISSION)
    end
  end

  describe 'submission permissions' do
    it 'keeps viewers from archiving submissions and lets submission admins archive them' do
      # Arrange
      create(
        :content_access,
        user: viewer_user,
        securable: template,
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

      # Initial Assert
      expect(submission.archived_at).to be_nil

      # Act
      sign_in(viewer_user)
      delete submission_path(submission)

      # Assert
      expect(response).to redirect_to(root_path)
      expect(submission.reload.archived_at).to be_nil

      sign_in(contributor_user)
      delete submission_path(submission)

      expect(response).to redirect_to(template_path(template))
      expect(submission.reload.archived_at).not_to be_nil
    end
  end
end
