class InputSanitizer
  # Comprehensive input sanitization service for security
  
  # HTML tags to strip completely
  DANGEROUS_TAGS = %w[
    script style object embed iframe frame frameset
    meta link base form input textarea button select
    applet audio video source track canvas svg
  ].freeze
  
  # Allowed HTML tags for rich text (if needed)
  ALLOWED_TAGS = %w[p br strong b em i u].freeze
  
  # HTML attributes to strip
  DANGEROUS_ATTRIBUTES = %w[
    onclick onload onerror onmouseover onfocus onblur
    javascript: data: vbscript: file: ftp:
  ].freeze
  
  # Regex patterns for detecting malicious content
  MALICIOUS_PATTERNS = [
    /<script[\s\S]*?<\/script>/mi,
    /javascript:/i,
    /vbscript:/i,
    /data:(?!image\/)[^;]*;base64/i,
    /expression\s*\(/i,
    /url\s*\(/i,
    /import\s*\(/i,
    /@import/i,
    /behavior\s*:/i,
    /binding\s*:/i,
    /-moz-binding/i
  ].freeze
  
  # SQL injection patterns
  SQL_INJECTION_PATTERNS = [
    /('|(\\')|('')|(%27)|(&#x27;))((\s*)(union|select|insert|update|delete|drop|create|alter|exec|execute))/i,
    /(union|select|insert|update|delete|drop|create|alter)\s+.*(from|into|where|values)/i,
    /;\s*(drop|delete|truncate|alter|update)\s/i,
    /(script|script\s)/i,
    /(or|and)\s+\d+\s*=\s*\d+/i
  ].freeze
  
  def self.sanitize_string(input)
    return nil if input.nil?
    return input if input.blank?
    
    # Convert to string and normalize encoding
    str = input.to_s.encode('UTF-8', invalid: :replace, replace: '')
    
    # Remove null bytes and control characters
    str = str.gsub(/\0/, '').gsub(/[\x00-\x08\x0B-\x0C\x0E-\x1F\x7F]/, '')
    
    # Normalize Unicode
    str = str.unicode_normalize(:nfc)
    
    # Strip malicious HTML/JS content
    str = strip_malicious_content(str)
    
    # HTML entity decode and re-encode safely
    str = CGI.unescapeHTML(str)
    str = CGI.escapeHTML(str)
    
    # Truncate if too long (prevent DoS)
    str = str.truncate(10000) if str.length > 10000
    
    str.strip
  end
  
  def self.sanitize_filename(filename)
    return nil if filename.nil?
    return filename if filename.blank?
    
    # Remove path traversal attempts
    clean_name = File.basename(filename.to_s)
    
    # Remove dangerous characters
    clean_name = clean_name.gsub(/[^\w\-_\.]/, '_')
    
    # Remove multiple dots (path traversal protection)
    clean_name = clean_name.gsub(/\.{2,}/, '.')
    
    # Ensure it starts with alphanumeric
    clean_name = clean_name.gsub(/^[^a-zA-Z0-9]+/, '')
    
    # Truncate length
    clean_name = clean_name.truncate(100)
    
    # Ensure it has an extension
    clean_name = "file.#{clean_name}" unless clean_name.include?('.')
    
    clean_name
  end
  
  def self.sanitize_email(email)
    return nil if email.nil?
    return email if email.blank?
    
    email = email.to_s.strip.downcase
    
    # Basic email validation
    return nil unless email.match?(/\A[^@\s]+@[^@\s]+\z/)
    
    # Check for suspicious patterns
    return nil if email.match?(/[<>()[\]\\,;:'"@]/)
    
    # Length check
    return nil if email.length > 100
    
    email
  end
  
  def self.sanitize_url(url)
    return nil if url.nil?
    return url if url.blank?
    
    url = url.to_s.strip
    
    # Only allow http/https
    return nil unless url.match?(/\Ahttps?:\/\//)
    
    begin
      uri = URI.parse(url)
      return nil unless %w[http https].include?(uri.scheme)
      return nil if uri.host.nil?
      
      # Block dangerous domains
      dangerous_domains = %w[localhost 127.0.0.1 0.0.0.0 10. 172. 192.168.]
      return nil if dangerous_domains.any? { |domain| uri.host.start_with?(domain) }
      
      uri.to_s.truncate(2000)
    rescue URI::InvalidURIError
      nil
    end
  end
  
  def self.validate_and_sanitize_params(params, allowed_params = {})
    # Recursively sanitize parameters based on type expectations
    sanitized = {}
    
    allowed_params.each do |key, type|
      value = params[key]
      next if value.nil?
      
      case type
      when :string
        sanitized[key] = sanitize_string(value)
      when :email
        sanitized[key] = sanitize_email(value)
      when :url
        sanitized[key] = sanitize_url(value)
      when :filename
        sanitized[key] = sanitize_filename(value)
      when :integer
        sanitized[key] = value.to_i if value.to_s.match?(/\A\d+\z/)
      when :boolean
        sanitized[key] = %w[true 1 yes on].include?(value.to_s.downcase)
      when :array
        if value.is_a?(Array)
          sanitized[key] = value.map { |v| sanitize_string(v) }.compact
        end
      when :hash
        if value.is_a?(Hash)
          sanitized[key] = sanitize_hash(value)
        end
      end
    end
    
    sanitized
  end
  
  def self.detect_threats(input)
    return [] if input.nil? || input.blank?
    
    threats = []
    input_str = input.to_s.downcase
    
    # Check for XSS
    if MALICIOUS_PATTERNS.any? { |pattern| input_str.match?(pattern) }
      threats << 'XSS_ATTEMPT'
    end
    
    # Check for SQL injection
    if SQL_INJECTION_PATTERNS.any? { |pattern| input_str.match?(pattern) }
      threats << 'SQL_INJECTION_ATTEMPT'
    end
    
    # Check for path traversal
    if input_str.include?('../') || input_str.include?('..\\')
      threats << 'PATH_TRAVERSAL_ATTEMPT'
    end
    
    # Check for command injection
    if input_str.match?(/[;&|`$(){}[\]]/i)
      threats << 'COMMAND_INJECTION_ATTEMPT'
    end
    
    # Check for LDAP injection
    if input_str.match?(/[()=*!&|]/i)
      threats << 'LDAP_INJECTION_ATTEMPT'
    end
    
    threats
  end
  
  def self.sanitize_for_search(query)
    return nil if query.nil?
    return query if query.blank?
    
    # Remove special regex characters for search
    query = query.to_s.gsub(/[.*+?^${}()|[\]\\]/, '\\\\\&')
    
    # Basic sanitization
    query = sanitize_string(query)
    
    # Limit length
    query.truncate(100)
  end
  
  private
  
  def self.strip_malicious_content(str)
    # Remove dangerous HTML tags
    DANGEROUS_TAGS.each do |tag|
      str = str.gsub(/<#{tag}[\s\S]*?<\/#{tag}>/mi, '')
      str = str.gsub(/<#{tag}[^>]*>/mi, '')
    end
    
    # Remove dangerous attributes
    DANGEROUS_ATTRIBUTES.each do |attr|
      str = str.gsub(/#{attr}[^>]*>/mi, '>')
    end
    
    # Remove script patterns
    MALICIOUS_PATTERNS.each do |pattern|
      str = str.gsub(pattern, '')
    end
    
    str
  end
  
  def self.sanitize_hash(hash)
    return {} unless hash.is_a?(Hash)
    
    sanitized = {}
    hash.each do |key, value|
      clean_key = sanitize_string(key.to_s)
      next if clean_key.blank?
      
      sanitized[clean_key] = case value
      when String
        sanitize_string(value)
      when Hash
        sanitize_hash(value)
      when Array
        value.map { |v| v.is_a?(String) ? sanitize_string(v) : v }.compact
      else
        value
      end
    end
    
    sanitized
  end
end