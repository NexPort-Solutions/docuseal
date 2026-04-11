# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    account
    first_name { Faker::Name.first_name }
    last_name { Faker::Name.last_name }
    password { 'password' }
    role { User::ADMIN_ROLE }
    email { Faker::Internet.email }

    after(:create) do |user|
      user.account_accesses.find_or_initialize_by(account: user.account).tap do |access|
        access.role = AccountAccess::ACCOUNT_ADMIN_ROLE
        access.save!
      end
    end
  end
end
