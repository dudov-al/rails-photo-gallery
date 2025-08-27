module RedisHelpers
  def mock_redis
    @mock_redis ||= MockRedis.new
  end

  def with_redis_mocked(&block)
    original_redis = Rails.cache.redis if Rails.cache.respond_to?(:redis)
    
    # Mock Redis for caching
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::RedisCacheStore.new(redis: mock_redis))
    
    # Mock Redis for Rack::Attack if it's configured
    if defined?(Rack::Attack) && Rack::Attack.cache.respond_to?(:redis)
      allow(Rack::Attack.cache).to receive(:redis).and_return(mock_redis)
    end
    
    yield
  ensure
    # Restore original Redis connection if it was mocked
    if defined?(Rack::Attack) && original_redis
      allow(Rack::Attack.cache).to receive(:redis).and_return(original_redis)
    end
  end

  def clear_redis_cache
    if Rails.cache.respond_to?(:redis)
      Rails.cache.redis.flushdb
    elsif Rails.cache.respond_to?(:clear)
      Rails.cache.clear
    end
  end

  def set_cache_value(key, value, expires_in: nil)
    if expires_in
      Rails.cache.write(key, value, expires_in: expires_in)
    else
      Rails.cache.write(key, value)
    end
  end

  def get_cache_value(key)
    Rails.cache.read(key)
  end

  def simulate_cache_miss(key)
    Rails.cache.delete(key)
  end

  def expect_cache_write(key, value = nil)
    if value
      expect(Rails.cache).to receive(:write).with(key, value, anything)
    else
      expect(Rails.cache).to receive(:write).with(key, anything, anything)
    end
  end

  def expect_cache_read(key, returns: nil)
    expectation = expect(Rails.cache).to receive(:read).with(key)
    expectation.and_return(returns) if returns
    expectation
  end
end

RSpec.configure do |config|
  config.include RedisHelpers
  
  # Clear Redis cache before each test
  config.before(:each) do
    clear_redis_cache
  end
end