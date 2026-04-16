# frozen_string_literal: true

class ContentAccessesController < ApplicationController
  def create
    securable = load_securable

    authorize!(:manage_permissions, securable)

    target_user = current_account_members.find(content_access_params[:user_id])
    self_lockout = false

    ContentAccess.transaction do
      access = ContentAccess.find_or_initialize_by(
        securable:,
        user: target_user
      )

      access.assign_attributes(
        template_permission: content_access_params[:template_permission],
        submission_permission: content_access_params[:submission_permission]
      )

      if access.inherited?
        access.destroy! if access.persisted?
      else
        access.save!
      end

      if target_user == current_user && !content_permissions_resolver.can_manage_content_permissions?(securable)
        self_lockout = true
        raise ActiveRecord::Rollback
      end
    end

    if self_lockout
      redirect_to content_access_redirect_path(securable), alert: I18n.t('content_access_self_lockout_prevented')
    else
      redirect_to content_access_redirect_path(securable), notice: I18n.t('changes_have_been_saved')
    end
  end

  private

  def load_securable
    klass = content_access_params[:securable_type].safe_constantize

    raise ActionController::RoutingError, 'Not Found' unless klass.in?([Template, TemplateFolder])

    current_account.public_send(klass == Template ? :templates : :template_folders).find(content_access_params[:securable_id])
  end

  def content_access_redirect_path(securable)
    case securable
    when Template
      template_preferences_path(securable)
    when TemplateFolder
      edit_folder_path(securable)
    else
      root_path
    end
  end

  def content_access_params
    params.require(:content_access)
          .permit(:user_id, :securable_type, :securable_id, :template_permission, :submission_permission)
          .tap do |attrs|
      attrs[:template_permission] = ContentAccess::INHERIT_PERMISSION unless attrs[:template_permission].in?(ContentAccess::TEMPLATE_PERMISSIONS)
      attrs[:submission_permission] = ContentAccess::INHERIT_PERMISSION unless attrs[:submission_permission].in?(ContentAccess::SUBMISSION_PERMISSIONS)
    end
  end
end
