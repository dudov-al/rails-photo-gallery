module ApplicationHelper
  # Check if current user is a photographer
  def photographer_signed_in?
    # This would be implemented based on your authentication system
    # For now, returning false as authentication isn't implemented yet
    false
  end

  def current_photographer
    # This would return the current photographer
    # Implementation depends on your authentication system
    nil
  end

  # Format file size in human readable format
  def human_file_size(size_in_bytes)
    return '0 Bytes' if size_in_bytes.nil? || size_in_bytes.zero?
    
    units = ['Bytes', 'KB', 'MB', 'GB', 'TB']
    size = size_in_bytes.to_f
    unit_index = 0
    
    while size >= 1024 && unit_index < units.length - 1
      size /= 1024.0
      unit_index += 1
    end
    
    "#{size.round(1)} #{units[unit_index]}"
  end

  # Generate responsive image srcset for different screen densities
  def responsive_image_srcset(image, variant_name)
    return '' unless image&.file&.attached?
    
    srcset_parts = []
    
    # Standard resolution
    if image.respond_to?(:variant_url) && image.variant_generated?(variant_name)
      srcset_parts << "#{image.variant_url(variant_name)} 1x"
    elsif image.respond_to?("#{variant_name}_url")
      srcset_parts << "#{image.send("#{variant_name}_url")} 1x"
    end
    
    # High resolution (2x) - if available
    high_res_variant = "#{variant_name}_2x".to_sym
    if image.respond_to?(:variant_url) && image.variant_generated?(high_res_variant)
      srcset_parts << "#{image.variant_url(high_res_variant)} 2x"
    end
    
    srcset_parts.join(', ')
  end

  # Generate structured data for image galleries
  def gallery_structured_data(gallery, images)
    {
      "@context": "https://schema.org",
      "@type": "ImageGallery",
      "name": gallery.title,
      "description": gallery.description,
      "creator": {
        "@type": "Person",
        "name": gallery.photographer.name
      },
      "dateCreated": gallery.created_at&.iso8601,
      "numberOfItems": images.count,
      "associatedMedia": images.map do |image|
        {
          "@type": "ImageObject",
          "name": image.filename,
          "contentUrl": image.respond_to?(:web_url) ? image.web_url : url_for(image.file),
          "thumbnailUrl": image.respond_to?(:thumbnail_url) ? image.thumbnail_url : url_for(image.file),
          "encodingFormat": image.content_type,
          "width": image.width,
          "height": image.height
        }
      end
    }.to_json.html_safe
  end

  # Check if we're on a public gallery page
  def public_gallery_page?
    controller_name == 'public_galleries'
  end

  # Generate page title with fallback
  def page_title(title = nil)
    base_title = "Photograph - Professional Photo Gallery Platform"
    return base_title unless title.present?
    "#{title} - Photograph"
  end

  # Generate meta description for SEO
  def meta_description(description = nil)
    default = "Professional photo gallery platform for photographers to showcase and share their work with clients."
    description.presence || default
  end
end