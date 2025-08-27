require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

# Explicitly require custom middleware before application class
require_relative '../app/middleware/security_headers_middleware'

module Photograph
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.0

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Security middleware
    config.middleware.insert_before ActionDispatch::Cookies, SecurityHeadersMiddleware
    
    # Custom logger for security events
    config.logger = ActiveSupport::Logger.new(STDOUT) if ENV['RAILS_LOG_TO_STDOUT'].present?
    
    # Add security logger
    config.logger.define_singleton_method(:security) do
      @security_logger ||= ActiveSupport::Logger.new(
        Rails.root.join('log', "security_#{Rails.env}.log")
      )
    end
    
    # Autoload paths
    config.autoload_paths += %W[
      #{config.root}/app/services
      #{config.root}/app/middleware
    ]

    # Active Job configuration
    config.active_job.queue_adapter = Rails.env.production? ? :sidekiq : :async

    # Security configuration
    config.force_ssl = Rails.env.production?

    # File upload configuration with security enhancements
    config.active_storage.variant_processor = :mini_magick
    
    # Remove ImageMagick analyzer (security risk) and use libvips
    config.active_storage.analyzers.delete ActiveStorage::Analyzer::ImageAnalyzer::ImageMagick
    config.active_storage.analyzers.prepend ActiveStorage::Analyzer::ImageAnalyzer::Vips
    
    # Max file size (50MB)
    config.active_storage.max_file_size = 50.megabytes
    
    # Strict content type validation
    config.active_storage.content_types_allowed_inline = %w[
      image/png
      image/jpeg
      image/webp
    ]
    
    # Prevent direct uploads in production (force validation)
    config.active_storage.direct_uploads_require_authentication = true
  end
end