# frozen_string_literal: true

class TemplatesFoldersController < ApplicationController
  load_and_authorize_resource :template

  def edit; end

  def update
    name = [params[:parent_name], params[:name]].compact_blank.join(' / ')
    target_resolution = TemplateFolders.resolve_by_name(current_account, name)

    raise CanCan::AccessDenied unless can_create_template_in_folder?(target_resolution.authorization_folder)

    @template.folder = TemplateFolders.materialize_resolution(current_user, target_resolution)

    if @template.save
      redirect_back(fallback_location: template_path(@template), notice: I18n.t('document_template_has_been_moved'))
    else
      redirect_back(fallback_location: template_path(@template), notice: I18n.t('unable_to_move_template_into_folder'))
    end
  end

  private

  def template_folder_params
    params.require(:template_folder).permit(:name)
  end
end
