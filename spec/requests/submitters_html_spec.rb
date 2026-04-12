# frozen_string_literal: true

RSpec.describe 'Submitters HTML' do
  describe 'PATCH /submitters/:id' do
    it 'blocks SMS resend requests for self-hosted deployments before any jobs are enqueued' do
      # Arrange
      account = create(:account)
      user = create(:user, account:)
      template = create(:template, account:, author: user)
      submission = create(:submission, template:, created_by_user: user)
      submitter = create(:submitter, submission:, account:, phone: '+15551234567', uuid: SecureRandom.uuid)

      sign_in(user)

      # Initial Assert
      expect(SendSubmitterInvitationEmailJob.jobs).to be_empty

      # Act
      expect do
        patch submitter_path(submitter), params: { send_sms: '1' }
      end.not_to change(SendSubmitterInvitationEmailJob.jobs, :size)

      # Assert
      expect(response).to redirect_to(submission_path(submission))
      expect(flash[:alert]).to eq(I18n.t('sms_delivery_is_not_enabled_for_this_deployment'))
    end
  end
end
