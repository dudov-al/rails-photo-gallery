class SecureFileValidator
  # File validation service with comprehensive security checks
  
  # Magic numbers for file type validation
  ALLOWED_FILE_SIGNATURES = {
    'image/jpeg' => [
      [0xFF, 0xD8, 0xFF, 0xE0],  # JFIF JPEG
      [0xFF, 0xD8, 0xFF, 0xE1],  # EXIF JPEG
      [0xFF, 0xD8, 0xFF, 0xE2],  # ICC JPEG
      [0xFF, 0xD8, 0xFF, 0xE8],  # SPIFF JPEG
      [0xFF, 0xD8, 0xFF, 0xDB]   # JPEG raw
    ],
    'image/png' => [
      [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    ],
    'image/webp' => [
      [0x52, 0x49, 0x46, 0x46], # RIFF (followed by WEBP at bytes 8-11)
    ],
    'image/tiff' => [
      [0x49, 0x49, 0x2A, 0x00], # Little-endian TIFF
      [0x4D, 0x4D, 0x00, 0x2A]  # Big-endian TIFF
    ],
    'image/bmp' => [
      [0x42, 0x4D]              # BM
    ],
    'image/gif' => [
      [0x47, 0x49, 0x46, 0x38, 0x37, 0x61], # GIF87a
      [0x47, 0x49, 0x46, 0x38, 0x39, 0x61]  # GIF89a
    ]
  }.freeze
  
  ALLOWED_MIME_TYPES = ALLOWED_FILE_SIGNATURES.keys.freeze
  
  # File size limits (in bytes)
  MAX_FILE_SIZE = 50.megabytes
  MIN_FILE_SIZE = 1.kilobyte
  MAX_DIMENSION = 10000 # pixels
  MIN_DIMENSION = 32    # pixels
  
  # Dangerous file extensions to block
  DANGEROUS_EXTENSIONS = %w[
    exe com bat cmd scr pif vbs js jse wsf wsh
    php php3 php4 php5 phtml asp aspx jsp
    html htm svg xml xhtml
  ].freeze
  
  def initialize(file, user = nil)
    @file = file
    @user = user
    @errors = []
    @warnings = []
    @file_path = file.respond_to?(:tempfile) ? file.tempfile.path : file.path
  end
  
  def valid?
    validate_file_existence
    return false if @errors.any?
    
    validate_file_size
    validate_file_extension
    validate_mime_type
    validate_magic_numbers
    validate_image_properties
    validate_metadata_safety
    scan_for_malicious_content
    
    @errors.empty?
  end
  
  def sanitized_file
    return nil unless valid?
    
    begin
      # Create sanitized copy
      sanitized_path = sanitize_file
      
      # Return new file object
      File.open(sanitized_path, 'rb') do |sanitized_file|
        ActionDispatch::Http::UploadedFile.new(
          tempfile: sanitized_file,
          filename: sanitized_filename,
          type: detected_mime_type,
          head: @file.headers
        )
      end
    rescue => e
      @errors << "File sanitization failed: #{e.message}"
      log_security_event('file_sanitization_failed', { error: e.message })
      nil
    end
  end
  
  def errors
    @errors
  end
  
  def warnings
    @warnings
  end
  
  def security_report
    {
      filename: @file.original_filename,
      mime_type: @file.content_type,
      detected_mime_type: detected_mime_type,
      file_size: @file.size,
      magic_numbers: read_magic_numbers.first(8),
      validation_errors: @errors,
      warnings: @warnings,
      threat_level: calculate_threat_level
    }
  end
  
  private
  
  def validate_file_existence
    unless @file && @file_path && File.exist?(@file_path)
      @errors << "File does not exist or is not accessible"
      return false
    end
    true
  end
  
  def validate_file_size
    size = @file.size
    
    if size > MAX_FILE_SIZE
      @errors << "File size (#{size.to_f / 1.megabyte:.1f}MB) exceeds maximum allowed size (#{MAX_FILE_SIZE / 1.megabyte}MB)"
      log_security_event('file_size_exceeded')
    elsif size < MIN_FILE_SIZE
      @errors << "File size is too small (minimum #{MIN_FILE_SIZE} bytes)"
    end
  end
  
  def validate_file_extension
    filename = @file.original_filename.to_s.downcase
    
    # Check for dangerous extensions
    if DANGEROUS_EXTENSIONS.any? { |ext| filename.end_with?(".#{ext}") }
      @errors << "File extension is not allowed"
      log_security_event('dangerous_file_extension', { filename: filename })
      return
    end
    
    # Check for double extensions (e.g., image.jpg.exe)
    if filename.count('.') > 1
      @warnings << "File has multiple extensions"
    end
    
    # Check for allowed image extensions
    unless filename.match?(/\.(jpe?g|png|webp|tiff?|bmp|gif)$/i)
      @errors << "File extension must be jpg, jpeg, png, webp, tiff, bmp, or gif"
    end
  end
  
  def validate_mime_type
    declared_type = @file.content_type
    detected_type = detected_mime_type
    
    unless ALLOWED_MIME_TYPES.include?(declared_type)
      @errors << "MIME type '#{declared_type}' is not allowed"
      log_security_event('invalid_mime_type', { declared: declared_type, detected: detected_type })
    end
    
    if declared_type != detected_type
      @warnings << "Declared MIME type '#{declared_type}' doesn't match detected type '#{detected_type}'"
    end
  end
  
  def validate_magic_numbers
    magic_numbers = read_magic_numbers
    detected_type = detected_mime_type
    
    return if detected_type.nil?
    
    valid_signatures = ALLOWED_FILE_SIGNATURES[detected_type]
    return unless valid_signatures
    
    is_valid = valid_signatures.any? do |signature|
      if detected_type == 'image/webp'
        # Special handling for WebP: check RIFF header and WEBP signature
        magic_numbers[0, 4] == signature && 
        magic_numbers[8, 4] == [0x57, 0x45, 0x42, 0x50] # "WEBP"
      else
        magic_numbers[0, signature.length] == signature
      end
    end
    
    unless is_valid
      @errors << "File signature does not match declared type (possible file type mismatch or corruption)"
      log_security_event('invalid_file_signature', { 
        magic_numbers: magic_numbers.first(16),
        expected_type: detected_type 
      })
    end
  end
  
  def validate_image_properties
    return unless valid_image_file?
    
    begin
      image = MiniMagick::Image.new(@file_path)
      
      width = image.width
      height = image.height
      
      if width > MAX_DIMENSION || height > MAX_DIMENSION
        @errors << "Image dimensions (#{width}x#{height}) exceed maximum allowed (#{MAX_DIMENSION}x#{MAX_DIMENSION})"
      end
      
      if width < MIN_DIMENSION || height < MIN_DIMENSION
        @errors << "Image dimensions (#{width}x#{height}) are below minimum required (#{MIN_DIMENSION}x#{MIN_DIMENSION})"
      end
      
      # Check for unusual aspect ratios (potential steganography)
      aspect_ratio = width.to_f / height.to_f
      if aspect_ratio > 20 || aspect_ratio < 0.05
        @warnings << "Unusual aspect ratio detected (#{width}:#{height})"
      end
      
    rescue => e
      @errors << "Unable to read image properties: #{e.message}"
    end
  end
  
  def validate_metadata_safety
    return unless valid_image_file?
    
    begin
      # Check for excessive EXIF data (potential payload hiding)
      exif_data = MiniMagick::Image.new(@file_path).exif
      
      if exif_data.size > 100 # Arbitrarily large number of EXIF tags
        @warnings << "Image contains excessive metadata (#{exif_data.size} EXIF tags)"
      end
      
      # Check for suspicious EXIF values
      suspicious_tags = %w[UserComment ImageDescription Copyright]
      suspicious_tags.each do |tag|
        if exif_data[tag] && exif_data[tag].length > 1000
          @warnings << "Suspicious EXIF data detected in #{tag} tag"
        end
      end
      
    rescue => e
      # Metadata reading failed - could indicate corrupted or malicious file
      @warnings << "Unable to read image metadata: #{e.message}"
    end
  end
  
  def scan_for_malicious_content
    # Basic pattern matching for malicious content
    content_sample = File.read(@file_path, 10000) # Read first 10KB
    
    # Check for embedded scripts or suspicious patterns
    malicious_patterns = [
      /<script/i,
      /javascript:/i,
      /data:.*base64/i,
      /eval\s*\(/i,
      /exec\s*\(/i,
      /<iframe/i,
      /<object/i,
      /<embed/i
    ]
    
    malicious_patterns.each do |pattern|
      if content_sample.match?(pattern)
        @errors << "File contains potentially malicious content"
        log_security_event('malicious_content_detected', { pattern: pattern.source })
        break
      end
    end
    
    # Check for polyglot file markers
    if content_sample.include?('GIF89a') && !detected_mime_type.start_with?('image/gif')
      @warnings << "File may be a polyglot (GIF header in non-GIF file)"
      log_security_event('polyglot_file_detected', { type: 'gif_header' })
    end
  end
  
  def sanitize_file
    # Create sanitized version of the file
    temp_path = Rails.root.join('tmp', 'sanitized', "#{SecureRandom.hex(16)}.#{file_extension}")
    FileUtils.mkdir_p(File.dirname(temp_path))
    
    begin
      image = MiniMagick::Image.new(@file_path)
      
      # Strip all metadata
      image.strip
      
      # Normalize format
      case detected_mime_type
      when 'image/jpeg'
        image.format 'jpeg'
        image.quality 95
      when 'image/png'
        image.format 'png'
      when 'image/webp'
        image.format 'webp'
        image.quality 90
      end
      
      # Write sanitized file
      image.write temp_path
      
      temp_path
    rescue => e
      raise "File sanitization failed: #{e.message}"
    end
  end
  
  def detected_mime_type
    @detected_mime_type ||= Marcel::MimeType.for(@file_path, declared_type: @file.content_type)
  end
  
  def read_magic_numbers
    @magic_numbers ||= begin
      File.open(@file_path, 'rb') do |f|
        f.read(32).unpack('C*')
      end
    rescue
      []
    end
  end
  
  def valid_image_file?
    ALLOWED_MIME_TYPES.include?(detected_mime_type)
  end
  
  def file_extension
    case detected_mime_type
    when 'image/jpeg'
      'jpg'
    when 'image/png'
      'png'
    when 'image/webp'
      'webp'
    when 'image/tiff'
      'tiff'
    when 'image/bmp'
      'bmp'
    when 'image/gif'
      'gif'
    else
      'bin'
    end
  end
  
  def sanitized_filename
    # Generate safe filename
    base_name = File.basename(@file.original_filename, '.*').gsub(/[^a-zA-Z0-9\-_]/, '_')
    "#{base_name}_sanitized.#{file_extension}"
  end
  
  def calculate_threat_level
    threat_score = 0
    
    threat_score += @errors.size * 3
    threat_score += @warnings.size * 1
    
    case threat_score
    when 0
      'LOW'
    when 1..2
      'MEDIUM'
    when 3..5
      'HIGH'
    else
      'CRITICAL'
    end
  end
  
  def log_security_event(event_type, additional_data = {})
    SecurityAuditLogger.log(
      event_type: "file_#{event_type}",
      photographer_id: @user&.id,
      ip_address: Current.request_ip,
      additional_data: additional_data.merge({
        filename: @file.original_filename,
        file_size: @file.size,
        mime_type: @file.content_type,
        threat_level: calculate_threat_level
      })
    )
  end
end