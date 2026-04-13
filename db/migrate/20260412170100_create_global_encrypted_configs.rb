# frozen_string_literal: true

class CreateGlobalEncryptedConfigs < ActiveRecord::Migration[8.0]
  def change
    create_table :global_encrypted_configs do |t|
      t.string :key, null: false
      t.text :value, null: false

      t.timestamps
    end

    add_index :global_encrypted_configs, :key, unique: true
  end
end
