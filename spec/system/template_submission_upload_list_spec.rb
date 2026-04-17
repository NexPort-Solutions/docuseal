# frozen_string_literal: true

RSpec.describe 'Template submission upload list' do
  it 'uploads a spreadsheet and creates recipients from the mapped rows' do
    # Arrange
    user = create(:user)
    template = create(:template, account: user.account, author: user, except_field_types: %w[phone payment])
    sign_in(user)
    csv_file = Tempfile.new(['recipients', '.csv'])
    csv_file.write("Email,Name,First Name\njohn.doe@example.com,John Doe,John\njane.doe@example.com,Jane Doe,Jane\n")
    csv_file.rewind

    # Initial Assert
    expect(Submission.count).to eq(0)

    # Act
    visit new_template_submission_path(template)
    choose('option_list', allow_label_click: true)
    expect(page).not_to have_content('This feature will be available in a future release for this deployment.')

    attach_file('import_list_file', csv_file.path, make_visible: true)
    expect(page).to have_content('Total entries: 2')

    click_button I18n.t('add_recipients')

    # Assert
    expect(page).to have_current_path(template_path(template), ignore_query: true)
    expect(page).to have_content(I18n.t('new_recipients_have_been_added'))
    expect(Submission.count).to eq(2)

    default_values = Submission.order(:id).last(2).map do |submission|
      submission.template_fields.find { |field| field['name'] == 'First Name' }['default_value']
    end

    expect(default_values).to match_array(%w[John Jane])
  ensure
    csv_file.close!
  end
end
