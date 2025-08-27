class ImagesController < ApplicationController
  before_action :authenticate_photographer!
  before_action :set_gallery
  before_action :set_image, only: [:show, :update, :destroy]
  
  # POST /galleries/:gallery_id/images
  def create
    # Security validation before processing
    if params[:image] && params[:image][:file]
      validator = SecureFileValidator.new(params[:image][:file], current_photographer)
      
      unless validator.valid?
        # Log security violation
        SecurityAuditLogger.log(
          event_type: 'file_upload_blocked',
          photographer_id: current_photographer.id,
          ip_address: request.remote_ip,
          additional_data: validator.security_report
        )
        
        render json: {
          status: 'error',
          errors: validator.errors,
          warnings: validator.warnings,
          security_report: Rails.env.development? ? validator.security_report : nil
        }, status: :unprocessable_entity
        return
      end
      
      # Use sanitized file for processing
      sanitized_file = validator.sanitized_file
      if sanitized_file
        params[:image][:file] = sanitized_file
        
        # Log successful validation
        SecurityAuditLogger.log(
          event_type: 'file_upload_validated',
          photographer_id: current_photographer.id,
          ip_address: request.remote_ip,
          additional_data: {
            filename: sanitized_file.original_filename,
            file_size: sanitized_file.size,
            threat_level: validator.security_report[:threat_level]
          }
        )
      end
    end
    
    @image = @gallery.images.build(image_params)
    
    if @image.save
      render json: {
        status: 'success',
        image: {
          id: @image.id,
          filename: @image.filename,
          processing_status: @image.processing_status,
          thumbnail_url: @image.processing_status == 'completed' ? @image.thumbnail_url : nil,
          file_size: @image.human_file_size,
          dimensions: @image.metadata&.dig('width') && @image.metadata&.dig('height') ? 
                     "#{@image.metadata['width']}x#{@image.metadata['height']}" : nil
        }
      }
    else
      render json: {
        status: 'error',
        errors: @image.errors.full_messages
      }, status: :unprocessable_entity
    end
  end
  
  # GET /galleries/:gallery_id/images/:id
  def show
    render json: {
      image: {
        id: @image.id,
        filename: @image.filename,
        processing_status: @image.processing_status,
        thumbnail_url: @image.thumbnail_url,
        web_url: @image.web_url,
        preview_url: @image.preview_url,
        download_url: @image.download_url,
        file_size: @image.human_file_size,
        dimensions: @image.width && @image.height ? "#{@image.width}x#{@image.height}" : nil,
        alt_text: @image.alt_text,
        description: @image.description,
        position: @image.position,
        variants_generated: @image.variants_generated,
        processing_errors: @image.processing_errors,
        created_at: @image.created_at.iso8601
      }
    }
  end
  
  # PATCH/PUT /galleries/:gallery_id/images/:id
  def update
    if @image.update(image_update_params)
      render json: {
        status: 'success',
        image: {
          id: @image.id,
          filename: @image.filename,
          alt_text: @image.alt_text,
          description: @image.description,
          position: @image.position
        }
      }
    else
      render json: {
        status: 'error',
        errors: @image.errors.full_messages
      }, status: :unprocessable_entity
    end
  end
  
  # DELETE /galleries/:gallery_id/images/:id
  def destroy
    if @image.destroy
      render json: { status: 'success', message: 'Image deleted successfully' }
    else
      render json: { 
        status: 'error', 
        errors: ['Failed to delete image'] 
      }, status: :unprocessable_entity
    end
  end
  
  # PATCH /galleries/:gallery_id/images/reorder
  def reorder
    params.require(:image_ids).each_with_index do |image_id, index|
      @gallery.images.find(image_id).update_column(:position, index + 1)
    end
    
    render json: { status: 'success', message: 'Images reordered successfully' }
  rescue ActiveRecord::RecordNotFound => e
    render json: { 
      status: 'error', 
      errors: ['One or more images not found'] 
    }, status: :not_found
  end
  
  # DELETE /galleries/:gallery_id/images/bulk_destroy
  def bulk_destroy
    image_ids = params.require(:image_ids)
    images = @gallery.images.where(id: image_ids)
    
    if images.count != image_ids.count
      render json: { 
        status: 'error', 
        errors: ['One or more images not found'] 
      }, status: :not_found
      return
    end
    
    destroyed_count = images.destroy_all.count
    
    render json: { 
      status: 'success', 
      message: "#{destroyed_count} images deleted successfully",
      deleted_count: destroyed_count
    }
  end
  
  # GET /galleries/:gallery_id/images/processing_status
  def processing_status
    processing_images = @gallery.images.processing_incomplete
    
    render json: {
      processing_images: processing_images.map do |image|
        {
          id: image.id,
          filename: image.filename,
          processing_status: image.processing_status,
          processing_started_at: image.processing_started_at&.iso8601,
          variants_generated: image.variants_generated,
          processing_errors: image.processing_errors
        }
      end,
      total_processing: processing_images.count
    }
  end
  
  private
  
  def set_gallery
    @gallery = current_photographer.galleries.find(params[:gallery_id])
  rescue ActiveRecord::RecordNotFound
    render json: { 
      status: 'error', 
      errors: ['Gallery not found or access denied'] 
    }, status: :not_found
  end
  
  def set_image
    @image = @gallery.images.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { 
      status: 'error', 
      errors: ['Image not found'] 
    }, status: :not_found
  end
  
  def image_params
    params.require(:image).permit(:file, :alt_text, :description, :position)
  end
  
  def image_update_params
    params.require(:image).permit(:alt_text, :description, :position)
  end
end