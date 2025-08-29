# Sidekiq configuration for background job processing

require 'sidekiq'
require 'sidekiq/web'

# Configure Redis URL
Sidekiq.configure_server do |config|
  config.redis = { url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0') }
  
  # Set concurrency for job processing
  config.concurrency = ENV.fetch('SIDEKIQ_CONCURRENCY', 5).to_i
end

Sidekiq.configure_client do |config|
  config.redis = { url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0') }
end

# Configure job retry settings
Sidekiq.default_job_options = {
  retry: 3,
  dead: true,
  backtrace: true
}

# Configure Sidekiq Web UI (protect in production)
if Rails.env.production?
  Sidekiq::Web.use(Rack::Auth::Basic) do |user, password|
    # Use environment variables for authentication
    user == ENV['SIDEKIQ_USERNAME'] && password == ENV['SIDEKIQ_PASSWORD']
  end
end

# Configure queues
Sidekiq.configure_server do |config|
  # Schedule recurring jobs (if using sidekiq-cron)
  # config.on(:startup) do
  #   Sidekiq::Cron::Job.load_from_hash(YAML.load_file('config/schedule.yml')) if File.exist?('config/schedule.yml')
  # end
end