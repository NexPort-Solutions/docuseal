# frozen_string_literal: true

class Ability
  include CanCan::Ability

  def initialize(user, current_account: nil)
    return unless user

    if user.platform_admin?
      can :manage, :all
      can :read, :admin_console
      can :manage, :tenants
      can :manage, :reply_to
      can :manage, :personalization_advanced
      can :manage, :saml_sso

      return
    end

    can :manage, User, id: user.id
    can :manage, EncryptedUserConfig, user_id: user.id
    can :manage, UserConfig, user_id: user.id
    can :manage, AccessToken, user_id: user.id
    can :manage, McpToken, user_id: user.id
    can :manage, :mcp

    return unless current_account && user.can_access_account?(current_account)

    content_scope = ContentPermissions::Scope.new(user, account: current_account)
    readable_template_ids = Array(content_scope.readable_template_ids)

    can :read, Account, id: current_account.id
    can :read, Template, id: readable_template_ids
    can :read, Template do |template|
      readable_template_ids.include?(template.id) &&
      Abilities::TemplateConditions.entity(template, user:, account: current_account, ability: 'read')
    end

    can :read, TemplateFolder, id: content_scope.readable_folder_ids
    can :read, Submission, id: content_scope.readable_submission_ids
    can :read, Submitter, submission_id: content_scope.readable_submission_ids

    if user.contributor_for?(current_account)
      editable_template_ids = Array(content_scope.editable_template_ids)
      admin_template_ids = Array(content_scope.admin_template_ids)

      can :update, Template, id: editable_template_ids
      can :update, Template do |template|
        editable_template_ids.include?(template.id) &&
        Abilities::TemplateConditions.entity(template, user:, account: current_account, ability: 'manage')
      end
      can :destroy, Template, id: admin_template_ids
      can :destroy, Template do |template|
        admin_template_ids.include?(template.id) &&
        Abilities::TemplateConditions.entity(template, user:, account: current_account, ability: 'manage')
      end

      can :manage, :template_create if content_scope.creatable_folder_ids.present?
      can :manage, TemplateFolder, id: content_scope.manageable_folder_ids
      can :manage_permissions, Template, id: admin_template_ids
      can :manage_permissions, TemplateFolder, id: content_scope.manageable_folder_ids
      can :manage, TemplateSharing, template_id: admin_template_ids
      can %i[update destroy], Submission, id: content_scope.admin_submission_ids
      can :manage, Submitter, submission_id: content_scope.admin_submission_ids
      can :manage, WebhookUrl, account_id: current_account.id
    end

    return unless user.account_admin_for?(current_account)

    can :manage_members, Account, id: current_account.id
    can :manage, Account, id: current_account.id
    can :manage, EncryptedConfig, account_id: current_account.id
    can :manage, AccountConfig, account_id: current_account.id
  end
end
