class Gallery < ApplicationRecord
  # Password protection for galleries
  has_secure_password :password, validations: false
  
  # Associations
  belongs_to :photographer
  has_many :images, dependent: :destroy
  
  # Validations
  validates :title, presence: true, length: { minimum: 1, maximum: 255 }
  validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z0-9\-]+\z/ }
  validates :password, length: { minimum: 8 }, allow_blank: true
  validates :password, format: {
    with: /\A(?=.*[a-z])(?=.*[A-Z])(?=.*\d)/,
    message: "must include at least one lowercase letter, one uppercase letter, and one number"
  }, allow_blank: true, if: :password_changed?
  
  # Custom validation for password strength
  validate :password_complexity, if: :password_changed?
  
  # Callbacks
  before_validation :generate_slug, on: :create
  after_update :update_images_count
  
  # Scopes
  scope :published, -> { where(published: true) }
  scope :featured, -> { where(featured: true) }
  scope :not_expired, -> { where('expires_at IS NULL OR expires_at > ?', Time.current) }
  scope :by_photographer, ->(photographer) { where(photographer: photographer) }
  
  # Instance methods
  def password_protected?
    password_digest.present?
  end
  
  def expired?
    expires_at.present? && expires_at < Time.current
  end
  
  def viewable?
    published? && !expired?
  end
  
  def to_param
    slug
  end
  
  def increment_views!
    increment!(:views_count)
  end
  
  # Security methods
  def password_strength_score
    return 0 unless password.present?
    
    score = 0
    score += 1 if password.length >= 8
    score += 1 if password.length >= 12
    score += 1 if password.match?(/[a-z]/)
    score += 1 if password.match?(/[A-Z]/)
    score += 1 if password.match?(/\d/)
    score += 1 if password.match?(/[^a-zA-Z\d]/) # Special characters
    score += 1 if !password.match?(/(.)\1{2,}/)  # No repeated characters
    score
  end
  
  def password_strength_text
    case password_strength_score
    when 0..2
      'Very Weak'
    when 3..4
      'Weak'
    when 5..6
      'Strong'
    when 7
      'Very Strong'
    else
      'Excellent'
    end
  end
  
  def authenticate_with_security(password, request = nil)
    return false unless password_digest.present?
    
    # Track authentication attempts
    cache_key = "gallery_auth_attempts:#{slug}:#{request&.remote_ip}"
    attempts = Rails.cache.read(cache_key) || 0
    
    if attempts >= 10
      SecurityAuditLogger.log(
        event_type: 'gallery_auth_blocked',
        ip_address: request&.remote_ip,
        additional_data: {
          gallery_id: id,
          gallery_slug: slug,
          attempts: attempts
        }
      )
      return false
    end
    
    if authenticate_password(password)
      # Reset attempts on success
      Rails.cache.delete(cache_key)
      
      SecurityAuditLogger.log(
        event_type: 'gallery_auth_success',
        ip_address: request&.remote_ip,
        additional_data: {
          gallery_id: id,
          gallery_slug: slug
        }
      )
      
      true
    else
      # Increment attempts
      Rails.cache.write(cache_key, attempts + 1, expires_in: 1.hour)
      
      SecurityAuditLogger.log(
        event_type: 'gallery_auth_failed',
        ip_address: request&.remote_ip,
        additional_data: {
          gallery_id: id,
          gallery_slug: slug,
          attempts: attempts + 1
        }
      )
      
      false
    end
  end
  
  private
  
  def password_complexity
    return unless password.present?
    
    # Check for common weak patterns
    weak_patterns = [
      /^password/i,
      /^123456/,
      /^qwerty/i,
      /^abc123/i,
      /^letmein/i,
      /^welcome/i
    ]
    
    if weak_patterns.any? { |pattern| password.match?(pattern) }
      errors.add(:password, 'contains common weak patterns')
    end
    
    # Check password strength
    if password_strength_score < 4
      errors.add(:password, "is too weak (#{password_strength_text}). Consider adding more complexity.")
    end
    
    # Check for dictionary words (basic implementation)
    common_words = %w[password gallery photo image family wedding portrait]
    if common_words.any? { |word| password.downcase.include?(word) }
      errors.add(:password, 'should not contain common dictionary words')
    end
  end
  
  def generate_slug
    return if slug.present?
    
    base_slug = title.parameterize
    candidate_slug = base_slug
    counter = 1
    
    while Gallery.exists?(slug: candidate_slug)
      candidate_slug = "#{base_slug}-#{counter}"
      counter += 1
    end
    
    self.slug = candidate_slug
  end
  
  def update_images_count
    update_column(:images_count, images.count) if images_count != images.count
  end
end