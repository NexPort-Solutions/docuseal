# frozen_string_literal: true

RSpec.describe 'Template Share Link' do
  let!(:account) { create(:account) }
  let!(:author) { create(:user, account:) }
  let!(:template) { create(:template, account:, author:) }

  before do
    sign_in(author)
  end

  def wait_for_shared_link(template, value)
    Timeout.timeout(Capybara.default_max_wait_time) do
      loop do
        template.reload
        break if template.shared_link == value

        sleep 0.05
      end
    end
  end

  context 'when the template is not shareable' do
    before do
      visit template_path(template)
    end

    it 'makes the template shareable' do
      find('#template_share_link_button').click

      within '#modal' do
        check 'template_shared_link'
      end

      wait_for_shared_link(template, true)
      expect(template.shared_link).to eq(true)
    end

    it 'makes the template shareable on toggle' do
      find('#template_share_link_button').click

      within '#modal' do
        find('#template_shared_link').click
      end

      wait_for_shared_link(template, true)
      expect(template.shared_link).to eq(true)
    end
  end

  context 'when the template is already shareable' do
    before do
      template.update(shared_link: true)
      visit template_path(template)
    end

    it 'makes the template unshareable' do
      find('#template_share_link_button').click

      within '#modal' do
        uncheck 'template_shared_link'
      end

      wait_for_shared_link(template, false)
      expect(template.shared_link).to eq(false)
    end
  end
end
