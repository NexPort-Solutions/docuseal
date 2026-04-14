# frozen_string_literal: true

RSpec.describe 'Template Conditions' do
  let(:account) { create(:account) }
  let(:author) { create(:user, account:) }
  let(:template) { create(:template, account:, author:, except_field_types: %w[phone payment]) }

  before do
    sign_in(author)
  end

  it 'opens the conditions modal without a Pro-only blocker and autosaves a condition' do
    # Arrange
    visit edit_template_path(template)

    first_field = template.fields.find { |item| item['name'] == 'First Name' }
    condition_source_field = template.fields.find { |item| item['name'] == 'Birthday' }

    # Initial Assert
    expect(first_field['conditions']).to be_blank

    # Act
    field_row = find('.list-field', text: 'First Name')
    field_row.find('.field-settings-dropdown label').click
    field_row.find('.field-settings-condition').click

    within '.modal-box' do
      expect(page).not_to have_content('Available in Pro')
      find_all('select').first.find('option', text: 'Birthday').select_option
      find('.modal-save-button').click
    end

    page.driver.wait_for_network_idle

    # Assert
    Timeout.timeout(Capybara.default_max_wait_time) do
      loop do
        persisted_field = template.reload.fields.find { |item| item['uuid'] == first_field['uuid'] }
        break if persisted_field['conditions'].present?

        sleep 0.05
      end
    end

    condition = template.reload.fields.find { |item| item['uuid'] == first_field['uuid'] }['conditions'].first

    expect(condition['field_uuid']).to eq(condition_source_field['uuid'])
    expect(condition['action']).to eq('not_empty')
  end
end
