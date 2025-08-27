class SecurityHeadersMiddleware
  # Comprehensive security headers middleware
  
  def initialize(app)
    @app = app
  end

  def call(env)
    status, headers, response = @app.call(env)
    
    # Add security headers
    add_security_headers(headers, env)
    
    [status, headers, response]
  end

  private

  def add_security_headers(headers, env)
    request = Rack::Request.new(env)
    
    # X-Frame-Options: Prevent clickjacking
    headers['X-Frame-Options'] = 'DENY'
    
    # X-Content-Type-Options: Prevent MIME sniffing
    headers['X-Content-Type-Options'] = 'nosniff'
    
    # X-XSS-Protection: Enable XSS filtering (legacy browsers)
    headers['X-XSS-Protection'] = '1; mode=block'
    
    # Referrer-Policy: Control referrer information
    headers['Referrer-Policy'] = 'strict-origin-when-cross-origin'
    
    # X-Download-Options: Prevent file execution in IE
    headers['X-Download-Options'] = 'noopen'
    
    # X-Permitted-Cross-Domain-Policies: Adobe Flash/PDF policy
    headers['X-Permitted-Cross-Domain-Policies'] = 'none'
    
    # Feature-Policy/Permissions-Policy: Control browser features
    permissions_policy = [
      'accelerometer=()',
      'ambient-light-sensor=()',
      'autoplay=()',
      'battery=()',
      'camera=()',
      'cross-origin-isolated=()',
      'display-capture=()',
      'document-domain=()',
      'encrypted-media=()',
      'execution-while-not-rendered=()',
      'execution-while-out-of-viewport=()',
      'fullscreen=(self)',
      'geolocation=()',
      'gyroscope=()',
      'keyboard-map=()',
      'magnetometer=()',
      'microphone=()',
      'midi=()',
      'navigation-override=()',
      'payment=()',
      'picture-in-picture=()',
      'publickey-credentials-get=()',
      'screen-wake-lock=()',
      'sync-xhr=()',
      'usb=()',
      'web-share=()',
      'xr-spatial-tracking=()'
    ].join(', ')
    headers['Permissions-Policy'] = permissions_policy
    
    # Strict-Transport-Security: Force HTTPS (production only)
    if Rails.env.production? && request.scheme == 'https'
      headers['Strict-Transport-Security'] = 'max-age=31536000; includeSubDomains; preload'
    end
    
    # Expect-CT: Certificate Transparency (production only)
    if Rails.env.production?
      headers['Expect-CT'] = 'max-age=86400, enforce'
    end
    
    # Cross-Origin-Embedder-Policy: Enable cross-origin isolation
    headers['Cross-Origin-Embedder-Policy'] = 'require-corp'
    
    # Cross-Origin-Opener-Policy: Prevent cross-origin access
    headers['Cross-Origin-Opener-Policy'] = 'same-origin'
    
    # Cross-Origin-Resource-Policy: Control cross-origin resource access
    if request.path.start_with?('/g/') # Gallery pages
      headers['Cross-Origin-Resource-Policy'] = 'same-origin'
    else
      headers['Cross-Origin-Resource-Policy'] = 'same-site'
    end
    
    # Server header obfuscation
    headers.delete('Server')
    headers['Server'] = 'photograph-platform'
    
    # Remove potentially revealing headers
    headers.delete('X-Powered-By')
    headers.delete('X-Runtime')
    
    # Add custom security identifier (for monitoring)
    headers['X-Security-Policy'] = 'enforced'
    
    # NEL (Network Error Logging) for monitoring
    if Rails.env.production?
      nel_policy = {
        "report_to" => "default",
        "max_age" => 2592000,
        "include_subdomains" => true
      }
      headers['NEL'] = nel_policy.to_json
      
      # Reporting API configuration
      reporting_endpoints = {
        "group" => "default",
        "max_age" => 2592000,
        "endpoints" => [
          {
            "url" => "/security_reports",
            "priority" => 1,
            "weight" => 1
          }
        ]
      }
      headers['Report-To'] = reporting_endpoints.to_json
    end
    
    # Cache-Control for sensitive pages
    if sensitive_path?(request.path)
      headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
      headers['Pragma'] = 'no-cache'
      headers['Expires'] = '0'
    end
  end
  
  def sensitive_path?(path)
    # Define paths that should not be cached
    sensitive_patterns = [
      /^\/login/,
      /^\/sessions/,
      /^\/register/,
      /^\/g\/.*\/auth/,
      /^\/galleries/,
      /^\/images/
    ]
    
    sensitive_patterns.any? { |pattern| path.match?(pattern) }
  end
end