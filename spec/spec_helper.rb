RSpec.configure do |config|
  # Use focused tests when available
  config.filter_run :focus
  config.run_all_when_everything_filtered = true

  # Settings for better output and debugging
  config.default_formatter = 'doc' if config.files_to_run.one?
  
  # Performance settings
  config.profile_examples = 10

  # Use shared examples
  config.shared_context_metadata_behavior = :apply_to_host_groups

  # Random ordering
  config.order = :random
  Kernel.srand config.seed

  # Expect syntax configuration
  config.expect_with :rspec do |expectations|
    # Enable only the newer, non-monkey-patching expect syntax
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
    expectations.syntax = :expect
  end

  # Mock syntax configuration  
  config.mock_with :rspec do |mocks|
    # Prevents mocks from verification failures on the same object
    mocks.verify_partial_doubles = true
    mocks.syntax = :expect
  end

  # Warning filters
  config.warnings = false

  # Example metadata
  config.example_status_persistence_file_path = "spec/examples.txt"

  # Disable monkey patching
  config.disable_monkey_patching!
end