class ImageProcessingJob < ApplicationJob
  queue_as :image_processing
  retry_on StandardError, wait: :exponentially_longer, attempts: 3
  discard_on ActiveRecord::RecordNotFound
  
  def perform(image_id)
    @image = Image.find(image_id)
    
    Rails.logger.info "Starting image processing for Image ID: #{image_id}"
    
    @image.update!(
      processing_status: :processing,
      processing_started_at: Time.current
    )
    
    # Process each variant
    variants_generated = {}
    
    Image::VARIANT_CONFIGS.each do |variant_name, config|
      begin
        process_variant(variant_name, config)
        variants_generated[variant_name] = {
          status: 'completed',
          generated_at: Time.current.iso8601,
          url: generate_variant_url(variant_name)
        }
      rescue => e
        Rails.logger.error "Failed to process variant #{variant_name}: #{e.message}"
        variants_generated[variant_name] = {
          status: 'failed',
          error: e.message,
          failed_at: Time.current.iso8601
        }
      end
    end
    
    # Update processing status
    all_variants_success = variants_generated.values.all? { |v| v[:status] == 'completed' }
    
    @image.update!(
      processing_status: all_variants_success ? :completed : :failed,
      processing_completed_at: Time.current,
      variants_generated: variants_generated,
      processing_errors: all_variants_success ? nil : extract_errors(variants_generated)
    )
    
    Rails.logger.info "Completed image processing for Image ID: #{image_id} - Status: #{@image.processing_status}"
    
    # Send notification if all variants completed successfully
    if all_variants_success
      # TODO: Add notification system for completed processing
      Rails.logger.info "All variants generated successfully for Image ID: #{image_id}"
    end
    
  rescue => e
    Rails.logger.error "Image processing job failed for Image ID: #{image_id} - #{e.message}"
    @image&.update!(
      processing_status: :failed,
      processing_errors: e.message,
      processing_completed_at: Time.current
    )
    raise e
  end
  
  private
  
  def process_variant(variant_name, config)
    # Generate variant using image_processing gem with libvips
    variant_blob = @image.file.variant(
      resize_to_limit: config[:resize_to_limit],
      format: config[:format],
      quality: config[:quality],
      strip: true,      # Remove EXIF data for privacy and smaller file size
      interlace: true   # Progressive JPEG/WebP for better loading
    ).processed
    
    Rails.logger.info "Generated #{variant_name} variant for Image ID: #{@image.id}"
    
    # Store processed variant
    # In a real implementation, this would upload to the appropriate storage tier
    # For now, we're using Rails' built-in variant system which handles storage automatically
    variant_blob
  end
  
  def generate_variant_url(variant_name)
    # Generate a URL for the processed variant
    # In production, this would be a direct URL to the stored variant in Vercel Blob
    # For now, using Rails variant URL system
    begin
      variant_config = Image::VARIANT_CONFIGS[variant_name]
      variant = @image.file.variant(
        resize_to_limit: variant_config[:resize_to_limit],
        format: variant_config[:format],
        quality: variant_config[:quality]
      )
      Rails.application.routes.url_helpers.rails_representation_url(variant)
    rescue => e
      Rails.logger.error "Failed to generate variant URL for #{variant_name}: #{e.message}"
      nil
    end
  end
  
  def extract_errors(variants_generated)
    failed_variants = variants_generated.select { |_, v| v[:status] == 'failed' }
    failed_variants.map { |name, data| "#{name}: #{data[:error]}" }.join('; ')
  end
end