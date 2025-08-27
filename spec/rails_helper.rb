require 'spec_helper'
ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'

# Prevent database truncation if the environment is production
abort("The Rails environment is running in production mode!") if Rails.env.production?

require 'rspec/rails'
require 'factory_bot_rails'

# Add additional requires below this line. Rails is not loaded until this point!
begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

# Load support files
Dir[Rails.root.join('spec', 'support', '**', '*.rb')].sort.each { |f| require f }

RSpec.configure do |config|
  # Remove this line if you're not using ActiveRecord or ActiveRecord fixtures
  config.fixture_path = "#{::Rails.root}/spec/fixtures"

  # Database cleaner configuration
  config.use_transactional_fixtures = true

  # RSpec Rails can automatically mix in different behaviours to your tests
  config.infer_spec_type_from_file_location!

  # Filter lines from Rails gems in backtraces.
  config.filter_rails_from_backtrace!

  # Include FactoryBot methods
  config.include FactoryBot::Syntax::Methods

  # ActiveStorage test configuration
  config.before(:suite) do
    # Clean up uploaded files
    FileUtils.rm_rf(ActiveStorage::Blob.service.root) if ActiveStorage::Blob.service.respond_to?(:root)
  end

  config.after(:each) do
    # Clean up uploaded files after each test
    FileUtils.rm_rf(ActiveStorage::Blob.service.root) if ActiveStorage::Blob.service.respond_to?(:root)
  end

  # Action Mailer configuration for tests
  config.before(:each) do
    ActionMailer::Base.deliveries.clear
  end

  # Redis/Cache configuration for tests
  config.before(:suite) do
    Rails.cache.clear if Rails.cache.respond_to?(:clear)
  end

  config.before(:each) do
    Rails.cache.clear if Rails.cache.respond_to?(:clear)
  end

  # Current attributes cleanup
  config.after(:each) do
    Current.reset
  end

  # Security event cleanup
  config.after(:each) do
    SecurityEvent.delete_all
  end

  # Background job testing
  config.include ActiveJob::TestHelper

  # Request specs helpers
  config.include SecurityHelpers, type: :request
  config.include SecurityHelpers, type: :controller

  # Controller test helpers  
  config.include Devise::Test::ControllerHelpers, type: :controller if defined?(Devise)
  config.include Warden::Test::Helpers if defined?(Warden)
end

# Shoulda Matchers configuration
Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end