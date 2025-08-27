# Secure session configuration
Rails.application.config.session_store :cookie_store,
  key: '_photograph_session',
  httponly: true,                    # Prevent XSS attacks
  secure: Rails.env.production?,     # HTTPS only in production
  same_site: :lax,                   # CSRF protection
  expire_after: 24.hours,            # Session expiration
  path: '/',                         # Session path
  domain: Rails.env.production? ? :all : nil  # Domain configuration

# Additional security configurations
Rails.application.configure do
  # Use secure cookies in production
  config.force_ssl = Rails.env.production?
  
  # Session security settings
  config.session_store :cookie_store, 
    key: '_photograph_session',
    httponly: true,
    secure: Rails.env.production?,
    same_site: Rails.env.production? ? :strict : :lax,
    expire_after: 24.hours
  
  # Configure cookie security
  if Rails.env.production?
    config.ssl_options = {
      secure_cookies: true,
      hsts: {
        expires: 1.year,
        subdomains: true,
        preload: true
      }
    }
  end
end

# Session cleanup job (for Redis-based sessions in the future)
if Rails.env.production?
  # Schedule session cleanup
  # This would be implemented as a background job to clean expired sessions
  # For now, using cookie-based sessions with automatic expiration
end