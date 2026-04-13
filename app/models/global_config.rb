# frozen_string_literal: true

# == Schema Information
#
# Table name: global_configs
#
#  id         :bigint           not null, primary key
#  key        :string           not null
#  value      :text             not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_global_configs_on_key  (key) UNIQUE
#
class GlobalConfig < ApplicationRecord
  CONFIG_KEYS = [
    ENABLE_MCP_KEY = 'enable_mcp'
  ].freeze

  serialize :value, coder: JSON
end
