class CreateImages < ActiveRecord::Migration[6.1]
  def change
    create_table :images do |t|
      t.references :gallery, null: false, foreign_key: true
      t.string :filename, null: false
      t.text :caption
      t.integer :position, default: 0
      t.bigint :file_size
      t.string :content_type
      t.integer :width
      t.integer :height
      t.json :metadata
      t.timestamps
    end
    
    add_index :images, :gallery_id
    add_index :images, [:gallery_id, :position]
    add_index :images, :filename
    add_index :images, :content_type
  end
end