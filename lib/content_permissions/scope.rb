# frozen_string_literal: true

module ContentPermissions
  class Scope
    attr_reader :user, :account, :resolver

    def initialize(user, account:)
      @user = user
      @account = account
      @resolver = Resolver.new(user, account:)
    end

    def readable_folder_ids
      return account.template_folders.select(:id) if user.platform_admin? || user.account_admin_for?(account)

      folders.select { |folder| resolver.can_view_folder?(folder) }.map(&:id)
    end

    def manageable_folder_ids
      return account.template_folders.select(:id) if user.platform_admin? || user.account_admin_for?(account)

      folders.select { |folder| resolver.can_manage_folder?(folder) }.map(&:id)
    end

    def readable_template_ids
      return account.templates.select(:id) if user.platform_admin? || user.account_admin_for?(account)

      templates.select { |template| resolver.can_view_template?(template) }.map(&:id)
    end

    def editable_template_ids
      return account.templates.select(:id) if user.platform_admin? || user.account_admin_for?(account)

      templates.select { |template| resolver.can_edit_template?(template) }.map(&:id)
    end

    def admin_template_ids
      return account.templates.select(:id) if user.platform_admin? || user.account_admin_for?(account)

      templates.select { |template| resolver.can_archive_template?(template) }.map(&:id)
    end

    def readable_submission_ids
      return account.submissions.select(:id) if user.platform_admin? || user.account_admin_for?(account)

      submissions.select { |submission| resolver.can_view_submission?(submission) }.map(&:id)
    end

    def admin_submission_ids
      return account.submissions.select(:id) if user.platform_admin? || user.account_admin_for?(account)

      submissions.select { |submission| resolver.can_archive_submission?(submission) }.map(&:id)
    end

    def creatable_folder_ids
      manageable_folder_ids
    end

    private

    def folders
      @folders ||= account.template_folders.select(:id, :parent_folder_id, :name).to_a
    end

    def templates
      @templates ||= account.templates.select(:id, :folder_id, :name).to_a
    end

    def submissions
      @submissions ||= account.submissions.select(:id, :template_id, :account_id).to_a
    end
  end
end
