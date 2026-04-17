# frozen_string_literal: true

require 'rubyXL'

RSpec.describe 'Upload spreadsheets' do
  describe 'POST /upload_spreadsheet' do
    it 'accepts csv files and returns the expected sheet payload' do
      # Arrange
      user = create(:user)
      sign_in(user)
      tempfile, file = build_uploaded_csv("Email,Name\njohn.doe@example.com,John Doe\n")

      # Act
      post '/upload_spreadsheet', params: { file: }

      # Assert
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq([
                                           ['Sheet1', [['Email', 'Name'], ['john.doe@example.com', 'John Doe']]]
                                         ])
    ensure
      tempfile.close!
    end

    it 'accepts xlsx files and returns the expected sheet payload' do
      # Arrange
      user = create(:user)
      sign_in(user)
      tempfile, file = build_uploaded_xlsx(
        [
          ['Email', 'Name', 'First Name'],
          ['john.doe@example.com', 'John Doe', 'John']
        ]
      )

      # Act
      post '/upload_spreadsheet', params: { file: }

      # Assert
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq([
                                           ['Recipients',
                                            [['Email', 'Name', 'First Name'],
                                             ['john.doe@example.com', 'John Doe', 'John']]]
                                         ])
    ensure
      tempfile.close!
    end

    it 'rejects unsupported file types cleanly' do
      # Arrange
      user = create(:user)
      sign_in(user)
      tempfile = Tempfile.create(['recipients', '.txt'])
      tempfile.write('not a spreadsheet')
      tempfile.rewind
      file = Rack::Test::UploadedFile.new(tempfile.path, 'text/plain')

      # Act
      post '/upload_spreadsheet', params: { file: }

      # Assert
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq({ 'error' => I18n.t('invalid_file_type') })
    ensure
      tempfile.close!
    end

    it 'rejects invalid spreadsheet files cleanly' do
      # Arrange
      user = create(:user)
      sign_in(user)
      tempfile = Tempfile.create(['recipients', '.xlsx'])
      tempfile.write('not really xlsx')
      tempfile.rewind
      file = Rack::Test::UploadedFile.new(
        tempfile.path,
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
      )

      # Act
      post '/upload_spreadsheet', params: { file: }

      # Assert
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq({ 'error' => I18n.t('unable_to_read_spreadsheet') })
    ensure
      tempfile.close!
    end
  end

  def build_uploaded_csv(contents)
    tempfile = Tempfile.new(['recipients', '.csv'])
    tempfile.write(contents)
    tempfile.rewind

    [tempfile, Rack::Test::UploadedFile.new(tempfile.path, 'text/csv')]
  end

  def build_uploaded_xlsx(rows)
    workbook = RubyXL::Workbook.new
    worksheet = workbook[0]
    worksheet.sheet_name = 'Recipients'

    rows.each_with_index do |row, row_index|
      row.each_with_index do |value, column_index|
        worksheet.add_cell(row_index, column_index, value)
      end
    end

    tempfile = Tempfile.new(['recipients', '.xlsx'])
    workbook.write(tempfile.path)
    tempfile.rewind

    [
      tempfile,
      Rack::Test::UploadedFile.new(
        tempfile.path,
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
      )
    ]
  end
end
