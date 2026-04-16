# frozen_string_literal: true

class TemplateFoldersAutocompleteController < ApplicationController
  load_and_authorize_resource :template_folder, parent: false

  LIMIT = 30

  def index
    content_scope = ContentPermissions::Scope.new(current_user, account: current_account)

    parent_name, name =
      if params[:parent_name].present?
        [params[:parent_name], params[:q]]
      else
        params[:q].to_s.split(' /', 2).map(&:squish)
      end

    if name
      parent_folder = @template_folders.find_by(name: parent_name, parent_folder_id: nil)
    else
      name = parent_name
    end

    readable_templates = current_account.templates.where(id: content_scope.readable_template_ids)
    template_folders = TemplateFolders.filter_active_folders(@template_folders.where(parent_folder:),
                                                             readable_templates)

    name = name.to_s.downcase

    template_folders = TemplateFolders.search(template_folders, name).order(id: :desc).limit(LIMIT)

    render json: template_folders.preload(:parent_folder)
                                 .sort_by { |e| e.name.downcase.index(name) || Float::MAX }
                                 .as_json(only: %i[name archived_at], methods: %i[full_name])
  end
end
