# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# Security-focused seeding with environment-based configuration
if Rails.env.development?
  # Use environment variables for secure seeding
  demo_password = ENV['DEMO_PHOTOGRAPHER_PASSWORD'] || SecureRandom.alphanumeric(12)
  gallery_password = ENV['DEMO_GALLERY_PASSWORD'] || SecureRandom.alphanumeric(10)
  
  # Generate strong passwords if not provided
  unless ENV['DEMO_PHOTOGRAPHER_PASSWORD']
    puts "SECURITY NOTICE: Generated random password for demo photographer."
    puts "Demo photographer password: #{demo_password}"
    puts "Please save this password or set DEMO_PHOTOGRAPHER_PASSWORD environment variable."
  end
  
  # Ensure password meets security requirements
  if demo_password.length < 8
    puts "WARNING: Demo password is too short. Generating secure password..."
    demo_password = "Demo#{SecureRandom.alphanumeric(8)}1!"
  end
  
  photographer = Photographer.find_or_create_by(email: 'demo@photographer.com') do |p|
    p.name = 'Demo Photographer'
    p.password = demo_password
    p.bio = 'A professional photographer specializing in weddings and portraits.'
    p.website = 'https://demophotographer.com'
    p.phone = '+1 (555) 123-4567'
  end

  if photographer.persisted? && photographer.valid?
    puts "✓ Created demo photographer: #{photographer.email}"
    
    # Create sample galleries with secure passwords
    unless photographer.galleries.exists?
      gallery1 = photographer.galleries.create!(
        title: 'Wedding - John & Sarah',
        description: 'Beautiful wedding ceremony at the beach.',
        slug: 'wedding-john-sarah',
        published: true,
        allow_downloads: true
      )
      
      # Ensure gallery password meets requirements (8+ chars)
      secure_gallery_password = gallery_password.length >= 8 ? gallery_password : "Gallery#{SecureRandom.alphanumeric(6)}1!"
      
      gallery2 = photographer.galleries.create!(
        title: 'Portrait Session - Johnson Family',
        description: 'Family portrait session in the park.',
        slug: 'johnson-family-portraits',
        password: secure_gallery_password,
        published: true,
        allow_downloads: true
      )
      
      puts "✓ Created sample galleries: #{gallery1.title}, #{gallery2.title}"
      
      unless ENV['DEMO_GALLERY_PASSWORD']
        puts "Demo gallery password: #{secure_gallery_password}"
        puts "Please save this password or set DEMO_GALLERY_PASSWORD environment variable."
      end
    end
  else
    puts "✗ Failed to create demo photographer:"
    photographer.errors.full_messages.each { |msg| puts "  - #{msg}" }
  end
elsif Rails.env.production?
  # Production seeding should be done via separate secure process
  puts "PRODUCTION SEEDING DISABLED"
  puts "Use secure deployment scripts for production data initialization."
  puts "Ensure all passwords are set via environment variables."
  
  # Verify required environment variables exist
  required_env_vars = %w[
    DATABASE_URL
    SECRET_KEY_BASE
    RAILS_MASTER_KEY
  ]
  
  missing_vars = required_env_vars.reject { |var| ENV[var].present? }
  
  if missing_vars.any?
    puts "✗ Missing required environment variables:"
    missing_vars.each { |var| puts "  - #{var}" }
    exit 1
  else
    puts "✓ All required environment variables are present"
  end
end

puts "Database seeded successfully!"

# Security audit for seed process
if Rails.env.development?
  SecurityAuditLogger.log(
    event_type: 'database_seeded',
    ip_address: 'localhost',
    additional_data: {
      environment: Rails.env,
      timestamp: Time.current,
      photographer_count: Photographer.count,
      gallery_count: Gallery.count
    }
  )
end