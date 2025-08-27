class AddProcessingToImages < ActiveRecord::Migration[6.1]
  def change
    add_column :images, :processing_status, :integer, default: 0
    add_column :images, :format, :string      # "jpeg", "png", etc.
    add_column :images, :variants_generated, :json, default: {}
    add_column :images, :processing_errors, :text
    add_column :images, :processing_started_at, :datetime
    add_column :images, :processing_completed_at, :datetime
    add_column :images, :alt_text, :text
    add_column :images, :description, :text
    
    add_index :images, :processing_status
    add_index :images, :processing_started_at
    add_index :images, :format
  end
end