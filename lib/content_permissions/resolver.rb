# frozen_string_literal: true

module ContentPermissions
  class Resolver
    Result = Struct.new(
      :template_permission,
      :submission_permission,
      :template_source,
      :submission_source,
      keyword_init: true
    )

    Source = Struct.new(:kind, :record_type, :record_id, :name, keyword_init: true)

    ACCOUNT_ADMIN_RESULT = Result.new(
      template_permission: ContentAccess::ADMIN_PERMISSION,
      submission_permission: ContentAccess::ADMIN_PERMISSION,
      template_source: Source.new(kind: :account_role, name: AccountAccess::ACCOUNT_ADMIN_ROLE),
      submission_source: Source.new(kind: :account_role, name: AccountAccess::ACCOUNT_ADMIN_ROLE)
    ).freeze

    attr_reader :user

    def initialize(user, account: nil)
      @user = user
      @account = account
      @account_state = {}
      @folder_results = {}
      @template_results = {}
      @submission_results = {}
    end

    def resolve_folder(folder)
      return deny_result unless folder && user

      account = @account || folder.account
      return ACCOUNT_ADMIN_RESULT if user.platform_admin? || user.account_admin_for?(account)

      cache_key = [account.id, folder.id]
      @folder_results[cache_key] ||= build_folder_result(folder, account)
    end

    def resolve_template(template)
      return deny_result unless template && user

      account = @account || template.account
      return ACCOUNT_ADMIN_RESULT if user.platform_admin? || user.account_admin_for?(account)

      cache_key = [account.id, template.id]
      @template_results[cache_key] ||= build_template_result(template, account)
    end

    def resolve_submission(submission)
      return deny_result unless submission && user

      account = @account || submission.account
      return ACCOUNT_ADMIN_RESULT if user.platform_admin? || user.account_admin_for?(account)

      cache_key = [account.id, submission.id]
      @submission_results[cache_key] ||= build_submission_result(submission, account)
    end

    def can_view_folder?(folder)
      resolve_folder(folder).template_permission != ContentAccess::NO_ACCESS_PERMISSION
    end

    def can_manage_folder?(folder)
      resolve_folder(folder).template_permission == ContentAccess::ADMIN_PERMISSION
    end

    def can_create_template_in_folder?(folder)
      can_manage_folder?(folder)
    end

    def can_view_template?(template)
      resolve_template(template).template_permission != ContentAccess::NO_ACCESS_PERMISSION
    end

    def can_edit_template?(template)
      resolve_template(template).template_permission.in?([ContentAccess::EDITOR_PERMISSION, ContentAccess::ADMIN_PERMISSION])
    end

    def can_archive_template?(template)
      resolve_template(template).template_permission == ContentAccess::ADMIN_PERMISSION
    end

    def can_manage_content_permissions?(securable)
      case securable
      when TemplateFolder
        can_manage_folder?(securable)
      when Template
        resolve_template(securable).template_permission == ContentAccess::ADMIN_PERMISSION
      else
        false
      end
    end

    def can_view_submission?(submission)
      resolve_submission(submission).submission_permission != ContentAccess::NO_ACCESS_PERMISSION
    end

    def can_edit_submission?(submission)
      resolve_submission(submission).submission_permission == ContentAccess::ADMIN_PERMISSION
    end

    def can_archive_submission?(submission)
      can_edit_submission?(submission)
    end

    def can_create_submission_from_template?(template)
      resolve_template(template).submission_permission == ContentAccess::ADMIN_PERMISSION
    end

    private

    def deny_result
      @deny_result ||= Result.new(
        template_permission: ContentAccess::NO_ACCESS_PERMISSION,
        submission_permission: ContentAccess::NO_ACCESS_PERMISSION,
        template_source: Source.new(kind: :no_membership),
        submission_source: Source.new(kind: :no_membership)
      )
    end

    def build_folder_result(folder, account)
      template_permission, template_source =
        resolve_folder_domain(account, folder.id, :template_permission)
      submission_permission, submission_source =
        resolve_folder_domain(account, folder.id, :submission_permission)

      Result.new(
        template_permission: cap_template_permission(default_template_permission_for(account), template_permission),
        submission_permission: cap_submission_permission(default_submission_permission_for(account), submission_permission),
        template_source: template_source,
        submission_source: submission_source
      )
    end

    def build_template_result(template, account)
      folder_result = resolve_folder(template.folder)
      access = access_for(account, 'Template', template.id)

      template_permission, template_source =
        explicit_or_default_permission(access, :template_permission, folder_result.template_permission,
                                       folder_result.template_source, template.name, 'Template', template.id)

      if access&.template_permission == ContentAccess::NO_ACCESS_PERMISSION
        submission_permission = ContentAccess::NO_ACCESS_PERMISSION
        submission_source = Source.new(kind: :explicit, record_type: 'Template', record_id: template.id, name: template.name)
      else
        submission_permission, submission_source =
          explicit_or_default_permission(access, :submission_permission, folder_result.submission_permission,
                                         folder_result.submission_source, template.name, 'Template', template.id)
      end

      Result.new(
        template_permission: cap_template_permission(default_template_permission_for(account), template_permission),
        submission_permission: cap_submission_permission(default_submission_permission_for(account), submission_permission),
        template_source: template_source,
        submission_source: submission_source
      )
    end

    def build_submission_result(submission, account)
      if submission.template
        template_result = resolve_template(submission.template)

        Result.new(
          template_permission: template_result.template_permission,
          submission_permission: template_result.submission_permission,
          template_source: template_result.template_source,
          submission_source: template_result.submission_source
        )
      else
        Result.new(
          template_permission: default_template_permission_for(account),
          submission_permission: default_submission_permission_for(account),
          template_source: Source.new(kind: :account_role, name: user.membership_role_for(account)),
          submission_source: Source.new(kind: :account_role, name: user.membership_role_for(account))
        )
      end
    end

    def resolve_folder_domain(account, folder_id, domain)
      current_folder_id = folder_id

      while current_folder_id.present?
        folder = state_for(account)[:folders][current_folder_id]
        access = access_for(account, 'TemplateFolder', current_folder_id)
        permission = access&.public_send(domain)

        if permission.present? && permission != ContentAccess::INHERIT_PERMISSION
          return [
            permission,
            Source.new(kind: :explicit, record_type: 'TemplateFolder', record_id: current_folder_id, name: folder&.name)
          ]
        end

        current_folder_id = folder&.parent_folder_id
      end

      [
        domain == :template_permission ? default_template_permission_for(account) : default_submission_permission_for(account),
        Source.new(kind: :account_role, name: user.membership_role_for(account))
      ]
    end

    def explicit_or_default_permission(access, field, inherited_permission, inherited_source, name, record_type, record_id)
      permission = access&.public_send(field)

      if permission.present? && permission != ContentAccess::INHERIT_PERMISSION
        [permission, Source.new(kind: :explicit, record_type:, record_id:, name:)]
      else
        [inherited_permission, inherited_source]
      end
    end

    def cap_template_permission(default_permission, explicit_permission)
      return ContentAccess::NO_ACCESS_PERMISSION if explicit_permission == ContentAccess::NO_ACCESS_PERMISSION
      return default_permission if default_permission == ContentAccess::VIEWER_PERMISSION

      explicit_permission
    end

    def cap_submission_permission(default_permission, explicit_permission)
      return ContentAccess::NO_ACCESS_PERMISSION if explicit_permission == ContentAccess::NO_ACCESS_PERMISSION
      return default_permission if default_permission == ContentAccess::VIEWER_PERMISSION

      explicit_permission
    end

    def default_template_permission_for(account)
      case user.membership_role_for(account)
      when AccountAccess::VIEWER_ROLE
        ContentAccess::VIEWER_PERMISSION
      when AccountAccess::CONTRIBUTOR_ROLE
        ContentAccess::ADMIN_PERMISSION
      else
        ContentAccess::NO_ACCESS_PERMISSION
      end
    end

    def default_submission_permission_for(account)
      case user.membership_role_for(account)
      when AccountAccess::VIEWER_ROLE
        ContentAccess::VIEWER_PERMISSION
      when AccountAccess::CONTRIBUTOR_ROLE
        ContentAccess::ADMIN_PERMISSION
      else
        ContentAccess::NO_ACCESS_PERMISSION
      end
    end

    def state_for(account)
      @account_state[account.id] ||= begin
        folder_rows = account.template_folders.select(:id, :parent_folder_id, :name).index_by(&:id)
        template_rows = account.templates.select(:id, :folder_id, :name).index_by(&:id)

        accesses =
          ContentAccess.where(user_id: user.id)
                       .where(
                         "(securable_type = 'TemplateFolder' AND securable_id IN (?)) OR (securable_type = 'Template' AND securable_id IN (?))",
                         folder_rows.keys.presence || [-1],
                         template_rows.keys.presence || [-1]
                       )
                       .index_by { |entry| [entry.securable_type, entry.securable_id] }

        {
          folders: folder_rows,
          templates: template_rows,
          accesses: accesses
        }
      end
    end

    def access_for(account, securable_type, securable_id)
      state_for(account)[:accesses][[securable_type, securable_id]]
    end
  end
end
