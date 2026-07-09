# frozen_string_literal: true

RSpec.describe 'Upstream Wave 1 hardening' do
  describe 'PUT /api/submitters/:id' do
    it 'persists require_email_2fa' do
      # Arrange
      account = create(:account)
      author = create(:user, account:)
      template = create(:template, account:, author:, attachment_count: 0)
      submitter = create(:submission, :with_submitters, template:, created_by_user: author).submitters.first

      # Initial Assert
      expect(submitter.preferences['require_email_2fa']).to be_nil

      # Act
      put "/api/submitters/#{submitter.id}",
          headers: { 'x-auth-token': author.access_token.token },
          params: { require_email_2fa: true }.to_json

      # Assert
      expect(response).to have_http_status(:ok)
      expect(submitter.reload.preferences['require_email_2fa']).to be(true)
    end
  end

  describe 'POST /settings/reveal_access_token' do
    it 'throttles repeated failed password attempts' do
      # Arrange
      user = create(:user)
      sign_in(user)

      # Initial Assert
      expect(user.valid_password?('wrong-password')).to be(false)

      # Act
      4.times do
        post settings_reveal_access_token_path, params: { password: 'wrong-password' }
      end
      post settings_reveal_access_token_path, params: { password: 'wrong-password' }

      # Assert
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(I18n.t(:too_many_attempts))
    end
  end

  describe 'HEAD /file/:signed_uuid/:filename' do
    it 'returns blob metadata with browser-safe headers' do
      # Arrange
      account = create(:account)
      contents = 'blob response body'
      blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new(contents),
        filename: 'example.txt',
        content_type: 'text/plain'
      )
      ActiveStorage::Attachment.create!(record: account, name: 'logo', blob:)

      # Initial Assert
      expect(blob.byte_size).to eq(contents.bytesize)

      # Act
      head ActiveStorage::Blob.proxy_path(blob, expires_at: 1.hour.from_now)

      # Assert
      expect(response).to have_http_status(:ok)
      expect(response.headers['Content-Type']).to start_with('text/plain')
      expect(response.headers['Content-Length']).to eq(contents.bytesize.to_s)
      expect(response.headers['X-Content-Type-Options']).to eq('nosniff')
      expect(response.body).to be_empty
    end
  end

  it 'serves script-like uploads as binary content' do
    # Arrange
    binary_types = Rails.application.config.active_storage.content_types_to_serve_as_binary

    # Initial Assert
    expect(binary_types).not_to be_empty

    # Act
    configured_types = binary_types

    # Assert
    expect(configured_types).to include(
      'application/javascript',
      'text/javascript',
      'application/ecmascript',
      'text/ecmascript',
      'application/wasm'
    )
  end
end
