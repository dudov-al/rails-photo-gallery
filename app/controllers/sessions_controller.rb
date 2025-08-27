class SessionsController < ApplicationController
  # Skip authentication for login forms
  skip_before_action :authenticate_photographer!, only: [:new, :create]
  
  # Rate limiting protection
  before_action :check_login_attempts, only: [:create]
  before_action :log_security_event, only: [:create, :destroy]
  
  def new
    redirect_to root_path if photographer_signed_in?
    @photographer = Photographer.new
  end

  def create
    @photographer = Photographer.find_by(email: login_params[:email]&.downcase&.strip)
    
    if @photographer&.authenticate(login_params[:password])
      if @photographer.account_locked?
        log_security_event('account_locked_login_attempt')
        redirect_to login_path, alert: 'Account is temporarily locked due to multiple failed attempts. Please try again later.'
        return
      end
      
      # Reset failed attempts on successful login
      @photographer.reset_failed_attempts!
      
      # Regenerate session to prevent fixation attacks
      reset_session
      
      # Set secure session
      session[:photographer_id] = @photographer.id
      session[:login_time] = Time.current
      session[:ip_address] = request.remote_ip
      session[:user_agent] = request.user_agent
      
      log_security_event('successful_login')
      
      redirect_to root_path, notice: 'Successfully logged in!'
    else
      # Track failed attempts
      if @photographer
        @photographer.increment_failed_attempts!
        
        if @photographer.account_locked?
          log_security_event('account_locked')
          redirect_to login_path, alert: 'Account locked due to multiple failed attempts. Please try again later.'
          return
        end
      end
      
      log_security_event('failed_login_attempt')
      
      # Use generic error message to prevent user enumeration
      @photographer = Photographer.new(email: login_params[:email])
      flash.now[:alert] = 'Invalid email or password.'
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    log_security_event('logout')
    
    # Clear all session data
    reset_session
    
    redirect_to root_path, notice: 'Successfully logged out!'
  end

  private

  def login_params
    params.require(:photographer).permit(:email, :password)
  end
  
  def check_login_attempts
    # Additional IP-based rate limiting beyond Rack::Attack
    cache_key = "login_attempts:#{request.remote_ip}"
    attempts = Rails.cache.read(cache_key) || 0
    
    if attempts >= 10
      log_security_event('ip_blocked_excessive_attempts')
      render json: { error: 'Too many login attempts from this IP address' }, status: :too_many_requests
      return
    end
    
    Rails.cache.write(cache_key, attempts + 1, expires_in: 1.hour)
  end
  
  def log_security_event(event_type)
    SecurityAuditLogger.log(
      event_type: event_type,
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      photographer_id: @photographer&.id,
      session_id: session.id,
      additional_data: {
        email: login_params[:email] if params[:photographer],
        timestamp: Time.current,
        referer: request.referer
      }
    )
  end
end