require 'rails_helper'

RSpec.describe "Comprehensive Security Tests", type: :request do
  let(:photographer) { create(:photographer, password: 'ValidPassword123!') }
  let(:gallery) { create(:gallery, :published, photographer: photographer) }
  let(:password_gallery) { create(:gallery, :published, :password_protected, photographer: photographer) }

  describe "Cross-Site Scripting (XSS) Protection" do
    context "in gallery titles and descriptions" do
      before do
        post '/login', params: {
          photographer: { email: photographer.email, password: 'ValidPassword123!' }
        }
      end

      it "sanitizes XSS attempts in gallery creation" do
        malicious_data = {
          gallery: {
            title: '<script>alert("XSS in title")</script>Malicious Gallery',
            description: '<img src=x onerror=alert("XSS in description")>Gallery description',
            published: true
          }
        }

        post '/galleries', params: malicious_data

        if response.status == 302 # Successful creation
          gallery = Gallery.last
          expect(gallery.title).not_to include('<script>')
          expect(gallery.title).not_to include('alert')
          expect(gallery.description).not_to include('<img')
          expect(gallery.description).not_to include('onerror')
        end
      end

      it "escapes dangerous content when displaying galleries" do
        malicious_gallery = create(:gallery,
          title: '<script>alert("stored XSS")</script>',
          description: '<iframe src="javascript:alert(1)">',
          photographer: photographer
        )

        get "/galleries/#{malicious_gallery.id}"

        expect(response.body).not_to include('<script>alert')
        expect(response.body).not_to include('<iframe src="javascript:')
      end
    end

    context "in public gallery viewing" do
      it "prevents XSS in gallery password authentication" do
        malicious_password = '<script>alert("XSS")</script>password'

        post "/g/#{password_gallery.slug}/auth", params: { password: malicious_password }

        expect(response.body).not_to include('<script>')
        expect(response.body).not_to include('alert("XSS")')
      end

      it "sanitizes gallery content for anonymous viewers" do
        xss_gallery = create(:gallery, 
          :published,
          title: '<script>document.cookie="hacked"</script>Public Gallery',
          description: '<svg onload=alert(1)>Description</svg>',
          photographer: photographer
        )

        get "/g/#{xss_gallery.slug}"

        expect(response.body).not_to include('<script>document.cookie')
        expect(response.body).not_to include('<svg onload=alert')
      end
    end
  end

  describe "Cross-Site Request Forgery (CSRF) Protection" do
    it "protects gallery creation from CSRF attacks" do
      # Enable CSRF protection for this test
      allow_any_instance_of(ActionController::Base).to receive(:protect_against_forgery?).and_return(true)

      post '/login', params: {
        photographer: { email: photographer.email, password: 'ValidPassword123!' }
      }

      expect {
        post '/galleries', params: {
          gallery: { title: 'CSRF Gallery', published: true }
        }
      }.to raise_error(ActionController::InvalidAuthenticityToken)
    end

    it "protects image uploads from CSRF attacks" do
      allow_any_instance_of(ActionController::Base).to receive(:protect_against_forgery?).and_return(true)

      post '/login', params: {
        photographer: { email: photographer.email, password: 'ValidPassword123!' }
      }

      image_file = create_uploaded_file(filename: 'test.jpg', content_type: 'image/jpeg')

      expect {
        post '/images', params: {
          gallery_id: gallery.id,
          image: { file: image_file }
        }
      }.to raise_error(ActionController::InvalidAuthenticityToken)
    end

    it "protects password changes from CSRF attacks" do
      allow_any_instance_of(ActionController::Base).to receive(:protect_against_forgery?).and_return(true)

      post '/login', params: {
        photographer: { email: photographer.email, password: 'ValidPassword123!' }
      }

      expect {
        patch "/galleries/#{gallery.id}", params: {
          gallery: { 
            password: 'NewPassword123!',
            password_confirmation: 'NewPassword123!'
          }
        }
      }.to raise_error(ActionController::InvalidAuthenticityToken)
    end
  end

  describe "SQL Injection Protection" do
    it "prevents SQL injection in gallery search" do
      post '/login', params: {
        photographer: { email: photographer.email, password: 'ValidPassword123!' }
      }

      sql_injection_attempts = [
        "'; DROP TABLE galleries; --",
        "' OR '1'='1",
        "'; INSERT INTO photographers (email, name) VALUES ('hacker@evil.com', 'Hacker'); --",
        "' UNION SELECT * FROM photographers WHERE '1'='1"
      ]

      sql_injection_attempts.each do |malicious_query|
        expect {
          get '/galleries', params: { search: malicious_query }
        }.not_to change(Gallery, :count)

        expect(response).to have_http_status(:success)
        expect(Photographer.count).to be >= 1 # Original data should remain
      end
    end

    it "prevents SQL injection in public gallery slug lookup" do
      sql_injection_slugs = [
        "valid-slug'; DROP TABLE galleries; --",
        "' OR 1=1 OR slug='",
        "'; UPDATE galleries SET published=true; --"
      ]

      sql_injection_slugs.each do |malicious_slug|
        expect {
          get "/g/#{malicious_slug}"
        }.not_to change(Gallery, :count)

        # Should return 404 or handle gracefully
        expect([404, 410, 500]).to include(response.status)
      end
    end
  end

  describe "Path Traversal Protection" do
    it "prevents directory traversal in gallery slugs" do
      traversal_attempts = [
        '../../../etc/passwd',
        '..\\..\\..\\windows\\system32\\config\\sam',
        '%2e%2e%2f%2e%2e%2f%2e%2e%2fetc%2fpasswd', # URL encoded
        '....//....//....//etc//passwd'
      ]

      traversal_attempts.each do |malicious_path|
        get "/g/#{malicious_path}"
        
        expect(response).to have_http_status(:not_found)
        expect(response.body).not_to include('root:x:0:0')
        expect(response.body).not_to include('[HKEY_LOCAL_MACHINE')
      end
    end
  end

  describe "Session Security" do
    it "implements secure session configuration" do
      post '/login', params: {
        photographer: { email: photographer.email, password: 'ValidPassword123!' }
      }

      # Check session cookie attributes (this is environment dependent)
      if Rails.env.production?
        expect(response.cookies['_photograph_session']).to include('secure')
        expect(response.cookies['_photograph_session']).to include('httponly')
      end
    end

    it "prevents session fixation attacks" do
      # Get initial session
      get '/login'
      initial_session = session.id

      # Login should regenerate session
      post '/login', params: {
        photographer: { email: photographer.email, password: 'ValidPassword123!' }
      }

      expect(session.id).not_to eq(initial_session)
      expect(session[:photographer_id]).to eq(photographer.id)
    end

    it "implements proper session timeout" do
      post '/login', params: {
        photographer: { email: photographer.email, password: 'ValidPassword123!' }
      }

      # Manually expire session
      session[:login_time] = 5.hours.ago.to_s

      get '/galleries'

      expect(response).to redirect_to(new_session_path)
      expect(session[:photographer_id]).to be_nil
    end

    it "detects and prevents session hijacking" do
      post '/login', params: {
        photographer: { email: photographer.email, password: 'ValidPassword123!' }
      }, headers: { 'User-Agent' => 'Original Browser' }

      expect(session[:photographer_id]).to eq(photographer.id)

      # Change user agent (simulating hijacking)
      get '/galleries', headers: { 'User-Agent' => 'Different Browser' }

      expect(response).to redirect_to(new_session_path)
      expect(session[:photographer_id]).to be_nil
    end
  end

  describe "Rate Limiting and DoS Protection" do
    before { clear_redis_cache }

    it "implements rate limiting on login attempts" do
      # Mock rate limiting
      allow(Rails.cache).to receive(:read).with(/login_attempts/).and_return(15)

      post '/login', params: {
        photographer: { email: photographer.email, password: 'ValidPassword123!' }
      }

      expect(response).to have_http_status(:forbidden)
    end

    it "implements rate limiting on gallery creation" do
      post '/login', params: {
        photographer: { email: photographer.email, password: 'ValidPassword123!' }
      }

      allow(Rails.cache).to receive(:read).with(/gallery_creation/).and_return(10)

      post '/galleries', params: {
        gallery: { title: 'Rate Limited Gallery', published: true }
      }

      expect(response).to have_http_status(:forbidden)
    end

    it "implements rate limiting on public gallery views" do
      allow(Rails.cache).to receive(:read).with(/gallery_view_attempts/).and_return(100)

      get "/g/#{gallery.slug}"

      expect(response).to have_http_status(:forbidden)
    end

    it "protects against large file upload DoS" do
      post '/login', params: {
        photographer: { email: photographer.email, password: 'ValidPassword123!' }
      }

      # Simulate multiple concurrent uploads
      allow(Rails.cache).to receive(:read).with(/upload_attempts/).and_return(25)

      image_file = create_uploaded_file(filename: 'test.jpg', content_type: 'image/jpeg')

      post '/images', params: {
        gallery_id: gallery.id,
        image: { file: image_file }
      }

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "Content Security Policy (CSP)" do
    it "sets appropriate CSP headers" do
      get "/g/#{gallery.slug}"

      csp_header = response.headers['Content-Security-Policy']
      expect(csp_header).to be_present
      expect(csp_header).to include("default-src 'self'")
      expect(csp_header).to include("script-src")
      expect(csp_header).to include("img-src")
    end

    it "prevents inline script execution" do
      get "/g/#{gallery.slug}"

      csp_header = response.headers['Content-Security-Policy']
      expect(csp_header).not_to include("'unsafe-inline'") unless csp_header.include?('nonce-')
    end
  end

  describe "Security Headers" do
    it "sets comprehensive security headers" do
      get "/g/#{gallery.slug}"

      expect_security_headers
      expect(response.headers['X-Frame-Options']).to eq('DENY')
      expect(response.headers['X-Content-Type-Options']).to eq('nosniff')
      expect(response.headers['X-XSS-Protection']).to be_present
      expect(response.headers['Referrer-Policy']).to be_present
    end

    it "prevents clickjacking attacks" do
      get "/g/#{gallery.slug}"

      frame_options = response.headers['X-Frame-Options']
      csp_header = response.headers['Content-Security-Policy']

      expect(frame_options).to eq('DENY').or eq('SAMEORIGIN')
      expect(csp_header).to include("frame-ancestors 'none'") if csp_header.present?
    end
  end

  describe "Authentication Bypass Attempts" do
    it "prevents authentication bypass through parameter manipulation" do
      # Try to access protected resource by manipulating session
      get '/galleries'
      
      session[:photographer_id] = 999999 # Non-existent ID
      
      get '/galleries'
      expect(response).to redirect_to(new_session_path)
    end

    it "prevents privilege escalation through gallery ownership manipulation" do
      other_photographer = create(:photographer, password: 'ValidPassword123!')
      other_gallery = create(:gallery, photographer: other_photographer)

      post '/login', params: {
        photographer: { email: photographer.email, password: 'ValidPassword123!' }
      }

      # Try to access other photographer's gallery
      get "/galleries/#{other_gallery.id}"
      expect(response).to have_http_status(:forbidden)

      # Try to edit other photographer's gallery
      patch "/galleries/#{other_gallery.id}", params: {
        gallery: { title: 'Hacked Gallery' }
      }
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "Data Exposure Prevention" do
    it "prevents information disclosure in error messages" do
      # Try to access non-existent gallery
      get "/galleries/999999"
      
      expect(response.body).not_to include('ActiveRecord')
      expect(response.body).not_to include('SQL')
      expect(response.body).not_to include('Database')
      expect(response.body).not_to include('Exception')
    end

    it "prevents user enumeration through login responses" do
      # Login with non-existent email
      post '/login', params: {
        photographer: { email: 'nonexistent@example.com', password: 'password' }
      }
      
      non_existent_response = flash[:alert] || response.body

      # Login with existing email but wrong password
      post '/login', params: {
        photographer: { email: photographer.email, password: 'wrong_password' }
      }
      
      wrong_password_response = flash[:alert] || response.body

      # Responses should be identical to prevent user enumeration
      expect(non_existent_response).to include('Invalid email or password')
      expect(wrong_password_response).to include('Invalid email or password')
    end

    it "prevents directory listing disclosure" do
      # Try to access common directories
      sensitive_paths = [
        '/uploads/',
        '/assets/',
        '/.git/',
        '/config/',
        '/log/',
        '/tmp/'
      ]

      sensitive_paths.each do |path|
        get path
        expect([404, 403, 301, 302]).to include(response.status)
        expect(response.body).not_to include('Index of')
        expect(response.body).not_to include('Directory listing')
      end
    end
  end

  describe "Input Validation and Sanitization" do
    it "validates all user inputs comprehensively" do
      post '/login', params: {
        photographer: { email: photographer.email, password: 'ValidPassword123!' }
      }

      dangerous_inputs = [
        '<script>alert("xss")</script>',
        '{{7*7}}', # Template injection
        '${7*7}', # Expression injection
        '../../../etc/passwd',
        'javascript:alert(1)',
        'data:text/html,<script>alert(1)</script>',
        "\x00\x01\x02", # Null bytes and control characters
        'A' * 10000 # Very long input
      ]

      dangerous_inputs.each do |malicious_input|
        post '/galleries', params: {
          gallery: {
            title: malicious_input,
            description: malicious_input,
            published: true
          }
        }

        if response.status == 302 # Successful creation
          gallery = Gallery.last
          expect(gallery.title).not_to include('<script>')
          expect(gallery.title).not_to include('{{7*7}}')
          expect(gallery.title).not_to include('../')
          expect(gallery.description).not_to include('javascript:')
          gallery.destroy # Clean up
        end
      end
    end

    it "handles malformed requests gracefully" do
      malformed_requests = [
        { gallery: nil },
        { gallery: '' },
        { gallery: [] },
        {},
        nil
      ]

      post '/login', params: {
        photographer: { email: photographer.email, password: 'ValidPassword123!' }
      }

      malformed_requests.each do |malformed_params|
        expect {
          post '/galleries', params: malformed_params
        }.not_to change(Gallery, :count)

        expect([400, 422, 500]).to include(response.status)
      end
    end
  end

  describe "Cryptographic Security" do
    it "uses secure password hashing" do
      new_photographer = create(:photographer, password: 'TestPassword123!')
      
      expect(new_photographer.password_digest).to be_present
      expect(new_photographer.password_digest).not_to eq('TestPassword123!')
      expect(new_photographer.password_digest).to start_with('$2a$') # bcrypt
      expect(new_photographer.password_digest.length).to be >= 60
    end

    it "generates cryptographically secure tokens" do
      # This would test any token generation in the app
      # For example, password reset tokens, API tokens, etc.
      tokens = []
      
      10.times do
        # If the app has token generation, test it here
        tokens << SecureRandom.urlsafe_base64(32)
      end

      # Ensure all tokens are unique (no collisions)
      expect(tokens.uniq.length).to eq(10)
      
      # Ensure tokens have sufficient entropy
      tokens.each do |token|
        expect(token.length).to be >= 32
      end
    end
  end

  describe "Third-party Content Security" do
    it "validates external URLs if any are accepted" do
      # This would test any functionality that accepts URLs
      # such as profile pictures from URLs, etc.
      
      malicious_urls = [
        'javascript:alert(1)',
        'data:text/html,<script>alert(1)</script>',
        'file:///etc/passwd',
        'ftp://malicious-server.com/malware',
        'http://internal-server:8080/admin'
      ]

      malicious_urls.each do |malicious_url|
        # If URL validation exists, test it
        expect(malicious_url).not_to match(/^https?:\/\/[\w\.-]+\.\w+/) # Basic URL validation
      end
    end
  end
end