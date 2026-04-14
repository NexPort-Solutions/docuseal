# frozen_string_literal: true

RSpec.describe 'Template folders' do
  describe 'GET /folders/:id' do
    it 'links the top-level folder breadcrumb back to templates' do
      # Arrange
      user = create(:user)
      folder = create(:template_folder, account: user.account, author: user)
      sign_in(user)

      # Act
      get folder_path(folder)

      # Assert
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(href="#{templates_path}"))
      expect(response.body).to include('Home')
    end

    it 'links a nested folder breadcrumb to its parent folder' do
      # Arrange
      user = create(:user)
      parent_folder = create(:template_folder, account: user.account, author: user, name: 'Parent Folder')
      child_folder = create(:template_folder, account: user.account, author: user,
                                              parent_folder: parent_folder, name: 'Child Folder')
      sign_in(user)

      # Act
      get folder_path(child_folder)

      # Assert
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(href="#{folder_path(parent_folder)}"))
      expect(response.body).to include('Parent Folder')
    end
  end
end
