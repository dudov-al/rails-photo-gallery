module SecurityHelpers
  def sign_in(photographer)
    session[:photographer_id] = photographer.id
    session[:login_time] = Time.current.to_s
    session[:ip_address] = request.remote_ip if respond_to?(:request)
    session[:user_agent] = request.user_agent if respond_to?(:request) && request.user_agent
  end
  
  def sign_out(photographer = nil)
    session.delete(:photographer_id)
    session.delete(:login_time)
    session.delete(:ip_address)
    session.delete(:user_agent)
  end
  
  def authenticate_to_gallery(gallery, password = nil)
    password ||= gallery.password
    session["gallery_#{gallery.id}_authenticated"] = true
    session["gallery_#{gallery.id}_auth_time"] = Time.current.to_i
    session["gallery_#{gallery.id}_ip"] = '127.0.0.1'
    session["gallery_#{gallery.id}_user_agent"] = 'Test Browser'
  end
  
  def create_malicious_file(filename, content_type = 'text/plain')
    temp_file = Tempfile.new([File.basename(filename, '.*'), File.extname(filename)])
    temp_file.write('<script>alert("XSS")</script>')
    temp_file.rewind
    
    ActionDispatch::Http::UploadedFile.new(
      tempfile: temp_file,
      filename: filename,
      type: content_type
    )
  end
  
  def create_valid_image_file(filename = 'test.jpg')
    # Create minimal valid JPEG
    jpeg_content = [
      0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46,
      0x49, 0x46, 0x00, 0x01, 0x01, 0x01, 0x00, 0x48,
      0x00, 0x48, 0x00, 0x00, 0xFF, 0xDB, 0x00, 0x43
    ].pack('C*') + "\x00" * 100 + [0xFF, 0xD9].pack('C*')
    
    temp_file = Tempfile.new([File.basename(filename, '.*'), File.extname(filename)])
    temp_file.binmode
    temp_file.write(jpeg_content)
    temp_file.rewind
    
    ActionDispatch::Http::UploadedFile.new(
      tempfile: temp_file,
      filename: filename,
      type: 'image/jpeg'
    )
  end
  
  def expect_security_event(event_type, additional_checks = {})
    expect(SecurityAuditLogger).to receive(:log) do |args|
      expect(args[:event_type]).to eq(event_type)
      additional_checks.each do |key, expected_value|
        case expected_value
        when Proc
          expect(expected_value.call(args[key])).to be true
        when Regexp
          expect(args[key]).to match(expected_value)
        else
          expect(args[key]).to eq(expected_value)
        end
      end
    end
  end
  
  def simulate_rate_limit_exceeded(path, params = {})
    # Make requests to trigger rate limiting
    15.times do
      case path
      when '/login'
        post path, params: params
      when /\/g\/.*\/auth/
        post path, params: params
      else
        get path, params: params
      end
    end
  end
  
  def with_security_disabled(&block)
    # Temporarily disable security checks for testing
    allow_any_instance_of(ApplicationController).to receive(:sanitize_params)
    allow_any_instance_of(ApplicationController).to receive(:detect_malicious_input)
    
    yield
  ensure
    # Re-enable security checks
    allow_any_instance_of(ApplicationController).to receive(:sanitize_params).and_call_original
    allow_any_instance_of(ApplicationController).to receive(:detect_malicious_input).and_call_original
  end
  
  def bypass_csrf_protection
    # For API testing
    allow_any_instance_of(ApplicationController).to receive(:verify_authenticity_token)
  end
  
  def mock_ip_address(ip)
    allow_any_instance_of(ActionDispatch::Request).to receive(:remote_ip).and_return(ip)
  end
  
  def expect_blocked_request(expected_status = 403)
    expect(response.status).to eq(expected_status)
    
    if response.content_type.include?('application/json')
      body = JSON.parse(response.body)
      expect(body).to have_key('error')
    end
  end
  
  def expect_security_headers
    security_headers = [
      'X-Frame-Options',
      'X-Content-Type-Options',
      'X-XSS-Protection',
      'Referrer-Policy',
      'X-Security-Policy'
    ]
    
    security_headers.each do |header|
      expect(response.headers[header]).to be_present
    end
  end
  
  def simulate_session_hijacking(gallery = nil)
    if gallery
      # Authenticate with one user agent
      post "/g/#{gallery.slug}/auth", 
           params: { password: gallery.password },
           headers: { 'User-Agent' => 'Original Browser' }
      
      # Access with different user agent
      get "/g/#{gallery.slug}",
          headers: { 'User-Agent' => 'Malicious Browser' }
    else
      # For photographer sessions
      photographer = create(:photographer)
      post '/login',
           params: { photographer: { email: photographer.email, password: 'ValidPassword123!' } },
           headers: { 'User-Agent' => 'Original Browser' }
      
      get '/galleries',
          headers: { 'User-Agent' => 'Malicious Browser' }
    end
  end
  
  def simulate_expired_session(gallery = nil)
    if gallery
      authenticate_to_gallery(gallery)
      session["gallery_#{gallery.id}_auth_time"] = 3.hours.ago.to_i
      get "/g/#{gallery.slug}"
    else
      photographer = create(:photographer)
      sign_in(photographer)
      session[:login_time] = 5.hours.ago.to_s
      get '/galleries'
    end
  end
end

RSpec.configure do |config|
  config.include SecurityHelpers, type: :request
  config.include SecurityHelpers, type: :controller
end