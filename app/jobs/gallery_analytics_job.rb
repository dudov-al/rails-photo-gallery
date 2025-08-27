class GalleryAnalyticsJob < ApplicationJob
  queue_as :analytics
  retry_on StandardError, wait: :exponentially_longer, attempts: 2
  discard_on ActiveRecord::RecordNotFound

  def perform(gallery_id, action_type, ip_address, **metadata)
    gallery = Gallery.find(gallery_id)
    
    case action_type
    when 'view'
      # Use atomic increment to avoid race conditions
      Gallery.where(id: gallery_id).update_all('views_count = views_count + 1')
      
    when 'download'
      # Log individual image download
      Rails.logger.info "Image download: Gallery #{gallery.slug}, Image #{metadata[:image_id]}, IP: #{ip_address}"
      
    when 'bulk_download'
      # Log bulk download
      Rails.logger.info "Bulk download: Gallery #{gallery.slug}, #{gallery.images_count} images, IP: #{ip_address}"
    end
    
    # Store analytics data for future reporting (optional)
    # GalleryAnalytics.create(
    #   gallery: gallery,
    #   action_type: action_type,
    #   ip_address: ip_address,
    #   metadata: metadata,
    #   timestamp: Time.current
    # )
    
  rescue => e
    Rails.logger.error "Gallery analytics job failed: #{e.message}"
    raise e
  end
end
EOF < /dev/null