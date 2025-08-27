# High-Volume Image Processing Architecture
## Scalable Solution for Original Storage + Multi-Variant Processing

---

## Overview

This document outlines the architecture for handling high-volume image processing while maintaining original files for client downloads. The solution is optimized for Vercel deployment with cost-effective storage tiers and scalable background processing.

---

## I. Architecture Overview

### Core Components
```
[Upload] → [Original Storage] → [Background Queue] → [Variant Processing] → [Tiered Storage]
    ↓              ↓                    ↓                   ↓              ↓
[Client]    [Vercel Blob Cold]    [Sidekiq/Redis]    [libvips/Rails]  [Vercel Blob Hot]
```

### Design Principles
- **Original Preservation**: Always store original files for high-quality downloads
- **Lazy Processing**: Generate variants in background to avoid upload delays
- **Tiered Storage**: Use appropriate storage tiers for access patterns
- **Progressive Enhancement**: Start with basic processing, add complexity as needed

---

## II. Storage Architecture

### 2.1 Multi-Tier Storage Strategy

**Tier 1: Cold Storage (Originals)**
```ruby
# Original files - rarely accessed, cost-optimized
class Image < ApplicationRecord
  has_one_attached :original_file
  
  def original_download_url
    # Generate signed URL for direct download
    original_file.blob.signed_url(expires_in: 1.hour)
  end
end
```

**Tier 2: Hot Storage (Web Variants)**
```ruby
# Frequently accessed variants - performance optimized
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
}
```

### 2.2 Storage Configuration

**Vercel Blob Configuration:**
```ruby
# config/storage.yml
production:
  vercel_blob_hot:
    service: VercelBlob
    access_token: <%= ENV['BLOB_READ_WRITE_TOKEN'] %>
    tier: 'hot'
    
  vercel_blob_cold:
    service: VercelBlob
    access_token: <%= ENV['BLOB_READ_WRITE_TOKEN'] %>
    tier: 'cold'

# config/environments/production.rb
config.active_storage.variant_processor = :vips  # Faster than mini_magick
```

---

## III. Database Schema Enhancement

### 3.1 Enhanced Image Model

```ruby
# Migration: Add processing status and metadata
class AddProcessingToImages < ActiveRecord::Migration[7.0]
  def change
    add_column :images, :processing_status, :integer, default: 0
    add_column :images, :file_size, :bigint
    add_column :images, :dimensions, :string  # "1920x1080"
    add_column :images, :format, :string      # "jpeg", "png", etc.
    add_column :images, :variants_generated, :json, default: {}
    add_column :images, :processing_errors, :text
    add_column :images, :processing_started_at, :datetime
    add_column :images, :processing_completed_at, :datetime
    
    add_index :images, :processing_status
    add_index :images, :processing_started_at
  end
end
```

### 3.2 Updated Image Model

```ruby
class Image < ApplicationRecord
  belongs_to :gallery
  has_one_attached :original_file
  
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
  validates :file_size, presence: true, numericality: { greater_than: 0 }
  validates :format, presence: true, inclusion: { in: %w[jpeg jpg png webp avif] }
  
  # Scopes
  scope :processing_incomplete, -> { where.not(processing_status: :completed) }
  scope :processing_failed, -> { where(processing_status: [:failed, :retrying]) }
  scope :by_size, ->(size) { order(:file_size) }
  
  # Callbacks
  after_create :extract_metadata
  after_create :enqueue_processing
  
  private
  
  def extract_metadata
    return unless original_file.attached?
    
    blob = original_file.blob
    self.file_size = blob.byte_size
    self.format = blob.content_type&.split('/')&.last || 'unknown'
    
    # Extract dimensions using image_processing
    if blob.image?
      begin
        metadata = original_file.analyze
        if metadata[:width] && metadata[:height]
          self.dimensions = "#{metadata[:width]}x#{metadata[:height]}"
        end
      rescue => e
        Rails.logger.error "Failed to extract image dimensions: #{e.message}"
      end
    end
    
    save!
  end
  
  def enqueue_processing
    ImageProcessingJob.perform_later(id)
  end
end
```

---

## IV. Background Processing System

### 4.1 Processing Job Implementation

```ruby
class ImageProcessingJob < ApplicationJob
  queue_as :image_processing
  retry_on StandardError, wait: :exponentially_longer, attempts: 3
  
  def perform(image_id)
    @image = Image.find(image_id)
    
    Rails.logger.info "Starting image processing for Image ID: #{image_id}"
    
    @image.update!(
      processing_status: :processing,
      processing_started_at: Time.current
    )
    
    # Process each variant
    variants_generated = {}
    
    VARIANT_CONFIGS.each do |variant_name, config|
      begin
        process_variant(variant_name, config)
        variants_generated[variant_name] = {
          status: 'completed',
          generated_at: Time.current.iso8601
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
    # Generate variant using image_processing gem
    variant_blob = @image.original_file.variant(
      resize_to_limit: config[:resize_to_limit],
      format: config[:format],
      quality: config[:quality]
    ).processed
    
    # Store in appropriate tier
    storage_service = config[:storage] == :hot ? :vercel_blob_hot : :vercel_blob_cold
    
    # Upload to Vercel Blob
    variant_key = generate_variant_key(variant_name)
    upload_variant_to_blob(variant_blob, variant_key, storage_service)
    
    Rails.logger.info "Generated #{variant_name} variant for Image ID: #{@image.id}"
  end
  
  def generate_variant_key(variant_name)
    "variants/#{@image.gallery.slug}/#{@image.id}/#{variant_name}.webp"
  end
  
  def upload_variant_to_blob(variant_blob, key, storage_service)
    # Implementation depends on Vercel Blob SDK integration
    # This would be implemented based on the specific Vercel Blob API
    # For now, this is a placeholder for the actual upload logic
  end
  
  def extract_errors(variants_generated)
    failed_variants = variants_generated.select { |_, v| v[:status] == 'failed' }
    failed_variants.map { |name, data| "#{name}: #{data[:error]}" }.join('; ')
  end
end
```

### 4.2 Queue Configuration

```ruby
# config/application.rb
config.active_job.queue_adapter = :sidekiq

# config/schedule.rb (for whenever gem)
every 1.hour do
  runner "ImageProcessingCleanupJob.perform_later"
end

# Sidekiq configuration
# config/initializers/sidekiq.rb
Sidekiq.configure_server do |config|
  config.redis = { url: ENV['REDIS_URL'] || 'redis://localhost:6379/0' }
end

Sidekiq.configure_client do |config|
  config.redis = { url: ENV['REDIS_URL'] || 'redis://localhost:6379/0' }
end

# config/routes.rb
require 'sidekiq/web'
mount Sidekiq::Web => '/sidekiq' if Rails.env.development?
```

---

## V. Upload Optimization Strategy

### 5.1 Client-Side Upload Enhancement

```javascript
// app/javascript/controllers/optimized_upload_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "preview", "progress", "error"]
  static values = { maxSize: Number, allowedTypes: Array, compressionQuality: Number }
  
  async upload(event) {
    const files = Array.from(event.target.files)
    
    for (const file of files) {
      try {
        // Validate file
        this.validateFile(file)
        
        // Compress image if needed
        const processedFile = await this.processImage(file)
        
        // Upload with progress tracking
        await this.uploadFile(processedFile)
        
      } catch (error) {
        this.showError(error.message)
      }
    }
  }
  
  validateFile(file) {
    if (file.size > this.maxSizeValue) {
      throw new Error(`File ${file.name} is too large. Maximum size is ${this.maxSizeValue / 1024 / 1024}MB`)
    }
    
    if (!this.allowedTypesValue.includes(file.type)) {
      throw new Error(`File type ${file.type} is not allowed`)
    }
  }
  
  async processImage(file) {
    return new Promise((resolve, reject) => {
      const canvas = document.createElement('canvas')
      const ctx = canvas.getContext('2d')
      const img = new Image()
      
      img.onload = () => {
        // Calculate optimal dimensions
        const { width, height } = this.calculateOptimalSize(img.width, img.height)
        
        canvas.width = width
        canvas.height = height
        
        // Draw and compress
        ctx.drawImage(img, 0, 0, width, height)
        
        canvas.toBlob((blob) => {
          resolve(new File([blob], file.name, { type: 'image/jpeg' }))
        }, 'image/jpeg', this.compressionQualityValue)
      }
      
      img.onerror = reject
      img.src = URL.createObjectURL(file)
    })
  }
  
  calculateOptimalSize(originalWidth, originalHeight) {
    const maxWidth = 2048
    const maxHeight = 2048
    
    if (originalWidth <= maxWidth && originalHeight <= maxHeight) {
      return { width: originalWidth, height: originalHeight }
    }
    
    const aspectRatio = originalWidth / originalHeight
    
    if (originalWidth > originalHeight) {
      return { width: maxWidth, height: Math.round(maxWidth / aspectRatio) }
    } else {
      return { width: Math.round(maxHeight * aspectRatio), height: maxHeight }
    }
  }
  
  async uploadFile(file) {
    const formData = new FormData()
    formData.append('image[file]', file)
    formData.append('image[gallery_id]', this.data.get('gallery-id'))
    
    const response = await fetch('/images', {
      method: 'POST',
      body: formData,
      headers: {
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
      }
    })
    
    if (!response.ok) {
      throw new Error(`Upload failed: ${response.statusText}`)
    }
    
    const result = await response.json()
    this.updatePreview(result)
  }
}
```

### 5.2 Server-Side Upload Handling

```ruby
class ImagesController < ApplicationController
  before_action :authenticate_photographer!
  before_action :set_gallery
  
  def create
    @image = @gallery.images.build(image_params)
    
    if @image.save
      render json: {
        status: 'success',
        image: {
          id: @image.id,
          filename: @image.filename,
          processing_status: @image.processing_status,
          thumbnail_url: @image.processing_status == 'completed' ? variant_url(@image, :thumbnail) : nil
        }
      }
    else
      render json: {
        status: 'error',
        errors: @image.errors.full_messages
      }, status: :unprocessable_entity
    end
  end
  
  private
  
  def image_params
    params.require(:image).permit(:file, :gallery_id)
  end
  
  def set_gallery
    @gallery = current_photographer.galleries.find(params[:image][:gallery_id])
  end
  
  def variant_url(image, variant_name)
    # This would return the URL for the processed variant
    # Implementation depends on how variants are stored and accessed
    "/images/#{image.id}/variants/#{variant_name}"
  end
end
```

---

## VI. Performance & Scaling Considerations

### 6.1 Processing Performance

**Optimization Strategies:**
- **libvips over ImageMagick**: 3-10x faster processing
- **Parallel processing**: Process multiple variants concurrently
- **Memory management**: Stream processing for large files
- **Format optimization**: Use modern formats (WebP, AVIF) when supported

```ruby
# Optimized variant processing
class OptimizedImageProcessor
  def self.process_variants(image, configs)
    # Process variants in parallel threads
    threads = configs.map do |variant_name, config|
      Thread.new do
        process_single_variant(image, variant_name, config)
      end
    end
    
    # Wait for all variants to complete
    results = threads.map(&:value)
    
    # Handle any failures
    handle_processing_results(results)
  end
  
  private
  
  def self.process_single_variant(image, variant_name, config)
    Rails.logger.info "Processing #{variant_name} for image #{image.id}"
    start_time = Time.current
    
    begin
      # Use libvips for fast processing
      variant = image.original_file.variant(
        resize_to_limit: config[:resize_to_limit],
        format: config[:format],
        quality: config[:quality],
        strip: true,  # Remove EXIF data
        interlace: true  # Progressive JPEG
      )
      
      processed_blob = variant.processed
      duration = Time.current - start_time
      
      Rails.logger.info "Completed #{variant_name} in #{duration.round(2)}s"
      
      { variant_name: variant_name, status: :success, blob: processed_blob }
    rescue => e
      Rails.logger.error "Failed to process #{variant_name}: #{e.message}"
      { variant_name: variant_name, status: :error, error: e.message }
    end
  end
end
```

### 6.2 Storage Cost Optimization

**Cost Management Strategies:**
```ruby
class ImageStorageOptimizer
  # Automatic format selection based on image content
  def self.optimal_format(image_blob)
    return :webp if modern_browser_support?
    return :jpeg if image_blob.content_type.include?('jpeg')
    :png
  end
  
  # Intelligent quality settings based on image characteristics
  def self.optimal_quality(variant_type, image_dimensions)
    case variant_type
    when :thumbnail
      75  # Lower quality for small images
    when :web
      85  # Balanced quality for web display
    when :preview
      80  # Good quality for previews
    else
      90  # High quality for other uses
    end
  end
  
  # Storage tier selection
  def self.storage_tier(variant_type)
    case variant_type
    when :thumbnail, :web
      :hot   # Frequently accessed
    when :preview
      :warm  # Occasionally accessed
    else
      :cold  # Rarely accessed
    end
  end
end
```

### 6.3 Monitoring and Alerting

```ruby
# Job monitoring and metrics
class ImageProcessingJob < ApplicationJob
  around_perform do |job, block|
    start_time = Time.current
    
    begin
      block.call
      
      # Record success metrics
      ImageProcessingMetrics.record_success(
        image_id: job.arguments.first,
        duration: Time.current - start_time
      )
      
    rescue => e
      # Record failure metrics
      ImageProcessingMetrics.record_failure(
        image_id: job.arguments.first,
        error: e.message,
        duration: Time.current - start_time
      )
      
      raise e
    end
  end
end

class ImageProcessingMetrics
  def self.record_success(image_id:, duration:)
    Rails.logger.info "IMAGE_PROCESSING_SUCCESS image_id=#{image_id} duration=#{duration}"
    # Send to monitoring service (NewRelic, Datadog, etc.)
  end
  
  def self.record_failure(image_id:, error:, duration:)
    Rails.logger.error "IMAGE_PROCESSING_FAILURE image_id=#{image_id} error='#{error}' duration=#{duration}"
    # Send alert to monitoring service
  end
end
```

---

## VII. Deployment Considerations

### 7.1 Vercel-Specific Configuration

```json
// vercel.json
{
  "functions": {
    "app/jobs/**": {
      "maxDuration": 300
    }
  },
  "env": {
    "BLOB_READ_WRITE_TOKEN": "@blob-token",
    "REDIS_URL": "@redis-url"
  }
}
```

### 7.2 Environment Variables

```bash
# Production environment variables
BLOB_READ_WRITE_TOKEN=vercel_blob_xxx
REDIS_URL=redis://redis-provider-url
IMAGE_PROCESSING_QUEUE_SIZE=10
MAX_CONCURRENT_PROCESSING=5
IMAGE_PROCESSING_TIMEOUT=300
```

---

## VIII. Success Metrics

### Performance Targets
- **Upload Processing**: < 30 seconds for 10MB batch
- **Variant Generation**: < 5 minutes for full set
- **Storage Cost**: < $0.10 per GB per month
- **Processing Success Rate**: > 99%
- **Processing Queue Depth**: < 100 jobs

### Monitoring Dashboard
- Queue depth and processing times
- Storage usage by tier
- Processing success/failure rates
- Cost per image processed
- User experience metrics (upload success rate)

---

This architecture provides a scalable foundation for high-volume image processing while maintaining original files for downloads and optimizing costs through intelligent storage tiering.