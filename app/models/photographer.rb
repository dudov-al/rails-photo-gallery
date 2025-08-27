class Photographer < ApplicationRecord
  has_secure_password
  
  # Security configuration
  MAX_FAILED_ATTEMPTS = 5
  LOCKOUT_DURATION = 30.minutes
  
  # Associations
  has_many :galleries, dependent: :destroy
  has_many :images, through: :galleries
  has_many :security_events, dependent: :destroy
  
  # Validations
  validates :email, presence: true, uniqueness: { case_sensitive: false }, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true, length: { minimum: 2, maximum: 100 }
  validates :password, length: { minimum: 8 }, format: { 
    with: /\A(?=.*[a-z])(?=.*[A-Z])(?=.*\d)/,
    message: "must include at least one lowercase letter, one uppercase letter, and one number"
  }, if: :password_digest_changed?
  
  # Callbacks
  before_save :normalize_email
  after_create :log_account_creation
  
  # Scopes
  scope :active, -> { where(active: true) }
  scope :with_galleries, -> { joins(:galleries).distinct }
  scope :locked, -> { where('locked_until > ?', Time.current) }
  scope :unlocked, -> { where('locked_until IS NULL OR locked_until <= ?', Time.current) }
  
  # Security methods
  def account_locked?
    locked_until.present? && locked_until > Time.current
  end
  
  def increment_failed_attempts!
    self.failed_attempts = (failed_attempts || 0) + 1
    self.last_failed_attempt = Time.current
    
    if failed_attempts >= MAX_FAILED_ATTEMPTS
      self.locked_until = LOCKOUT_DURATION.from_now
      log_security_event('account_locked')
    end
    
    save!
    log_security_event('failed_login_attempt')
  end
  
  def reset_failed_attempts!
    update!(
      failed_attempts: 0,
      locked_until: nil,
      last_failed_attempt: nil,
      last_login_at: Time.current,
      last_login_ip: Current.request_ip
    )
    log_security_event('successful_login')
  end
  
  def authenticate_with_security(password)
    return false if account_locked?
    
    if authenticate(password)
      reset_failed_attempts!
      true
    else
      increment_failed_attempts!
      false
    end
  end
  
  def password_strength_score
    return 0 unless password.present?
    
    score = 0
    score += 1 if password.length >= 8
    score += 1 if password.match?(/[a-z]/)
    score += 1 if password.match?(/[A-Z]/)
    score += 1 if password.match?(/\d/)
    score += 1 if password.match?(/[^a-zA-Z\d]/)
    score += 1 if password.length >= 12
    score
  end
  
  def time_until_unlock
    return 0 unless account_locked?
    
    ((locked_until - Time.current) / 1.minute).ceil
  end
  
  private
  
  def normalize_email
    self.email = email.downcase.strip if email.present?
  end
  
  def log_account_creation
    log_security_event('account_created')
  end
  
  def log_security_event(event_type)
    SecurityAuditLogger.log(
      event_type: event_type,
      photographer_id: id,
      ip_address: Current.request_ip,
      additional_data: {
        email: email,
        failed_attempts: failed_attempts,
        locked_until: locked_until
      }
    )
  end
end