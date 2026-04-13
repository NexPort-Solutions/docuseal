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

    can :read, Account, id: current_account.id
    can :read, Template, Abilities::TemplateConditions.collection(user, account: current_account) do |template|
      Abilities::TemplateConditions.entity(template, user:, account: current_account, ability: 'read')
    end

    can :read, TemplateFolder, account_id: current_account.id
    can :read, Submission, account_id: current_account.id
    can :read, Submitter, account_id: current_account.id

    if user.contributor_for?(current_account)
      can %i[create update destroy], Template, Abilities::TemplateConditions.collection(user, account: current_account) do |template|
        Abilities::TemplateConditions.entity(template, user:, account: current_account, ability: 'manage')
      end

      can :manage, TemplateFolder, account_id: current_account.id
      can :manage, TemplateSharing, template: { account_id: current_account.id }
      can :manage, Submission, account_id: current_account.id
      can :manage, Submitter, account_id: current_account.id
      can :manage, WebhookUrl, account_id: current_account.id
    end

    return unless user.account_admin_for?(current_account)

    can :manage_members, Account, id: current_account.id
    can :manage, Account, id: current_account.id
    can :manage, EncryptedConfig, account_id: current_account.id
    can :manage, AccountConfig, account_id: current_account.id
  end
end
