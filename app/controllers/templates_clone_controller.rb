# frozen_string_literal: true

class TemplatesCloneController < ApplicationController
  load_and_authorize_resource :template, instance_name: :base_template

  def new
    raise CanCan::AccessDenied unless can_archive_template?(@base_template)

    @template = Template.new(name: "#{@base_template.name} (#{I18n.t('clone')})")
  end

  def create
    ActiveRecord::Associations::Preloader.new(
      records: [@base_template],
      associations: [schema_documents: :preview_images_attachments]
    ).call

    destination_account =
      if params[:account_id].present? && true_ability.can?(:manage, Account.find(params[:account_id]))
        Account.find(params[:account_id])
      else
        current_account
      end

    folder_resolution =
      if params[:folder_name].present?
        TemplateFolders.resolve_by_name(destination_account, params[:folder_name])
      elsif destination_account == current_account
        TemplateFolders::Resolution.new(folder: @base_template.folder, authorization_folder: @base_template.folder, requires_creation: false)
      else
        default_folder = destination_account.default_template_folder
        TemplateFolders::Resolution.new(folder: default_folder, authorization_folder: default_folder, requires_creation: false)
      end

    raise CanCan::AccessDenied unless can_archive_template?(@base_template)
    raise CanCan::AccessDenied unless can_create_template_in_folder?(folder_resolution.authorization_folder)

    target_folder = TemplateFolders.materialize_resolution(current_user, folder_resolution)

    @template = Templates::Clone.call(@base_template, author: current_user,
                                                      name: params.dig(:template, :name),
                                                      folder: target_folder,
                                                      destination_account:)

    if destination_account != current_account
      @template.account_id = destination_account.id
      @template.author = true_user if true_user.account_id == @template.account_id
    else
      @template.account = current_account
    end

    Templates.maybe_assign_access(@template)

    if @template.save
      Templates::CloneAttachments.call(template: @template, original_template: @base_template)

      SearchEntries.enqueue_reindex(@template)

      WebhookUrls.enqueue_events(@template, 'template.created')

      maybe_redirect_to_template(@template)
    else
      render turbo_stream: turbo_stream.replace(:modal, partial: 'templates_clone/form'), status: :unprocessable_content
    end
  end

  private

  def maybe_redirect_to_template(template)
    if template.account == current_account
      redirect_to(edit_template_path(template))
    else
      redirect_back(fallback_location: root_path, notice: I18n.t('template_has_been_cloned'))
    end
  end
end
