# frozen_string_literal: true

module EncryptedConfigRecovery
  extend ActiveSupport::Concern

  private

  def recover_unreadable_encrypted_config(record, unreadable:)
    return record unless unreadable && record.persisted?

    identity_attrs = { key: record[:key] }
    identity_attrs[:account_id] = record[:account_id] if record.has_attribute?(:account_id)

    record.class.transaction do
      record.class.where(id: record.id).delete_all
      record.class.new(identity_attrs)
    end
  end
end
