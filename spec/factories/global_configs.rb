# frozen_string_literal: true

FactoryBot.define do
  factory :global_config do
    key { GlobalConfig::ENABLE_MCP_KEY }
    value { false }
  end
end
