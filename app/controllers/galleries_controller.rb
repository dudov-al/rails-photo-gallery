class GalleriesController < ApplicationController
  before_action :authenticate_photographer!
  before_action :set_gallery, only: [:edit, :update, :destroy, :reorder_images]
  before_action :rate_limit_gallery_creation, only: [:create]
  
  # GET /galleries
  def index
    # Build query with filters
    scope = current_photographer.galleries.includes(:images)
    
    # Apply filters based on params
    case params[:filter]
    when 'published'
      scope = scope.published
    when 'unpublished'
      scope = scope.where(published: false)
    when 'expired'
      scope = scope.where('expires_at IS NOT NULL AND expires_at < ?', Time.current)
    when 'password_protected'
      scope = scope.where.not(password_digest: nil)
    when 'featured'
      scope = scope.featured
    end
    
    # Search functionality
    if params[:search].present?
      sanitized_search = InputSanitizer.sanitize_search_term(params[:search])
      scope = scope.where('title ILIKE ? OR description ILIKE ?', 
                         "%#{sanitized_search}%", "%#{sanitized_search}%")
    end
    
    # Sorting
    case params[:sort]
    when 'title'
      scope = scope.order(:title)
    when 'created_desc'
      scope = scope.order(created_at: :desc)
    when 'created_asc'
      scope = scope.order(created_at: :asc)
    when 'views'
      scope = scope.order(views_count: :desc)
    when 'images_count'
      scope = scope.left_joins(:images).group(:id).order('COUNT(images.id) DESC')
    else
      scope = scope.order(updated_at: :desc) # Default sort
    end
    
    # Pagination
    @pagy, @galleries = pagy(scope, items: 12)
    
    # Gallery statistics for dashboard
    @stats = {
      total_galleries: current_photographer.galleries.count,
      published_galleries: current_photographer.galleries.published.count,
      total_images: current_photographer.galleries.joins(:images).count,
      total_views: current_photographer.galleries.sum(:views_count),
      featured_galleries: current_photographer.galleries.featured.count,
      password_protected_galleries: current_photographer.galleries.where.not(password_digest: nil).count
    }
    
    # Recent activity for dashboard
    @recent_galleries = current_photographer.galleries
                                          .order(updated_at: :desc)
                                          .limit(5)
                                          .includes(:images)
  end
  
  # GET /galleries/new
  def new
    @gallery = current_photographer.galleries.build
    
    # Set default values
    @gallery.published = false
    @gallery.featured = false
    
    # Pre-populate from params if coming from a template or duplicate
    if params[:template_id].present?
      template = current_photographer.galleries.find_by(id: params[:template_id])
      if template
        @gallery.assign_attributes(
          title: "Copy of #{template.title}",
          description: template.description,
          published: false,
          featured: false,
          password: nil # Don't copy passwords
        )
      end
    end
  end
  
  # POST /galleries
  def create
    @gallery = current_photographer.galleries.build(gallery_params)
    
    # Security: Clear any potentially malicious content
    @gallery.title = InputSanitizer.sanitize_text(@gallery.title)
    @gallery.description = InputSanitizer.sanitize_html(@gallery.description) if @gallery.description.present?
    
    if @gallery.save
      # Log successful gallery creation
      SecurityAuditLogger.log(
        event_type: 'gallery_created',
        photographer_id: current_photographer.id,
        ip_address: request.remote_ip,
        additional_data: {
          gallery_id: @gallery.id,
          gallery_slug: @gallery.slug,
          published: @gallery.published?,
          password_protected: @gallery.password_protected?
        }
      )
      
      # Determine redirect based on action taken
      if params[:commit] == 'Create and Add Images'
        redirect_to new_gallery_image_path(@gallery), 
                   notice: 'Gallery created successfully. Now add some images!'
      else
        redirect_to galleries_path, 
                   notice: "Gallery '#{@gallery.title}' was created successfully."
      end
    else
      # Log failed gallery creation attempt
      SecurityAuditLogger.log(
        event_type: 'gallery_creation_failed',
        photographer_id: current_photographer.id,
        ip_address: request.remote_ip,
        additional_data: {
          errors: @gallery.errors.full_messages,
          attempted_title: params.dig(:gallery, :title)
        }
      )
      
      render :new, status: :unprocessable_entity
    end
  end
  
  # GET /galleries/:id/edit
  def edit
    # Pre-populate password field indicator
    @has_password = @gallery.password_protected?
    @password_strength = @gallery.password_strength_text if @gallery.password.present?
  end
  
  # PATCH/PUT /galleries/:id
  def update
    # Handle password update logic
    gallery_update_params = gallery_params.dup
    
    # If password is being cleared
    if gallery_update_params[:password].blank? && gallery_update_params[:password_confirmation].blank?
      if params[:clear_password] == '1'
        gallery_update_params[:password] = nil
        gallery_update_params[:password_confirmation] = nil
      else
        # Don't change password if fields are empty and not explicitly clearing
        gallery_update_params.delete(:password)
        gallery_update_params.delete(:password_confirmation)
      end
    end
    
    # Sanitize input
    gallery_update_params[:title] = InputSanitizer.sanitize_text(gallery_update_params[:title]) if gallery_update_params[:title]
    gallery_update_params[:description] = InputSanitizer.sanitize_html(gallery_update_params[:description]) if gallery_update_params[:description]
    
    # Track what's being changed for security logging
    changes = {}
    gallery_update_params.each do |key, value|
      if key != 'password' && key != 'password_confirmation' && @gallery.send(key) != value
        changes[key] = { from: @gallery.send(key), to: value }
      elsif key == 'password' && value.present?
        changes['password'] = 'updated'
      end
    end
    
    if @gallery.update(gallery_update_params)
      # Log successful gallery update
      SecurityAuditLogger.log(
        event_type: 'gallery_updated',
        photographer_id: current_photographer.id,
        ip_address: request.remote_ip,
        additional_data: {
          gallery_id: @gallery.id,
          gallery_slug: @gallery.slug,
          changes: changes
        }
      )
      
      redirect_to galleries_path, 
                 notice: "Gallery '#{@gallery.title}' was updated successfully."
    else
      # Log failed gallery update
      SecurityAuditLogger.log(
        event_type: 'gallery_update_failed',
        photographer_id: current_photographer.id,
        ip_address: request.remote_ip,
        additional_data: {
          gallery_id: @gallery.id,
          errors: @gallery.errors.full_messages,
          attempted_changes: changes
        }
      )
      
      @has_password = @gallery.password_protected?
      render :edit, status: :unprocessable_entity
    end
  end
  
  # DELETE /galleries/:id
  def destroy
    # Security check - only allow deletion with confirmation
    unless params[:confirm_delete] == @gallery.slug
      redirect_to galleries_path, 
                 alert: 'Gallery deletion cancelled. Confirmation slug did not match.'
      return
    end
    
    # Store info for logging before destruction
    gallery_info = {
      id: @gallery.id,
      slug: @gallery.slug,
      title: @gallery.title,
      images_count: @gallery.images.count,
      published: @gallery.published?
    }
    
    # Perform destruction in transaction for safety
    begin
      ActiveRecord::Base.transaction do
        # First, destroy all associated images (this will handle file cleanup)
        @gallery.images.destroy_all
        
        # Then destroy the gallery
        @gallery.destroy!
        
        # Log successful gallery deletion
        SecurityAuditLogger.log(
          event_type: 'gallery_deleted',
          photographer_id: current_photographer.id,
          ip_address: request.remote_ip,
          additional_data: gallery_info
        )
        
        redirect_to galleries_path, 
                   notice: "Gallery '#{gallery_info[:title]}' and all its images have been deleted."
      end
    rescue ActiveRecord::RecordNotDestroyed => e
      # Log failed deletion
      SecurityAuditLogger.log(
        event_type: 'gallery_deletion_failed',
        photographer_id: current_photographer.id,
        ip_address: request.remote_ip,
        additional_data: {
          gallery_info: gallery_info,
          error: e.message
        }
      )
      
      redirect_to galleries_path, 
                 alert: 'Failed to delete gallery. Please try again.'
    end
  end
  
  # PATCH /galleries/:id/reorder_images
  def reorder_images
    # Validate that image_ids belong to this gallery
    image_ids = params.require(:image_ids)
    gallery_image_ids = @gallery.images.pluck(:id).map(&:to_s)
    
    unless (image_ids - gallery_image_ids).empty?
      render json: { 
        status: 'error', 
        errors: ['One or more images do not belong to this gallery'] 
      }, status: :forbidden
      return
    end
    
    # Update positions
    ActiveRecord::Base.transaction do
      image_ids.each_with_index do |image_id, index|
        @gallery.images.find(image_id).update_column(:position, index + 1)
      end
    end
    
    # Log reordering action
    SecurityAuditLogger.log(
      event_type: 'gallery_images_reordered',
      photographer_id: current_photographer.id,
      ip_address: request.remote_ip,
      additional_data: {
        gallery_id: @gallery.id,
        gallery_slug: @gallery.slug,
        image_count: image_ids.length
      }
    )
    
    if request.xhr?
      render json: { 
        status: 'success', 
        message: 'Images reordered successfully' 
      }
    else
      redirect_to edit_gallery_path(@gallery), 
                 notice: 'Images reordered successfully.'
    end
  rescue ActiveRecord::RecordNotFound => e
    render json: { 
      status: 'error', 
      errors: ['One or more images not found'] 
    }, status: :not_found
  end
  
  # POST /galleries/:id/duplicate
  def duplicate
    source_gallery = current_photographer.galleries.find(params[:id])
    
    new_gallery = source_gallery.dup
    new_gallery.title = "Copy of #{source_gallery.title}"
    new_gallery.slug = nil # Will be regenerated
    new_gallery.published = false
    new_gallery.featured = false
    new_gallery.password = nil # Don't copy passwords
    new_gallery.password_confirmation = nil
    new_gallery.views_count = 0
    
    if new_gallery.save
      # Log gallery duplication
      SecurityAuditLogger.log(
        event_type: 'gallery_duplicated',
        photographer_id: current_photographer.id,
        ip_address: request.remote_ip,
        additional_data: {
          source_gallery_id: source_gallery.id,
          new_gallery_id: new_gallery.id,
          source_slug: source_gallery.slug,
          new_slug: new_gallery.slug
        }
      )
      
      redirect_to edit_gallery_path(new_gallery), 
                 notice: 'Gallery duplicated successfully. You can now customize it.'
    else
      redirect_to galleries_path, 
                 alert: 'Failed to duplicate gallery.'
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to galleries_path, alert: 'Gallery not found.'
  end
  
  private
  
  def set_gallery
    @gallery = current_photographer.galleries.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    # Log unauthorized access attempt
    SecurityAuditLogger.log(
      event_type: 'unauthorized_gallery_access',
      photographer_id: current_photographer&.id,
      ip_address: request.remote_ip,
      additional_data: {
        requested_gallery_id: params[:id],
        action: action_name
      }
    )
    
    redirect_to galleries_path, alert: 'Gallery not found or access denied.'
  end
  
  def gallery_params
    params.require(:gallery).permit(
      :title, :description, :published, :featured, :expires_at,
      :password, :password_confirmation, :allow_downloads, :watermark_enabled
    )
  end
  
  def rate_limit_gallery_creation
    # Check rate limiting for gallery creation
    cache_key = "gallery_creation:#{current_photographer.id}"
    creation_count = Rails.cache.read(cache_key) || 0
    
    # Allow 10 galleries per hour
    if creation_count >= 10
      SecurityAuditLogger.log(
        event_type: 'gallery_creation_rate_limited',
        photographer_id: current_photographer.id,
        ip_address: request.remote_ip,
        additional_data: { creation_count: creation_count }
      )
      
      redirect_to galleries_path, 
                 alert: 'Too many galleries created recently. Please wait before creating more.'
      return
    end
    
    # Increment counter
    Rails.cache.write(cache_key, creation_count + 1, expires_in: 1.hour)
  end
end