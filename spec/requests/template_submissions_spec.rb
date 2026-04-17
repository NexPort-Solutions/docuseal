# frozen_string_literal: true

RSpec.describe 'Template submissions' do
  describe 'POST /templates/:template_id/submissions' do
    it 'creates submissions from spreadsheet-import json payloads' do
      # Arrange
      user = create(:user)
      template = create(:template, account: user.account, author: user, except_field_types: %w[phone payment])
      sign_in(user)

      submissions_json = [
        {
          submitters: [
            {
              role: 'First Party',
              email: 'john.doe@example.com',
              name: 'John Doe',
              fields: [
                { name: 'First Name', default_value: 'John' }
              ]
            }
          ]
        },
        {
          submitters: [
            {
              role: 'First Party',
              email: 'jane.doe@example.com',
              name: 'Jane Doe',
              fields: [
                { name: 'First Name', default_value: 'Jane' }
              ]
            }
          ]
        }
      ].to_json

      # Initial Assert
      expect(Submission.count).to eq(0)

      # Act
      post template_submissions_path(template), params: {
        submissions_json:,
        send_email: '1'
      }

      # Assert
      expect(response).to redirect_to(template_path(template))
      expect(flash[:notice]).to eq(I18n.t('new_recipients_have_been_added'))
      expect(Submission.count).to eq(2)

      submissions = Submission.order(:id).last(2)
      expect(submissions.flat_map(&:submitters).map(&:email)).to match_array(
        %w[john.doe@example.com jane.doe@example.com]
      )
      expect(submissions.map { |submission| submission.template_fields.find { |field| field['name'] == 'First Name' }['default_value'] }).to match_array(%w[John Jane])
      expect(submissions.flat_map(&:submitters).map { |submitter| submitter.preferences['send_email'] }).to all(be(true))
    end
  end
end
