class CreatePhotographers < ActiveRecord::Migration[6.1]
  def change
    create_table :photographers do |t|
      t.string :email, null: false
      t.string :password_digest, null: false
      t.string :name, null: false
      t.text :bio
      t.string :website
      t.string :phone
      t.boolean :active, default: true
      t.timestamps
    end
    
    add_index :photographers, :email, unique: true
    add_index :photographers, :active
  end
end