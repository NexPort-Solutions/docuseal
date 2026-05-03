# frozen_string_literal: true

class TemplateFoldersController < ApplicationController
  load_and_authorize_resource :template_folder, except: %i[new create]

  helper_method :selected_order

  TEMPLATES_PER_PAGE = 12
  FOLDERS_PER_PAGE = 18

  def show
    content_scope = ContentPermissions::Scope.new(current_user, account: current_account)
    readable_templates = current_account.templates.where(id: content_scope.readable_template_ids).active

    @templates = readable_templates
                 .where(folder: [@template_folder, *(params[:q].present? ? @template_folder.subfolders : [])])
                 .preload(:author, :content_accesses, folder: :content_accesses)

    @template_folders =
      @template_folder.subfolders.where(id: readable_templates.select(:folder_id))

    @template_folders = TemplateFolders.search(@template_folders, params[:q])
    @template_folders = TemplateFolders.sort(@template_folders, current_account:, order: selected_order)

    if @templates.exists?
      @templates = Templates.search(current_user, current_account, @templates, params[:q])
      @templates = Templates::Order.call(@templates, current_account:, order: selected_order)

      limit =
        if @template_folders.size < 4
          TEMPLATES_PER_PAGE
        else
          (@template_folders.size < 7 ? 9 : 6)
        end

      @pagy, @templates = pagy_auto(@templates, limit:)

      load_related_submissions if params[:q].present? && @templates.blank?
    else
      @pagy, @template_folders = pagy(@template_folders, limit: FOLDERS_PER_PAGE)

      @templates = @templates.none
    end
  end

  def edit; end

  def new
    @parent_folder = parent_folder
    authorize_folder_create!(@parent_folder)
    @template_folder = current_account.template_folders.new(parent_folder: @parent_folder)
  end

  def create
    @parent_folder = parent_folder
    authorize_folder_create!(@parent_folder)

    @template_folder = current_account.template_folders
                                      .create_with(author: current_user)
                                      .find_or_create_by(template_folder_params.merge(parent_folder: @parent_folder))

    if @template_folder.persisted?
      redirect_to(@parent_folder ? folder_path(@parent_folder) : templates_path,
                  notice: I18n.t('folder_has_been_created', default: 'Folder has been created.'))
    else
      render :new, status: :unprocessable_content
    end
  end

  def update
    if @template_folder != current_account.default_template_folder &&
       @template_folder.update(template_folder_params)
      redirect_to folder_path(@template_folder), notice: I18n.t('folder_name_has_been_updated')
    else
      redirect_to folder_path(@template_folder), alert: I18n.t('unable_to_rename_folder')
    end
  end

  def destroy
    if @template_folder.default?
      redirect_to folder_path(@template_folder), alert: I18n.t('default_folder_cannot_be_deleted')
    elsif @template_folder.deletable?
      redirect_path = @template_folder.parent_folder ? folder_path(@template_folder.parent_folder) : templates_path

      @template_folder.destroy!

      redirect_to redirect_path, notice: I18n.t('folder_has_been_deleted')
    else
      redirect_to folder_path(@template_folder), alert: I18n.t('folder_must_be_empty_before_deleting')
    end
  end

  private

  def selected_order
    @selected_order ||=
      if cookies.permanent[:dashboard_templates_order].blank? ||
         (cookies.permanent[:dashboard_templates_order] == 'used_at' && can?(:manage, :countless))
        'created_at'
      else
        cookies.permanent[:dashboard_templates_order]
      end
  end

  def template_folder_params
    params.require(:template_folder).permit(:name)
  end

  def parent_folder
    return if params[:parent_folder_id].blank?

    current_account.template_folders.find(params[:parent_folder_id])
  end

  def authorize_folder_create!(parent_folder)
    authorization_folder = parent_folder || current_account.default_template_folder

    authorize!(:create, Template)

    raise CanCan::AccessDenied unless can_create_template_in_folder?(authorization_folder)
  end

  def load_related_submissions
    @related_submissions =
      Submission.accessible_by(current_ability)
                .where(archived_at: nil)
                .where(template_id: current_account.templates.active
                                                   .where(folder: [@template_folder, *@template_folder.subfolders])
                                                   .select(:id))
                .preload(:template_accesses, :created_by_user,
                         template: :author,
                         submitters: :start_form_submission_events)

    @related_submissions = Submissions.search(current_user, current_account, @related_submissions, params[:q])
                                      .order(id: :desc)

    @related_submissions_pagy, @related_submissions = pagy_auto(@related_submissions, limit: 5)
  end
end
