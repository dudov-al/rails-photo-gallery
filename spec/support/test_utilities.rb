module TestUtilities
  # Query counting for performance tests
  def exceed_query_limit(expected)
    query_count = 0
    counter = lambda { |*| query_count += 1 }
    
    ActiveSupport::Notifications.subscribed(counter, 'sql.active_record') do
      yield
    end
    
    RSpec::Matchers::BuiltIn::BePredicate.new(:>, expected).tap do |matcher|
      matcher.instance_variable_set(:@actual, query_count)
    end
  end

  # Mock external services
  def mock_external_services
    # Mock image processing service
    allow(ImageProcessingJob).to receive(:perform_later).and_return(true)
    
    # Mock email delivery
    allow_any_instance_of(ActionMailer::MessageDelivery).to receive(:deliver_later)
    
    # Mock cloud storage
    allow_any_instance_of(ActiveStorage::Service::DiskService).to receive(:upload).and_return(true)
    allow_any_instance_of(ActiveStorage::Service::DiskService).to receive(:delete).and_return(true)
  end

  # Database state helpers
  def clean_database
    DatabaseCleaner.clean_with(:truncation)
  end

  def with_clean_database(&block)
    clean_database
    yield
  ensure
    clean_database
  end

  # Time manipulation helpers
  def travel_to_time(time, &block)
    travel_to(time, &block)
  end

  def with_frozen_time(time = Time.current, &block)
    freeze_time(time, &block)
  end

  # Network mocking
  def mock_network_failure
    allow(Net::HTTP).to receive(:start).and_raise(SocketError.new('Network unavailable'))
  end

  def mock_slow_network(delay_seconds = 5)
    allow(Net::HTTP).to receive(:start) do |*args, &block|
      sleep(delay_seconds)
      block.call if block_given?
    end
  end

  # Security testing helpers
  def expect_security_log(event_type, **additional_data)
    expect(SecurityAuditLogger).to receive(:log).with(
      event_type: event_type,
      photographer_id: anything,
      ip_address: anything,
      additional_data: hash_including(additional_data)
    )
  end

  def simulate_attack(attack_type, options = {})
    case attack_type
    when :brute_force
      simulate_brute_force_attack(options)
    when :dos
      simulate_dos_attack(options)
    when :sql_injection
      simulate_sql_injection_attack(options)
    when :xss
      simulate_xss_attack(options)
    else
      raise ArgumentError, "Unknown attack type: #{attack_type}"
    end
  end

  # File testing helpers
  def create_test_image_with_exif
    # Creates a test image with EXIF data
    temp_file = Tempfile.new(['test_with_exif', '.jpg'])
    temp_file.binmode
    
    # JPEG with basic EXIF header
    jpeg_with_exif = create_jpeg_with_basic_exif
    temp_file.write(jpeg_with_exif)
    temp_file.rewind
    
    ActionDispatch::Http::UploadedFile.new(
      tempfile: temp_file,
      filename: 'photo_with_exif.jpg',
      type: 'image/jpeg'
    )
  end

  def create_virus_signature_file
    # Creates a file with a fake virus signature for testing
    temp_file = Tempfile.new(['fake_virus', '.exe'])
    temp_file.write('MZ' + 'X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*')
    temp_file.rewind
    
    ActionDispatch::Http::UploadedFile.new(
      tempfile: temp_file,
      filename: 'fake_virus.exe',
      type: 'application/octet-stream'
    )
  end

  # Performance testing helpers
  def measure_response_time(&block)
    start_time = Time.current
    yield
    end_time = Time.current
    end_time - start_time
  end

  def expect_fast_response(max_time = 1.second, &block)
    response_time = measure_response_time(&block)
    expect(response_time).to be < max_time
  end

  # Memory testing helpers
  def measure_memory_usage(&block)
    start_memory = memory_usage
    yield
    end_memory = memory_usage
    end_memory - start_memory
  end

  def memory_usage
    `ps -o rss= -p #{Process.pid}`.to_i * 1024 # Convert KB to bytes
  end

  # Authentication helpers for different scenarios
  def authenticate_as_admin
    admin = create(:photographer, :admin) if respond_to?(:admin)
    sign_in(admin || create(:photographer))
  end

  def authenticate_with_expired_session
    photographer = create(:photographer)
    sign_in(photographer)
    session[:login_time] = 5.hours.ago.to_s
  end

  def authenticate_from_different_ip
    photographer = create(:photographer)
    sign_in(photographer)
    session[:ip_address] = '127.0.0.1'
    allow_any_instance_of(ActionDispatch::Request).to receive(:remote_ip).and_return('192.168.1.100')
  end

  # Data generation helpers
  def generate_random_string(length = 10, charset = :alphanumeric)
    case charset
    when :alphanumeric
      chars = ('a'..'z').to_a + ('A'..'Z').to_a + (0..9).to_a
    when :alpha
      chars = ('a'..'z').to_a + ('A'..'Z').to_a
    when :numeric
      chars = (0..9).to_a
    when :special
      chars = %w[! @ # $ % ^ & * ( ) - _ = + [ ] { } | ; : ' " , . < > / ?]
    else
      chars = charset
    end
    
    Array.new(length) { chars.sample }.join
  end

  def generate_test_email
    "test_#{SecureRandom.hex(8)}@example.com"
  end

  def generate_secure_password
    "Secure#{SecureRandom.hex(4).capitalize}!"
  end

  # Concurrency testing helpers
  def run_concurrent_test(thread_count = 5, &block)
    threads = []
    results = Queue.new
    
    thread_count.times do
      threads << Thread.new do
        begin
          result = yield
          results << { success: true, result: result }
        rescue => e
          results << { success: false, error: e }
        end
      end
    end
    
    threads.each(&:join)
    
    # Collect results
    collected_results = []
    thread_count.times do
      collected_results << results.pop
    end
    
    collected_results
  end

  private

  def simulate_brute_force_attack(options)
    target_endpoint = options[:endpoint] || '/login'
    attempts = options[:attempts] || 20
    
    attempts.times do |i|
      post target_endpoint, params: {
        photographer: {
          email: 'target@example.com',
          password: "attempt_#{i}"
        }
      }
    end
  end

  def simulate_dos_attack(options)
    target_endpoint = options[:endpoint] || '/'
    requests = options[:requests] || 100
    
    requests.times do
      get target_endpoint
    end
  end

  def simulate_sql_injection_attack(options)
    injection_payloads = [
      "'; DROP TABLE galleries; --",
      "' OR '1'='1",
      "'; INSERT INTO photographers (email) VALUES ('hacker@evil.com'); --"
    ]
    
    injection_payloads.each do |payload|
      post options[:endpoint], params: {
        options[:parameter] => payload
      }
    end
  end

  def simulate_xss_attack(options)
    xss_payloads = [
      '<script>alert("XSS")</script>',
      '<img src=x onerror=alert("XSS")>',
      'javascript:alert("XSS")',
      '<svg onload=alert("XSS")>'
    ]
    
    xss_payloads.each do |payload|
      post options[:endpoint], params: {
        options[:parameter] => payload
      }
    end
  end

  def create_jpeg_with_basic_exif
    # Simplified JPEG with EXIF marker
    jpeg_header = [0xFF, 0xD8, 0xFF, 0xE1].pack('C*') # SOI + APP1
    exif_size = [0x00, 0x20].pack('n') # Size of EXIF data
    exif_id = "Exif\x00\x00"
    minimal_exif = "\x00" * 26 # Minimal EXIF data
    jpeg_body = "\x00" * 100
    jpeg_footer = [0xFF, 0xD9].pack('C*') # EOI
    
    jpeg_header + exif_size + exif_id + minimal_exif + jpeg_body + jpeg_footer
  end
end

RSpec.configure do |config|
  config.include TestUtilities
  
  config.before(:each) do
    # Clear any mocked external services
    allow(ImageProcessingJob).to receive(:perform_later).and_call_original
  end
  
  config.around(:each, :with_clean_database) do |example|
    with_clean_database { example.run }
  end
  
  config.around(:each, :freeze_time) do |example|
    freeze_time { example.run }
  end
end