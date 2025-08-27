class ApplicationController < ActionController::Base
  # Security includes
  include SecureParams
  
  # Prevent CSRF attacks by raising an exception.
  protect_from_forgery with: :exception
  
  # Include Rack::Attack protection
  include Rack::Attack::StoreHelpers if defined?(Rack::Attack)
  
  before_action :set_request_context
  before_action :validate_session_security
  before_action :set_current_photographer
  before_action :check_session_timeout
  
  # Session timeout configuration
  SESSION_TIMEOUT = 4.hours
  
  protected
  
  # Authentication helpers
  def current_photographer
    @current_photographer ||= begin
      if session[:photographer_id] && session_valid?
        photographer = Photographer.find_by(id: session[:photographer_id])
        photographer if photographer && !photographer.account_locked?
      end
    end
  end
  
  def photographer_signed_in?
    current_photographer.present?
  end
  
  def authenticate_photographer!
    unless photographer_signed_in?
      reset_session
      redirect_to login_path, alert: 'Please log in to continue.'
    end
  end
  
  helper_method :current_photographer, :photographer_signed_in?
  
  private
  
  def set_request_context
    Current.set_request_context(request)
  end
  
  def set_current_photographer
    Current.photographer = current_photographer
  end
  
  def session_valid?
    return false unless session[:photographer_id]
    return false if session_hijacking_detected?
    return false if session_expired?
    
    true
  end
  
  def session_hijacking_detected?
    # Check IP consistency (optional, can be disabled for mobile users)
    if session[:ip_address] && ENV['ENABLE_IP_BINDING'] == 'true'
      return session[:ip_address] != request.remote_ip
    end
    
    # Check User-Agent consistency
    if session[:user_agent] && session[:user_agent] != request.user_agent
      SecurityAuditLogger.log(
        event_type: 'session_hijack_attempt',
        photographer_id: session[:photographer_id],
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        additional_data: {
          original_user_agent: session[:user_agent],
          current_user_agent: request.user_agent
        }
      )
      return true
    end
    
    false
  end
  
  def session_expired?
    return false unless session[:login_time]
    
    login_time = Time.parse(session[:login_time])
    expired = login_time < SESSION_TIMEOUT.ago
    
    if expired
      SecurityAuditLogger.log(
        event_type: 'session_expired',
        photographer_id: session[:photographer_id],
        ip_address: request.remote_ip
      )
    end
    
    expired
  rescue ArgumentError
    # Invalid login_time format
    true
  end
  
  def validate_session_security
    if session[:photographer_id] && !session_valid?
      reset_session
      redirect_to login_path, alert: 'Your session has expired or been invalidated for security reasons.'
    end
  end
  
  def check_session_timeout
    return unless photographer_signed_in?
    
    # Update session activity
    session[:last_activity] = Time.current.to_s
    
    # Extend session if needed
    if session[:login_time] && Time.parse(session[:login_time]) < 30.minutes.ago
      session[:login_time] = Time.current.to_s
    end
  end
  
  # Handle security-related errors
  rescue_from ActionController::InvalidAuthenticityToken do |exception|
    SecurityAuditLogger.log(
      event_type: 'csrf_token_invalid',
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      additional_data: { referer: request.referer }
    )
    
    reset_session
    redirect_to login_path, alert: 'Security validation failed. Please log in again.'
  end
  
  # Handle unauthorized access
  rescue_from ActionController::ParameterMissing do |exception|
    SecurityAuditLogger.log(
      event_type: 'parameter_missing',
      ip_address: request.remote_ip,
      additional_data: { missing_param: exception.param }
    )
    
    render json: { error: "Missing parameter: #{exception.param}" }, status: :bad_request
  end
  
  # Handle not found errors
  rescue_from ActiveRecord::RecordNotFound do |exception|
    if request.xhr?
      render json: { error: 'Record not found' }, status: :not_found
    else
      redirect_to root_path, alert: 'The requested resource was not found.'
    end
  end
  
  # Handle suspicious activity
  def handle_suspicious_activity(details = {})
    SecurityAuditLogger.log(
      event_type: 'suspicious_activity',
      photographer_id: current_photographer&.id,
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      additional_data: details
    )
    
    # Optionally lock account or take other actions
    if current_photographer && details[:severity] == 'high'
      current_photographer.update!(locked_until: 1.hour.from_now)
      reset_session
      redirect_to login_path, alert: 'Account temporarily locked due to suspicious activity.'
    end
  end
end