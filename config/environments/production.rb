require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Performance-optimized production configuration
  config.cache_classes = true
  config.eager_load = true

  # Performance caching with optimized settings
  config.consider_all_requests_local = false
  config.action_controller.perform_caching = true

  # Enhanced caching configuration
  config.cache_store = :redis_cache_store, {
    url: ENV['REDIS_URL'] || 'redis://localhost:6379/1',
    expires_in: 1.hour,
    race_condition_ttl: 5.minutes,
    compress: true,
    compression_threshold: 1024
  }

  # Static file serving optimized for Vercel
  config.public_file_server.enabled = ENV['RAILS_SERVE_STATIC_FILES'].present?
  config.public_file_server.headers = {
    'Cache-Control' => 'public, max-age=31536000, immutable',
    'Expires' => 1.year.from_now.to_formatted_s(:rfc822)
  }

  # Asset compilation optimizations
  config.assets.js_compressor = :terser
  config.assets.css_compressor = :sass
  config.assets.compile = false
  config.assets.digest = true
  
  # Precompile additional assets for critical CSS
  config.assets.precompile += %w(critical.css)

  # Active Storage optimized for Vercel Blob
  config.active_storage.service = :vercel_blob_hot
  config.active_storage.variant_processor = :vips
  config.active_storage.resolve_model_to_route = :rails_storage_proxy

  # Force SSL with HSTS
  config.force_ssl = true
  config.ssl_options = {
    hsts: {
      expires: 31536000,
      subdomains: true,
      preload: true
    }
  }

  # Optimized logging
  config.log_level = :info
  config.log_tags = [:request_id, :remote_ip]
  
  # Custom log formatter for better performance monitoring
  config.log_formatter = proc do |severity, timestamp, progname, msg|
    "[#{timestamp}] #{severity}: #{msg}\n"
  end

  # Background job configuration
  config.active_job.queue_adapter = :sidekiq
  config.active_job.queue_name_prefix = "photograph_production"

  # Mailer configuration
  config.action_mailer.perform_caching = false
  config.action_mailer.default_url_options = { 
    host: ENV['VERCEL_URL'] || ENV['CUSTOM_DOMAIN'] 
  }

  # I18n optimizations
  config.i18n.fallbacks = true

  # Deprecation settings
  config.active_support.deprecation = :notify
  config.active_support.disallowed_deprecation = :log
  config.active_support.disallowed_deprecation_warnings = []

  # Database optimizations
  config.active_record.dump_schema_after_migration = false
  
  # Connection pool optimization for serverless
  config.database_configuration = {
    'production' => {
      'adapter' => 'postgresql',
      'url' => ENV['DATABASE_URL'],
      'pool' => ENV.fetch('RAILS_MAX_THREADS', 5).to_i,
      'timeout' => 5000,
      'checkout_timeout' => 5,
      'reaping_frequency' => 10,
      'idle_timeout' => 300,
      'variables' => {
        'statement_timeout' => '30s',
        'lock_timeout' => '10s'
      }
    }
  }

  # Memory and GC optimizations
  config.after_initialize do
    # Ruby GC tuning for better performance
    GC::Profiler.enable if ENV['RAILS_GC_PROFILING']
    
    # Preload frequently used classes
    Rails.logger.info "Preloading application classes..."
    [Gallery, Image, Photographer].each(&:connection)
    
    Rails.logger.info "Production environment initialized with performance optimizations"
  end

  # Custom middleware for performance monitoring
  config.middleware.insert_before(Rack::Runtime, 'PerformanceMonitoring') if defined?(PerformanceMonitoring)

  # Image processing optimizations
  config.active_storage.queues.analysis = :image_analysis
  config.active_storage.queues.purge = :image_purge

  # Rack::Attack configuration for rate limiting
  config.middleware.use Rack::Attack

  if ENV["RAILS_LOG_TO_STDOUT"].present?
    logger = ActiveSupport::TaggedLogging.new(Logger.new(STDOUT))
    logger.formatter = config.log_formatter
    config.logger = logger
  end
end

# Performance monitoring middleware
class PerformanceMonitoring
  def initialize(app)
    @app = app
  end

  def call(env)
    start_time = Time.current
    
    status, headers, response = @app.call(env)
    
    duration = Time.current - start_time
    
    # Log slow requests
    if duration > 1.0
      Rails.logger.warn "Slow request: #{env['REQUEST_METHOD']} #{env['PATH_INFO']} took #{duration}s"
    end
    
    # Add performance headers
    headers['X-Response-Time'] = "#{(duration * 1000).round(2)}ms"
    headers['X-Ruby-Version'] = RUBY_VERSION
    
    [status, headers, response]
  rescue => e
    Rails.logger.error "Request failed: #{e.message}"
    raise e
  end
end