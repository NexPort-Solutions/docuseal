# frozen_string_literal: true

class CreateGlobalConfigs < ActiveRecord::Migration[8.0]
  def change
    create_table :global_configs do |t|
      t.string :key, null: false
      t.text :value, null: false

      t.timestamps
    end

    add_index :global_configs, :key, unique: true
  end
end
