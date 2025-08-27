class PhotographersController < ApplicationController
  # Skip authentication for registration forms
  skip_before_action :authenticate_photographer!, only: [:new, :create]
  
  before_action :set_photographer, only: [:show, :edit, :update]
  before_action :ensure_correct_photographer, only: [:show, :edit, :update]
  
  # Rate limiting protection
  before_action :check_registration_attempts, only: [:create]
  before_action :log_security_event, only: [:create]

  def new
    redirect_to root_path if photographer_signed_in?
    @photographer = Photographer.new
  end

  def create
    @photographer = Photographer.new(registration_params)
    
    if @photographer.save
      # Regenerate session to prevent fixation attacks
      reset_session
      
      # Set secure session after successful registration
      session[:photographer_id] = @photographer.id
      session[:login_time] = Time.current
      session[:ip_address] = request.remote_ip
      session[:user_agent] = request.user_agent
      
      # Log successful registration
      log_security_event('successful_registration')
      
      redirect_to root_path, notice: 'Welcome to Photograph! Your account has been created successfully.'
    else
      # Log failed registration attempt
      log_security_event('failed_registration')
      
      # Clear password fields for security
      @photographer.password = nil
      @photographer.password_confirmation = nil
      
      flash.now[:alert] = 'Please correct the errors below.'
      render :new, status: :unprocessable_entity
    end
  end

  def show
    # Profile view - show photographer details
  end

  def edit
    # Edit profile form
  end

  def update
    if @photographer.update(profile_params)
      redirect_to @photographer, notice: 'Profile updated successfully.'
    else
      flash.now[:alert] = 'Please correct the errors below.'
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def registration_params
    params.require(:photographer).permit(:name, :email, :password, :password_confirmation)
  end
  
  def profile_params
    params.require(:photographer).permit(:name, :email)
  end
  
  def set_photographer
    @photographer = Photographer.find(params[:id])
  end
  
  def ensure_correct_photographer
    unless @photographer == current_photographer
      redirect_to root_path, alert: 'Access denied.'
    end
  end
  
  def check_registration_attempts
    # Additional IP-based rate limiting for registration attempts
    cache_key = "registration_attempts:#{request.remote_ip}"
    attempts = Rails.cache.read(cache_key) || 0
    
    if attempts >= 5
      log_security_event('ip_blocked_excessive_registration_attempts')
      render json: { error: 'Too many registration attempts from this IP address' }, status: :too_many_requests
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
        email: params[:photographer] ? registration_params[:email] : nil,
        name: params[:photographer] ? registration_params[:name] : nil,
        timestamp: Time.current,
        referer: request.referer,
        validation_errors: @photographer&.errors&.full_messages
      }
    )
  end
end