class Image < ApplicationRecord
  # Active Storage attachments
  has_one_attached :file
  
  # Associations
  belongs_to :gallery
  
  # Processing status enum
  enum processing_status: {
    pending: 0,      # Upload complete, processing queued
    processing: 1,   # Currently generating variants
    completed: 2,    # All variants generated successfully
    failed: 3,       # Processing failed
    retrying: 4      # Retrying after failure
  }
  
  # Validations
  validates :filename, presence: true
  validates :file, presence: true
  validates :format, presence: true, inclusion: { in: %w[jpeg jpg png webp avif gif heic heif] }
  validate :acceptable_file_format
  validate :acceptable_file_size
  
  # Callbacks
  before_save :extract_metadata
  after_create :enqueue_processing
  after_create :update_gallery_images_count
  after_destroy :update_gallery_images_count
  
  # Scopes
  scope :ordered, -> { order(:position, :created_at) }
  scope :by_content_type, ->(type) { where(content_type: type) }
  scope :processing_incomplete, -> { where.not(processing_status: :completed) }
  scope :processing_failed, -> { where(processing_status: [:failed, :retrying]) }
  scope :by_size, ->(size) { order(:file_size) }
  
  # Variant configurations for different storage tiers
  VARIANT_CONFIGS = {
    thumbnail: { 
      resize_to_limit: [300, 300], 
      format: :webp, 
      quality: 85,
      storage: :hot 
    },
    web: { 
      resize_to_limit: [1200, 1200], 
      format: :webp, 
      quality: 90,
      storage: :hot 
    },
    preview: { 
      resize_to_limit: [800, 600], 
      format: :webp, 
      quality: 85,
      storage: :hot 
    }
  }.freeze
  
  # Image variants for different display sizes
  def thumbnail(size: [300, 300])
    return variant_url(:thumbnail) if variant_generated?(:thumbnail)
    file.variant(resize_to_limit: size, format: :webp, quality: 85)
  end
  
  def web_size(size: [1200, 1200])
    return variant_url(:web) if variant_generated?(:web)
    file.variant(resize_to_limit: size, format: :webp, quality: 90)
  end
  
  def preview_size(size: [800, 600])
    return variant_url(:preview) if variant_generated?(:preview)
    file.variant(resize_to_limit: size, format: :webp, quality: 85)
  end
  
  def original_file
    file
  end
  
  # Generate signed URL for secure downloads
  def download_url
    file.blob.signed_url(expires_in: 1.hour, disposition: "attachment")
  end
  
  def thumbnail_url
    return variant_url(:thumbnail) if variant_generated?(:thumbnail)
    Rails.application.routes.url_helpers.rails_representation_path(thumbnail, only_path: true)
  end
  
  def web_url
    return variant_url(:web) if variant_generated?(:web)
    Rails.application.routes.url_helpers.rails_representation_path(web_size, only_path: true)
  end
  
  def preview_url
    return variant_url(:preview) if variant_generated?(:preview)
    Rails.application.routes.url_helpers.rails_representation_path(preview_size, only_path: true)
  end
  
  # Variant management methods
  def variant_generated?(variant_name)
    variants_generated.dig(variant_name.to_s, 'status') == 'completed'
  end
  
  def variant_url(variant_name)
    # This would return the direct URL to the processed variant stored in Vercel Blob
    # For now, returning a placeholder that would be implemented with actual Blob URLs
    variants_generated.dig(variant_name.to_s, 'url')
  end
  
  def variants_complete?
    VARIANT_CONFIGS.keys.all? { |variant_name| variant_generated?(variant_name) }
  end
  
  def processing_duration
    return nil unless processing_started_at && processing_completed_at
    processing_completed_at - processing_started_at
  end
  
  # File information helpers
  def file_extension
    File.extname(filename).downcase
  end
  
  def human_file_size
    return '0 Bytes' if file_size.nil? || file_size.zero?
    
    units = ['Bytes', 'KB', 'MB', 'GB']
    size = file_size.to_f
    unit_index = 0
    
    while size >= 1024 && unit_index < units.length - 1
      size /= 1024.0
      unit_index += 1
    end
    
    "#{size.round(1)} #{units[unit_index]}"
  end
  
  private
  
  def acceptable_file_format
    return unless file.attached?
    
    acceptable_types = %w[image/jpeg image/jpg image/png image/gif image/webp image/heic image/heif]
    unless acceptable_types.include?(file.content_type)
      errors.add(:file, 'must be a valid image format (JPEG, PNG, GIF, WebP, HEIC, HEIF)')
    end
  end
  
  def acceptable_file_size
    return unless file.attached?
    
    max_size = 50.megabytes
    if file.byte_size > max_size
      errors.add(:file, "must be less than #{max_size / 1.megabyte}MB")
    end
  end
  
  def extract_metadata
    return unless file.attached?
    
    blob = file.blob
    self.content_type = blob.content_type
    self.file_size = blob.byte_size
    self.format = blob.content_type&.split('/')&.last || 'unknown'
    
    # Extract dimensions using image_processing
    if blob.image?
      begin
        metadata = file.analyze
        if metadata[:width] && metadata[:height]
          self.width = metadata[:width]
          self.height = metadata[:height]
          self.metadata = metadata
        end
      rescue => e
        Rails.logger.error "Failed to extract image dimensions for #{id}: #{e.message}"
      end
    end
    
    self.filename = file.filename.to_s if filename.blank?
  end
  
  def enqueue_processing
    ImageProcessingJob.perform_later(id)
  end
  
  def update_gallery_images_count
    gallery.update_column(:images_count, gallery.images.count)
  end
end