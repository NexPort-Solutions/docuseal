# frozen_string_literal: true

module Api
  class TemplatesCloneController < ApiBaseController
    load_and_authorize_resource :template

    def create
      raise CanCan::AccessDenied unless can_archive_template?(@template)

      ActiveRecord::Associations::Preloader.new(
        records: [@template],
        associations: [schema_documents: :preview_images_attachments]
      ).call

      folder_resolution =
        if params[:folder_name].present?
          TemplateFolders.resolve_by_name(current_account, params[:folder_name])
        else
          TemplateFolders::Resolution.new(folder: @template.folder, authorization_folder: @template.folder, requires_creation: false)
        end

      raise CanCan::AccessDenied unless can_create_template_in_folder?(folder_resolution.authorization_folder)

      target_folder = TemplateFolders.materialize_resolution(current_user, folder_resolution)

      cloned_template = Templates::Clone.call(
        @template,
        author: current_user,
        name: params[:name],
        external_id: params[:external_id].presence || params[:application_key],
        folder: target_folder,
        destination_account: current_account
      )

      cloned_template.source = :api

      schema_documents = Templates::CloneAttachments.call(template: cloned_template,
                                                          original_template: @template,
                                                          documents: params[:documents])

      Templates.maybe_assign_access(cloned_template)

      cloned_template.save!

      WebhookUrls.enqueue_events(cloned_template, 'template.created')

      SearchEntries.enqueue_reindex(cloned_template)

      render json: Templates::SerializeForApi.call(cloned_template, schema_documents:)
    end
  end
end
