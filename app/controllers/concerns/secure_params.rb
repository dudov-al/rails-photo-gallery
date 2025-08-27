module SecureParams
  extend ActiveSupport::Concern
  
  included do
    before_action :sanitize_params
    before_action :detect_malicious_input
  end
  
  private
  
  def sanitize_params
    # Sanitize all string parameters
    sanitize_params_recursive(params)
  end
  
  def detect_malicious_input
    threats = detect_threats_in_params(params)
    
    if threats.any?
      log_security_threat(threats)
      
      # Block request if high-risk threats detected
      critical_threats = %w[SQL_INJECTION_ATTEMPT COMMAND_INJECTION_ATTEMPT]
      if threats.any? { |threat| critical_threats.include?(threat) }
        render json: { error: 'Request blocked for security reasons' }, status: :forbidden
        return
      end
    end
  end
  
  def sanitize_params_recursive(params_hash)
    params_hash.each do |key, value|
      case value
      when String
        params_hash[key] = InputSanitizer.sanitize_string(value)
      when Hash
        sanitize_params_recursive(value)
      when Array
        params_hash[key] = value.map do |item|
          item.is_a?(String) ? InputSanitizer.sanitize_string(item) : item
        end
      end
    end
  end
  
  def detect_threats_in_params(params_hash, current_path = [])
    threats = []
    
    params_hash.each do |key, value|
      path = current_path + [key]
      
      case value
      when String
        param_threats = InputSanitizer.detect_threats(value)
        if param_threats.any?
          threats.concat(param_threats.map { |threat| "#{threat}:#{path.join('.')}" })
        end
      when Hash
        threats.concat(detect_threats_in_params(value, path))
      when Array
        value.each_with_index do |item, index|
          if item.is_a?(String)
            item_threats = InputSanitizer.detect_threats(item)
            if item_threats.any?
              threats.concat(item_threats.map { |threat| "#{threat}:#{path.join('.')}[#{index}]" })
            end
          end
        end
      end
    end
    
    threats
  end
  
  def log_security_threat(threats)
    SecurityAuditLogger.log(
      event_type: 'malicious_input_detected',
      photographer_id: current_photographer&.id,
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      additional_data: {
        controller: controller_name,
        action: action_name,
        threats: threats,
        params_preview: sanitized_params_preview,
        url: request.fullpath,
        method: request.method
      }
    )
  end
  
  def sanitized_params_preview
    # Create safe preview of params for logging (remove sensitive data)
    safe_params = params.to_unsafe_h.deep_dup
    
    # Remove sensitive fields
    sensitive_fields = %w[password password_confirmation token secret api_key]
    
    def redact_sensitive(hash, sensitive_fields)
      hash.each do |key, value|
        if sensitive_fields.any? { |field| key.to_s.downcase.include?(field) }
          hash[key] = '[REDACTED]'
        elsif value.is_a?(Hash)
          redact_sensitive(value, sensitive_fields)
        elsif value.is_a?(Array) && value.first.is_a?(Hash)
          value.each { |item| redact_sensitive(item, sensitive_fields) if item.is_a?(Hash) }
        end
      end
    end
    
    redact_sensitive(safe_params, sensitive_fields)
    
    # Truncate large values
    JSON.parse(safe_params.to_json).to_s.truncate(1000)
  rescue
    '[PARAMS_PREVIEW_ERROR]'
  end
  
  # Helper methods for specific parameter sanitization
  def sanitize_search_params
    if params[:q] || params[:search] || params[:query]
      search_term = params[:q] || params[:search] || params[:query]
      sanitized_search = InputSanitizer.sanitize_for_search(search_term)
      
      params[:q] = sanitized_search if params[:q]
      params[:search] = sanitized_search if params[:search]
      params[:query] = sanitized_search if params[:query]
    end
  end
  
  def validate_file_params
    return unless params[:image] && params[:image][:file]
    
    file = params[:image][:file]
    
    # Basic file validation
    unless file.respond_to?(:original_filename) && file.respond_to?(:content_type)
      render json: { error: 'Invalid file upload' }, status: :bad_request
      return false
    end
    
    # Sanitize filename
    if file.original_filename.present?
      file.define_singleton_method(:original_filename) do
        InputSanitizer.sanitize_filename(super())
      end
    end
    
    true
  end
  
  def require_secure_params(param_definitions)
    # Enhanced parameter validation with security checks
    sanitized_params = InputSanitizer.validate_and_sanitize_params(params, param_definitions)
    
    # Check if all required parameters are present
    required_params = param_definitions.select { |k, v| v.is_a?(Hash) && v[:required] }
    missing_params = required_params.keys - sanitized_params.keys
    
    if missing_params.any?
      render json: { 
        error: 'Missing required parameters',
        missing: missing_params 
      }, status: :bad_request
      return nil
    end
    
    sanitized_params
  end
end