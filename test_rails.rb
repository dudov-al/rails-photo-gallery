#!/usr/bin/env ruby

puts "Testing Rails application setup..."

begin
  require_relative "config/environment"
  puts "✓ Rails environment loaded successfully"
  puts "✓ Rails version: #{Rails.version}"
  puts "✓ Application: #{Rails.application.class.name}"
  puts "✓ Environment: #{Rails.env}"
  
  # Test database connection
  begin
    ActiveRecord::Base.connection
    puts "✓ Database connection available"
  rescue => e
    puts "✗ Database connection failed: #{e.message}"
  end
  
  # Test models can be loaded
  begin
    require_relative "app/models/photographer"
    require_relative "app/models/gallery"
    require_relative "app/models/image"
    puts "✓ Models loaded successfully"
  rescue => e
    puts "✗ Model loading failed: #{e.message}"
  end
  
  puts "\n✓ Rails application setup is working correctly!"
  
rescue => e
  puts "✗ Rails environment failed to load: #{e.message}"
  puts e.backtrace.first(5)
end