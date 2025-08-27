# Performance optimization and benchmarking tasks
namespace :performance do
  desc "Run comprehensive performance benchmarks"
  task benchmark: :environment do
    puts "🚀 Starting Performance Benchmarks"
    puts "=" * 50
    
    # Load performance monitor
    require_relative '../performance_monitor'
    
    # Test database performance
    benchmark_database_queries
    
    # Test image processing performance
    benchmark_image_processing
    
    # Test controller performance
    benchmark_controller_performance
    
    # Generate comprehensive report
    report = PerformanceMonitor.report
    
    puts "\n📊 Performance Summary"
    puts "=" * 50
    puts "Performance Grade: #{report[:summary][:performance_grade]}"
    puts "Total Benchmarks: #{report[:summary][:total_benchmarks]}"
    puts "Slow Queries: #{report[:summary][:total_slow_queries]}"
    puts "Current Memory: #{report[:summary][:current_memory_mb]}MB"
    
    # Save report to file
    File.write("tmp/performance_report_#{Time.current.strftime('%Y%m%d_%H%M%S')}.json", 
               JSON.pretty_generate(report))
    
    puts "\n✅ Benchmarks completed. Report saved to tmp/"
  end
  
  desc "Optimize database with performance indexes"
  task optimize_database: :environment do
    puts "🔧 Optimizing Database Performance"
    puts "=" * 50
    
    ActiveRecord::Base.connection.execute("ANALYZE;")
    puts "✅ Database statistics updated"
    
    # Check for missing indexes
    missing_indexes = check_missing_indexes
    if missing_indexes.any?
      puts "⚠️  Missing indexes detected:"
      missing_indexes.each { |idx| puts "   - #{idx}" }
      puts "Run: rails db:migrate to add performance indexes"
    else
      puts "✅ All critical indexes present"
    end
  end
  
  desc "Warm up application caches"
  task warmup: :environment do
    puts "🔥 Warming up caches"
    puts "=" * 50
    
    # Preload frequently accessed data
    Gallery.published.limit(10).includes(:photographer, images: :blob).find_each do |gallery|
      puts "Warming cache for gallery: #{gallery.title}"
      # Access methods that would be cached
      gallery.viewable?
      gallery.images.completed.count
    end
    
    # Preload Active Storage variants
    Image.joins(:file_attachment)
         .where(processing_status: :completed)
         .limit(20)
         .find_each do |image|
      begin
        image.thumbnail_url
        image.web_url
      rescue => e
        puts "Warning: Could not warm cache for image #{image.id}: #{e.message}"
      end
    end
    
    puts "✅ Cache warmup completed"
  end
  
  desc "Profile memory usage"
  task memory_profile: :environment do
    puts "🧠 Memory Profiling"
    puts "=" * 50
    
    require 'objspace'
    
    ObjectSpace.trace_object_allocations_start
    
    # Simulate typical workload
    gallery = Gallery.published.includes(:images).first
    if gallery
      gallery.images.limit(10).each do |image|
        image.thumbnail_url
        image.web_url
      end
    end
    
    ObjectSpace.trace_object_allocations_stop
    
    # Generate memory report
    stats = ObjectSpace.count_objects
    puts "Object counts:"
    stats.sort_by { |k, v| v }.reverse.first(10).each do |type, count|
      puts "  #{type}: #{count}"
    end
    
    puts "\n✅ Memory profiling completed"
  end
  
  desc "Test image processing performance"
  task image_benchmark: :environment do
    puts "📸 Image Processing Benchmark"
    puts "=" * 50
    
    # Create test image if none exists
    test_image = create_test_image
    
    if test_image
      benchmark_variants(test_image)
    else
      puts "❌ No test images available"
    end
  end
  
  private
  
  def benchmark_database_queries
    puts "\n📊 Database Query Benchmarks"
    puts "-" * 30
    
    # Gallery queries
    PerformanceMonitor.benchmark('Gallery.published') do
      Gallery.published.limit(10).to_a
    end
    
    PerformanceMonitor.benchmark('Gallery.with_images') do
      Gallery.published.includes(:images).limit(5).to_a
    end
    
    # Image queries  
    PerformanceMonitor.benchmark('Image.completed') do
      Image.where(processing_status: :completed).limit(20).to_a
    end
    
    PerformanceMonitor.benchmark('Image.with_attachments') do
      Image.includes(file_attachment: :blob).limit(10).to_a
    end
  end
  
  def benchmark_image_processing
    puts "\n🖼️  Image Processing Benchmarks"
    puts "-" * 30
    
    test_image = Image.joins(:file_attachment).first
    return unless test_image
    
    PerformanceMonitor.benchmark('Generate_thumbnail') do
      test_image.thumbnail
    end
    
    PerformanceMonitor.benchmark('Generate_web_size') do
      test_image.web_size
    end
  end
  
  def benchmark_controller_performance
    puts "\n🎮 Controller Performance Benchmarks"
    puts "-" * 30
    
    # Simulate gallery show action
    gallery = Gallery.published.first
    return unless gallery
    
    PerformanceMonitor.benchmark('PublicGallery_show_query') do
      images = gallery.images
        .includes(file_attachment: [:blob, { variant_attachments: :blob }])
        .where(processing_status: :completed)
        .ordered
        .select(:id, :filename, :alt_text, :position, :processing_status, :gallery_id)
      images.to_a
    end
  end
  
  def check_missing_indexes
    missing = []
    
    # Check critical indexes
    indexes = ActiveRecord::Base.connection.indexes('galleries')
    missing << 'galleries(views_count)' unless indexes.any? { |idx| idx.columns == ['views_count'] }
    missing << 'galleries(published, expires_at)' unless indexes.any? { |idx| idx.columns.sort == ['published', 'expires_at'].sort }
    
    indexes = ActiveRecord::Base.connection.indexes('images')
    missing << 'images(gallery_id, processing_status)' unless indexes.any? { |idx| idx.columns.sort == ['gallery_id', 'processing_status'].sort }
    
    missing
  end
  
  def create_test_image
    # Try to find an existing image first
    Image.joins(:file_attachment).first
  end
  
  def benchmark_variants(image)
    variants = [:thumbnail, :web_size, :preview_size]
    
    variants.each do |variant|
      PerformanceMonitor.benchmark("#{variant}_generation") do
        image.send(variant)
      end
    end
  end
end
EOF < /dev/null