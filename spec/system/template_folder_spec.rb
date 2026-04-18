# frozen_string_literal: true

RSpec.describe 'Template folder management' do
  it 'deletes an empty folder from the edit modal' do
    # Arrange
    user = create(:user)
    folder = create(:template_folder, account: user.account, author: user, name: 'Disposable Folder')
    sign_in(user)

    # Initial Assert
    expect(folder.deletable?).to be(true)

    # Act
    visit edit_folder_path(folder)

    within(all('#modal', visible: true).last) do
      accept_confirm do
        click_button I18n.t('delete_folder')
      end
    end

    # Assert
    expect(page).to have_current_path(templates_path, ignore_query: true)
    expect(page).to have_content(I18n.t('folder_has_been_deleted'))
    expect(TemplateFolder.exists?(folder.id)).to be(false)
  end

  it 'keeps a non-empty folder and shows an alert when deletion is attempted' do
    # Arrange
    user = create(:user)
    folder = create(:template_folder, account: user.account, author: user, name: 'Busy Folder')
    create(:template, account: user.account, author: user, folder:)
    sign_in(user)

    # Initial Assert
    expect(folder.templates.count).to eq(1)

    # Act
    visit edit_folder_path(folder)

    within(all('#modal', visible: true).last) do
      accept_confirm do
        click_button I18n.t('delete_folder')
      end
    end

    # Assert
    expect(page).to have_current_path(folder_path(folder), ignore_query: true)
    expect(page).to have_content(I18n.t('folder_must_be_empty_before_deleting'))
    expect(TemplateFolder.exists?(folder.id)).to be(true)
  end
end
