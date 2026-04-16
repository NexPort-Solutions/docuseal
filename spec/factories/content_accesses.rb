# frozen_string_literal: true

FactoryBot.define do
  factory :content_access do
    user
    securable { association(:template, account: user.account, author: user) }
    template_permission { ContentAccess::INHERIT_PERMISSION }
    submission_permission { ContentAccess::INHERIT_PERMISSION }
  end
end
