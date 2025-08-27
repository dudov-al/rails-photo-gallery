class AddSecurityFieldsToPhotographers < ActiveRecord::Migration[7.0]
  def change
    add_column :photographers, :failed_attempts, :integer, default: 0, null: false
    add_column :photographers, :locked_until, :datetime
    add_column :photographers, :last_failed_attempt, :datetime
    add_column :photographers, :last_login_at, :datetime
    add_column :photographers, :last_login_ip, :string
    
    add_index :photographers, :locked_until
    add_index :photographers, :last_login_at
    add_index :photographers, :failed_attempts
  end
end