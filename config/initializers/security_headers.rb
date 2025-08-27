# Security headers configuration for production

Rails.application.config.force_ssl = Rails.env.production?

Rails.application.configure do
  # Set security headers
  config.ssl_options = {
    redirect: { status: 301, port: 443 },
    secure_cookies: Rails.env.production?,
    hsts: {
      expires: 1.year,
      subdomains: true,
      preload: true
    }
  }
end

# Configure Content Security Policy - Strict Security
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.font_src    :self, :https, :data, 'fonts.gstatic.com', 'fonts.googleapis.com'
    policy.img_src     :self, :https, :data, :blob, '*.blob.vercel-storage.com'
    policy.object_src  :none
    
    # Secure script policy using nonces instead of unsafe-inline/unsafe-eval
    if Rails.env.production?
      policy.script_src :self, :https, 'cdn.jsdelivr.net'
      policy.style_src  :self, :https, 'fonts.googleapis.com', 'cdn.jsdelivr.net'
    else
      # Development allows unsafe-eval for hot reloading
      policy.script_src :self, :https, :unsafe_eval, 'cdn.jsdelivr.net'
      policy.style_src  :self, :https, :unsafe_inline, 'fonts.googleapis.com', 'cdn.jsdelivr.net'
    end
    
    policy.connect_src :self, :https, :wss, '*.blob.vercel-storage.com'
    policy.frame_src   :none
    policy.media_src   :self, :https, :blob, '*.blob.vercel-storage.com'
    
    # Base URI restriction
    policy.base_uri    :self
    
    # Form action restriction
    policy.form_action :self
    
    # Frame ancestors (prevent clickjacking)
    policy.frame_ancestors :none
    
    # Upgrade insecure requests in production
    if Rails.env.production?
      policy.upgrade_insecure_requests
      policy.block_all_mixed_content
    end
    
    # Specify URI for violation reports
    if Rails.env.production?
      policy.report_uri '/csp_reports'
    end
  end

  # Generate session nonces for permitted scripts and styles
  config.content_security_policy_nonce_generator = ->(request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w(script-src style-src)

  # Enforce policy in production, report-only in development
  config.content_security_policy_report_only = Rails.env.development?
end