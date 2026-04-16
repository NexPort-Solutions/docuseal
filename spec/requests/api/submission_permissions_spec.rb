# frozen_string_literal: true

RSpec.describe 'Submission API content permissions' do
  let(:account) { create(:account, :with_testing_account) }
  let(:folder) { create(:template_folder, account:) }
  let(:template_author) { create(:user, account:, email: 'template-author@example.com') }
  let(:viewer_user) { create(:user, account:, email: 'viewer-api@example.com') }
  let(:contributor_user) { create(:user, account:, email: 'contributor-api@example.com') }
  let(:template) { create(:template, account:, author: template_author, folder:) }

  before do
    viewer_user.account_access_for(account).update!(role: AccountAccess::VIEWER_ROLE)
    contributor_user.account_access_for(account).update!(role: AccountAccess::CONTRIBUTOR_ROLE)
  end

  describe 'POST /api/submissions' do
    it 'rejects viewer access and allows a contributor with submission admin access' do
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

      params = {
        template_id: template.id,
        send_email: true,
        submitters: [{ role: 'First Party', email: 'john.doe@example.com' }]
      }.to_json

      # Initial Assert
      expect(Submission.count).to eq(0)

      # Act
      post '/api/submissions', headers: { 'x-auth-token': viewer_user.access_token.token }, params: params

      # Assert
      expect(response).to have_http_status(:forbidden)
      expect(Submission.count).to eq(0)

      post '/api/submissions', headers: { 'x-auth-token': contributor_user.access_token.token }, params: params

      expect(response).to have_http_status(:ok)
      expect(Submission.count).to eq(1)
    end
  end
end
