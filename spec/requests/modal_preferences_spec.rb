# frozen_string_literal: true

RSpec.describe 'Permissions modal presentation' do
  describe 'GET /folders/:id/edit' do
    it 'renders the folder modal with general and permissions tabs in the large width shell' do
      user = create(:user)
      folder = create(:template_folder, account: user.account, author: user)
      sign_in(user)

      get edit_folder_path(folder)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Edit Folder')
      expect(response.body).to include('General')
      expect(response.body).to include(I18n.t('permissions'))
      expect(response.body).to include('md:w-[940px]')
    end
  end

  describe 'GET /templates/:id/preferences' do
    it 'renders a dedicated permissions tab for manageable templates' do
      user = create(:user)
      template = create(:template, account: user.account, author: user)
      sign_in(user)

      get template_preferences_path(template)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('id="permissions"')
      expect(response.body).to include('option_permissions')
    end
  end
end
