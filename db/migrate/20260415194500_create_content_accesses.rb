# frozen_string_literal: true

class CreateContentAccesses < ActiveRecord::Migration[8.1]
  def change
    create_table :content_accesses do |t|
      t.references :user, null: false, foreign_key: true
      t.references :securable, polymorphic: true, null: false
      t.string :template_permission, null: false, default: 'inherit'
      t.string :submission_permission, null: false, default: 'inherit'

      t.timestamps
    end

    add_index :content_accesses, %i[user_id securable_type securable_id], unique: true,
              name: 'index_content_accesses_on_user_and_securable'
  end
end
