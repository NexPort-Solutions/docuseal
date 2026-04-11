# frozen_string_literal: true

module Abilities
  module TemplateConditions
    module_function

    def collection(user, account:, ability: nil)
      templates = Template.where(account_id: account.id)

      return templates unless account.testing?

      shared_ids =
        TemplateSharing.where({ ability:, account_id: [account.id, TemplateSharing::ALL_ID] }.compact)
                       .select(:template_id)

      Template.where(Template.arel_table[:id].in(templates.select(:id).arel.union(:all, shared_ids.arel)))
    end

    def entity(template, user:, account:, ability: nil)
      return true if template.account_id.blank?
      return true if template.account_id == account.id
      return false unless account.linked_account_account
      return false if template.template_sharings.to_a.blank?

      account_ids = [account.id, TemplateSharing::ALL_ID]

      template.template_sharings.to_a.any? do |e|
        e.account_id.in?(account_ids) && (ability.nil? || e.ability == 'manage' || e.ability == ability)
      end
    end
  end
end
