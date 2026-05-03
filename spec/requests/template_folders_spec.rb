# frozen_string_literal: true

RSpec.describe 'Template folders' do
  describe 'GET /templates' do
    it 'shows create menu actions for templates and folders' do
      # Arrange
      user = create(:user)
      sign_in(user)

      # Initial Assert
      expect(user.account.default_template_folder).to be_present

      # Act
      get templates_path

      # Assert
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('templates_create_button')
      expect(response.body).to include(new_template_path)
      expect(response.body).to include(new_folder_path)
      expect(response.body).to include('New Template')
      expect(response.body).to include('New Folder')
    end
  end

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

  describe 'GET /folders/new' do
    it 'renders the new folder modal' do
      # Arrange
      user = create(:user)
      sign_in(user)

      # Initial Assert
      expect(user.account.default_template_folder).to be_present

      # Act
      get new_folder_path

      # Assert
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('New Folder')
      expect(response.body).to include('template_folder[name]')
    end
  end

  describe 'POST /folders' do
    it 'creates a root folder and redirects to templates' do
      # Arrange
      user = create(:user)
      sign_in(user)

      # Initial Assert
      expect(user.account.template_folders.find_by(name: 'Client Docs', parent_folder: nil)).to be_nil

      # Act
      post folders_path, params: { template_folder: { name: 'Client Docs' } }

      # Assert
      expect(response).to redirect_to(templates_path)
      folder = user.account.template_folders.find_by!(name: 'Client Docs', parent_folder: nil)
      expect(folder.author).to eq(user)
    end

    it 'creates a child folder in the current folder and redirects back to the parent' do
      # Arrange
      user = create(:user)
      parent_folder = create(:template_folder, account: user.account, author: user, name: 'Parent Folder')
      sign_in(user)

      # Initial Assert
      expect(parent_folder.subfolders.find_by(name: 'Child Folder')).to be_nil

      # Act
      post folders_path, params: { parent_folder_id: parent_folder.id, template_folder: { name: 'Child Folder' } }

      # Assert
      expect(response).to redirect_to(folder_path(parent_folder))
      folder = parent_folder.subfolders.find_by!(name: 'Child Folder')
      expect(folder.author).to eq(user)
    end
  end

  describe 'DELETE /folders/:id' do
    it 'deletes an empty nested folder and redirects to the parent folder' do
      # Arrange
      user = create(:user)
      parent_folder = create(:template_folder, account: user.account, author: user, name: 'Parent Folder')
      folder = create(:template_folder, account: user.account, author: user, parent_folder:, name: 'Child Folder')
      sign_in(user)

      # Initial Assert
      expect(folder.deletable?).to be(true)

      # Act
      delete folder_path(folder)

      # Assert
      expect(response).to redirect_to(folder_path(parent_folder))
      expect(flash[:notice]).to eq(I18n.t('folder_has_been_deleted'))
      expect(TemplateFolder.exists?(folder.id)).to be(false)
    end

    it 'rejects deletion when the folder still has templates' do
      # Arrange
      user = create(:user)
      folder = create(:template_folder, :with_templates, account: user.account, author: user, name: 'Used Folder')
      sign_in(user)

      # Initial Assert
      expect(folder.templates.count).to be > 0

      # Act
      delete folder_path(folder)

      # Assert
      expect(response).to redirect_to(folder_path(folder))
      expect(flash[:alert]).to eq(I18n.t('folder_must_be_empty_before_deleting'))
      expect(TemplateFolder.exists?(folder.id)).to be(true)
    end

    it 'rejects deletion when the folder still has subfolders' do
      # Arrange
      user = create(:user)
      folder = create(:template_folder, account: user.account, author: user, name: 'Parent Folder')
      create(:template_folder, account: user.account, author: user, parent_folder: folder, name: 'Child Folder')
      sign_in(user)

      # Initial Assert
      expect(folder.subfolders.count).to eq(1)

      # Act
      delete folder_path(folder)

      # Assert
      expect(response).to redirect_to(folder_path(folder))
      expect(flash[:alert]).to eq(I18n.t('folder_must_be_empty_before_deleting'))
      expect(TemplateFolder.exists?(folder.id)).to be(true)
    end

    it 'rejects deletion of the default folder' do
      # Arrange
      user = create(:user)
      default_folder = user.account.default_template_folder
      sign_in(user)

      # Initial Assert
      expect(default_folder.default?).to be(true)

      # Act
      delete folder_path(default_folder)

      # Assert
      expect(response).to redirect_to(folder_path(default_folder))
      expect(flash[:alert]).to eq(I18n.t('default_folder_cannot_be_deleted'))
      expect(TemplateFolder.exists?(default_folder.id)).to be(true)
    end

    it 'respects folder manage permissions' do
      # Arrange
      account = create(:account)
      admin_user = create(:user, account:, email: 'admin@example.com')
      viewer_user = create(:user, account:, email: 'viewer@example.com')
      folder = create(:template_folder, account:, author: admin_user, name: 'Protected Folder')

      viewer_user.account_access_for(account).update!(role: AccountAccess::VIEWER_ROLE)
      sign_in(viewer_user)

      # Initial Assert
      expect(Ability.new(viewer_user, current_account: account).can?(:manage, folder)).to be(false)

      # Act
      delete folder_path(folder)

      # Assert
      expect(response).to redirect_to(root_path)
      expect(TemplateFolder.exists?(folder.id)).to be(true)
    end
  end
end
