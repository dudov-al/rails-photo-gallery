# Redis configuration for secure distributed caching and rate limiting

redis_url = ENV['REDIS_URL'] || ENV['REDISCLOUD_URL'] || ENV['REDISTOGO_URL'] || 'redis://localhost:6379/0'

# Configure Redis connection with security settings
redis_config = {
  url: redis_url,
  driver: :ruby,
  reconnect_attempts: 3,
  reconnect_delay: 1.5,
  reconnect_delay_max: 10.0,
  timeout: 5.0,
  tcp_keepalive: 60,
  # SSL configuration for production
  ssl_params: Rails.env.production? && redis_url.start_with?('rediss://') ? {
    verify_mode: OpenSSL::SSL::VERIFY_PEER,
    cert_store: OpenSSL::X509::Store.new.tap { |store| store.set_default_paths }
  } : {}
}

# Create Redis connection pool
Redis.current = ConnectionPool.new(size: ENV.fetch('RAILS_MAX_THREADS') { 5 }.to_i, timeout: 5) do
  Redis.new(redis_config)
end

# Configure Rails cache store with Redis
if Rails.env.production?
  Rails.application.configure do
    config.cache_store = :redis_cache_store, {
      url: redis_url,
      pool_size: ENV.fetch('RAILS_MAX_THREADS') { 5 }.to_i,
      pool_timeout: 5,
      reconnect_attempts: 3,
      namespace: "photograph_#{Rails.env}",
      compress: true,
      expires_in: 24.hours,
      error_handler: -> (method:, returning:, exception:) {
        Rails.logger.error "[REDIS CACHE] Error in #{method}: #{exception.message}"
        # Optionally send to monitoring service
        SecurityAuditLogger.log(
          event_type: 'redis_cache_error',
          additional_data: {
            method: method,
            error: exception.message,
            returning: returning
          }
        )
      }
    }
  end
end

# Test Redis connection on startup
begin
  Redis.current.with do |redis|
    redis.ping
    Rails.logger.info "[REDIS] Successfully connected to Redis at #{redis_url}"
  end
rescue => e
  Rails.logger.warn "[REDIS] Redis connection failed: #{e.message}"
  if Rails.env.production?
    Rails.logger.error "[REDIS] Redis is required in production environment"
    # Don't fail startup, but log critical issue
    SecurityAuditLogger.log(
      event_type: 'redis_connection_failed',
      additional_data: {
        error: e.message,
        environment: Rails.env,
        redis_url: redis_url.gsub(/\/\/[^@]*@/, '//***:***@') # Hide credentials in logs
      }
    )
  end
end