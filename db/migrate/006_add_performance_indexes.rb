class AddPerformanceIndexes < ActiveRecord::Migration[6.1]
  def change
    # Gallery performance indexes
    add_index :galleries, :views_count, order: { views_count: :desc }
    add_index :galleries, [:published, :expires_at], where: 'published = true'
    add_index :galleries, [:photographer_id, :views_count], order: { views_count: :desc }
    
    # Image performance indexes  
    add_index :images, [:gallery_id, :processing_status]
    add_index :images, [:processing_status, :processing_started_at]
    add_index :images, [:gallery_id, :position, :id]
    add_index :images, :file_size, order: { file_size: :desc }
    
    # Composite indexes for common queries
    add_index :images, [:gallery_id, :processing_status, :position], 
              name: 'idx_images_gallery_status_position'
  end
end
