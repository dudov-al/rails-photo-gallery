class CreateGalleries < ActiveRecord::Migration[6.1]
  def change
    create_table :galleries do |t|
      t.references :photographer, null: false, foreign_key: true
      t.string :title, null: false
      t.string :slug, null: false
      t.text :description
      t.string :password_digest
      t.datetime :expires_at
      t.boolean :published, default: false
      t.boolean :allow_downloads, default: true
      t.integer :images_count, default: 0
      t.integer :views_count, default: 0
      t.timestamps
    end
    
    add_index :galleries, :slug, unique: true
    add_index :galleries, :photographer_id
    add_index :galleries, :published
    add_index :galleries, :expires_at
    add_index :galleries, [:photographer_id, :published]
  end
end