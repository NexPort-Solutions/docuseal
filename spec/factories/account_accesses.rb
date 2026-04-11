# frozen_string_literal: true

FactoryBot.define do
  factory :account_access do
    account
    user
    role { AccountAccess::CONTRIBUTOR_ROLE }
  end
end
