class PublicGalleriesController < ApplicationController
  layout 'public_gallery'
  
  before_action :find_gallery, only: [:show, :authenticate, :download, :download_all]
  before_action :check_gallery_access, only: [:show, :download_all]
  before_action :authenticate_gallery_password, only: [:show, :download_all], if: -> { @gallery.password_protected? }
  
  # Performance monitoring for critical actions
  around_action :performance_monitoring, only: [:show]

  def show
    # Optimized query with minimal database hits
    @images = @gallery.images
      .includes(file_attachment: [:blob, { variant_attachments: :blob }])
      .where(processing_status: :completed)
      .ordered
      .select(:id, :filename, :alt_text, :position, :processing_status, :gallery_id)
    
    # Batch increment views for better performance
    increment_gallery_views_async
    
    # Pre-generate URLs in batches to avoid N+1
    @images_data = build_optimized_images_data(@images)
    
    # Set performance headers
    set_performance_headers
    
    respond_to do |format|
      format.html { render_with_performance_hints }
      format.json { render json: { images: @images_data } }
    end
  end

  def authenticate
    if @gallery.authenticate_password(params[:password])
      session["gallery_#{@gallery.id}_authenticated"] = true
      redirect_to public_gallery_path(@gallery.slug), 
                  notice: "Welcome to #{@gallery.title}"
    else
      @error = "Incorrect password. Please try again."
      render :password_form, status: :unauthorized
    end
  end

  def download
    # Optimized image lookup with minimal fields
    @image = @gallery.images.select(:id, :filename).find(params[:image_id])
    
    # Log download for analytics (async to avoid blocking)
    log_download_async(@gallery, @image)
    
    # Generate signed URL for secure download
    download_url = @image.download_url
    redirect_to download_url, allow_other_host: true
  rescue ActiveRecord::RecordNotFound
    redirect_to public_gallery_path(@gallery.slug), 
                alert: "Image not found"
  end

  def download_all
    # Log bulk download for analytics (async)
    log_bulk_download_async(@gallery)
    
    respond_to do |format|
      format.html do
        flash[:notice] = "Bulk download feature coming soon\! Download individual images for now."
        redirect_to public_gallery_path(@gallery.slug)
      end
      format.json do
        # Batch generate download URLs efficiently
        download_urls = batch_generate_download_urls(@gallery.images)
        render json: { downloads: download_urls }
      end
    end
  end

  private

  def find_gallery
    # Optimized gallery lookup with minimal joins
    @gallery = Gallery.includes(:photographer)
      .published
      .not_expired
      .select(:id, :slug, :title, :description, :photographer_id, :views_count, :images_count, :created_at)
      .find_by\!(slug: params[:slug])
  rescue ActiveRecord::RecordNotFound
    render :not_found, status: :not_found
  end

  def check_gallery_access
    unless @gallery.viewable?
      if @gallery.expired?
        render :expired, status: :gone
      else
        render :not_found, status: :not_found
      end
    end
  end

  def authenticate_gallery_password
    return if session["gallery_#{@gallery.id}_authenticated"]
    
    render :password_form, status: :unauthorized
  end
  
  # Performance optimization methods
  
  def build_optimized_images_data(images)
    # Pre-generate all URLs in a single pass to avoid N+1
    images.map do |image|
      {
        id: image.id,
        filename: image.filename,
        thumbnail_url: optimized_thumbnail_url(image),
        web_url: optimized_web_url(image),
        download_url: download_image_path(@gallery.slug, image.id),
        alt_text: image.alt_text || "#{@gallery.title} - Photo #{image.position}"
      }
    end
  end
  
  def optimized_thumbnail_url(image)
    # Check for pre-generated variant first, fallback to on-demand
    if image.variant_generated?(:thumbnail)
      image.variant_url(:thumbnail)
    else
      # Use optimized parameters for better performance
      Rails.application.routes.url_helpers.rails_representation_path(
        image.thumbnail(size: [300, 300]), only_path: true
      )
    end
  end
  
  def optimized_web_url(image)
    # Check for pre-generated variant first, fallback to on-demand
    if image.variant_generated?(:web)
      image.variant_url(:web)
    else
      Rails.application.routes.url_helpers.rails_representation_path(
        image.web_size(size: [1200, 1200]), only_path: true
      )
    end
  end
  
  def increment_gallery_views_async
    # Use background job to avoid blocking the main request
    GalleryAnalyticsJob.perform_later(@gallery.id, 'view', request.remote_ip)
  end
  
  def log_download_async(gallery, image)
    GalleryAnalyticsJob.perform_later(gallery.id, 'download', request.remote_ip, image_id: image.id)
  end
  
  def log_bulk_download_async(gallery)
    GalleryAnalyticsJob.perform_later(gallery.id, 'bulk_download', request.remote_ip)
  end
  
  def batch_generate_download_urls(images)
    # Generate all URLs efficiently without individual queries
    images.select(:id, :filename).map do |image|
      {
        filename: image.filename,
        url: download_image_path(@gallery.slug, image.id)
      }
    end
  end
  
  def set_performance_headers
    # Set appropriate caching headers for better performance
    expires_in 5.minutes, public: true
    response.headers['X-Gallery-Images'] = @images.size.to_s
    response.headers['X-Processing-Status'] = 'completed'
  end
  
  def render_with_performance_hints
    # Add resource hints for better loading performance
    response.headers['Link'] = build_resource_hints
    render :show
  end
  
  def build_resource_hints
    hints = []
    
    # Preload critical images (first 6 for above-the-fold)
    @images.limit(6).each do |image|
      hints << "<#{optimized_thumbnail_url(image)}>; rel=preload; as=image"
    end
    
    # Prefetch web-size images for faster lightbox loading
    @images.limit(3).each do |image|
      hints << "<#{optimized_web_url(image)}>; rel=prefetch; as=image"
    end
    
    hints.join(', ')
  end
  
  def performance_monitoring
    start_time = Time.current
    yield
  ensure
    duration = Time.current - start_time
    Rails.logger.info "PublicGalleries#show completed in #{(duration * 1000).round(2)}ms"
    
    # Log slow requests for monitoring
    if duration > 1.0
      Rails.logger.warn "Slow request: PublicGalleries#show took #{duration}s for gallery #{@gallery&.slug}"
    end
  end
end
EOF < /dev/null