# frozen_string_literal: true

class AddRoleToAccountAccesses < ActiveRecord::Migration[8.1]
  def up
    add_column :account_accesses, :role, :string, null: false, default: 'contributor'

    execute <<~SQL.squish
      UPDATE account_accesses
      SET role = 'account_admin'
      FROM users
      WHERE users.id = account_accesses.user_id
    SQL

    User.reset_column_information
    AccountAccess.reset_column_information

    User.find_each do |user|
      next if user.account_accesses.exists?(account_id: user.account_id)

      user.account_accesses.create!(
        account_id: user.account_id,
        role: 'account_admin'
      )
    end
  end

  def down
    remove_column :account_accesses, :role
  end
end
