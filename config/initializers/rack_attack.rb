# Configure Rack::Attack for rate limiting and security

class Rack::Attack
  # Always allow requests from localhost
  Rack::Attack.safelist('allow-localhost') do |req|
    '127.0.0.1' == req.ip || '::1' == req.ip
  end

  # Block requests from known bad IPs
  Rack::Attack.blocklist('block-bad-ips') do |req|
    # Example: Block specific IPs
    # ['1.2.3.4', '5.6.7.8'].include?(req.ip)
    false
  end

  # Throttle login attempts by IP address
  Rack::Attack.throttle('login/ip', limit: 5, period: 20.seconds) do |req|
    if req.path == '/login' && req.post?
      req.ip
    end
  end

  # Throttle login attempts by email parameter
  Rack::Attack.throttle('login/email', limit: 5, period: 20.seconds) do |req|
    if req.path == '/login' && req.post?
      # Normalize email
      req.params['photographer'].try(:[], 'email').to_s.downcase.gsub(/\s+/, '')
    end
  end

  # Throttle registration attempts
  Rack::Attack.throttle('register/ip', limit: 3, period: 300.seconds) do |req|
    if req.path == '/register' && req.post?
      req.ip
    end
  end

  # Throttle gallery password attempts
  Rack::Attack.throttle('gallery/password', limit: 10, period: 60.seconds) do |req|
    if req.path.match?(/^\/g\/[^\/]+\/auth$/) && req.post?
      "#{req.ip}:#{req.path}"
    end
  end

  # Throttle image upload attempts
  Rack::Attack.throttle('upload/ip', limit: 20, period: 60.seconds) do |req|
    if req.path.include?('/images') && req.post?
      req.ip
    end
  end

  # Throttle general requests per IP
  Rack::Attack.throttle('req/ip', limit: 300, period: 5.minutes) do |req|
    req.ip unless req.path.start_with?('/assets')
  end

  # Custom response for throttled requests
  self.throttled_response = lambda do |env|
    retry_after = (env['rack.attack.match_data'] || {})[:period]
    [
      429,
      {
        'Content-Type' => 'application/json',
        'Retry-After' => retry_after.to_s
      },
      [{ error: 'Too many requests. Please try again later.' }.to_json]
    ]
  end

  # Custom response for blocked requests
  self.blocklisted_response = lambda do |env|
    [
      403,
      { 'Content-Type' => 'application/json' },
      [{ error: 'Request blocked' }.to_json]
    ]
  end
end

# Configure Redis store for tracking
redis_url = ENV['REDIS_URL'] || ENV['REDISCLOUD_URL'] || ENV['REDISTOGO_URL'] || 'redis://localhost:6379/0'

begin
  Rack::Attack.cache.store = ActiveSupport::Cache::RedisCacheStore.new(
    url: redis_url,
    pool_size: ENV.fetch('RAILS_MAX_THREADS') { 5 }.to_i,
    pool_timeout: 5,
    reconnect_attempts: 3,
    error_handler: -> (method:, returning:, exception:) {
      Rails.logger.error "[RACK::ATTACK] Redis error: #{exception.message}"
    }
  )
rescue => e
  Rails.logger.warn "[RACK::ATTACK] Redis connection failed, falling back to memory store: #{e.message}"
  # Fallback to memory store if Redis is unavailable
  Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
end

# Enable logging
ActiveSupport::Notifications.subscribe('rack.attack') do |name, start, finish, request_id, payload|
  req = payload[:request]
  Rails.logger.warn "[RACK::ATTACK] #{req.env['rack.attack.match_type']}: #{req.ip} #{req.request_method} #{req.fullpath}"
end