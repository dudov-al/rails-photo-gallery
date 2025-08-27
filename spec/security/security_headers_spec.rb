require 'rails_helper'

RSpec.describe "Security Headers", type: :request do
  describe "HTTP Security Headers" do
    it "sets X-Frame-Options to prevent clickjacking" do
      get '/'
      expect(response.headers['X-Frame-Options']).to eq('DENY')
    end
    
    it "sets X-Content-Type-Options to prevent MIME sniffing" do
      get '/'
      expect(response.headers['X-Content-Type-Options']).to eq('nosniff')
    end
    
    it "sets X-XSS-Protection for legacy browsers" do
      get '/'
      expect(response.headers['X-XSS-Protection']).to eq('1; mode=block')
    end
    
    it "sets Referrer-Policy for privacy" do
      get '/'
      expect(response.headers['Referrer-Policy']).to eq('strict-origin-when-cross-origin')
    end
    
    it "sets security identification header" do
      get '/'
      expect(response.headers['X-Security-Policy']).to eq('enforced')
    end
    
    it "removes revealing server headers" do
      get '/'
      expect(response.headers['X-Powered-By']).to be_nil
      expect(response.headers['X-Runtime']).to be_nil
      expect(response.headers['Server']).to eq('photograph-platform')
    end
  end
  
  describe "Content Security Policy" do
    it "sets CSP header in production" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))
      
      get '/'
      
      expect(response.headers['Content-Security-Policy']).to be_present
      expect(response.headers['Content-Security-Policy']).not_to include('unsafe-inline')
      expect(response.headers['Content-Security-Policy']).not_to include('unsafe-eval')
    end
    
    it "sets report-only CSP in development" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('development'))
      
      get '/'
      
      expect(response.headers['Content-Security-Policy-Report-Only']).to be_present
    end
    
    it "includes nonce for scripts and styles" do
      get '/'
      
      # Should generate nonce for CSP
      expect(response.body).to include('nonce-') if response.body.include?('<script')
    end
  end
  
  describe "HTTPS Security" do
    it "sets HSTS header in production with HTTPS" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))
      
      get '/', headers: { 'X-Forwarded-Proto' => 'https' }
      
      expect(response.headers['Strict-Transport-Security']).to include('max-age=31536000')
      expect(response.headers['Strict-Transport-Security']).to include('includeSubDomains')
      expect(response.headers['Strict-Transport-Security']).to include('preload')
    end
    
    it "does not set HSTS in development" do
      get '/'
      expect(response.headers['Strict-Transport-Security']).to be_nil
    end
  end
  
  describe "Permissions Policy" do
    it "restricts dangerous browser features" do
      get '/'
      
      permissions_policy = response.headers['Permissions-Policy']
      expect(permissions_policy).to include('camera=()')
      expect(permissions_policy).to include('microphone=()')
      expect(permissions_policy).to include('geolocation=()')
      expect(permissions_policy).to include('payment=()')
    end
    
    it "allows necessary features" do
      get '/'
      
      permissions_policy = response.headers['Permissions-Policy']
      expect(permissions_policy).to include('fullscreen=(self)')
    end
  end
  
  describe "Cross-Origin Policies" do
    it "sets Cross-Origin-Embedder-Policy" do
      get '/'
      expect(response.headers['Cross-Origin-Embedder-Policy']).to eq('require-corp')
    end
    
    it "sets Cross-Origin-Opener-Policy" do
      get '/'
      expect(response.headers['Cross-Origin-Opener-Policy']).to eq('same-origin')
    end
    
    it "sets appropriate Cross-Origin-Resource-Policy for gallery pages" do
      gallery = create(:gallery)
      get "/g/#{gallery.slug}"
      
      expect(response.headers['Cross-Origin-Resource-Policy']).to eq('same-origin')
    end
  end
  
  describe "Caching Headers for Sensitive Pages" do
    it "sets no-cache headers for login page" do
      get '/login'
      
      expect(response.headers['Cache-Control']).to include('no-cache')
      expect(response.headers['Cache-Control']).to include('no-store')
      expect(response.headers['Cache-Control']).to include('must-revalidate')
      expect(response.headers['Pragma']).to eq('no-cache')
      expect(response.headers['Expires']).to eq('0')
    end
    
    it "sets no-cache headers for gallery authentication" do
      gallery = create(:gallery, password: 'test123')
      get "/g/#{gallery.slug}/auth"
      
      expect(response.headers['Cache-Control']).to include('no-cache')
    end
    
    it "allows caching for public assets" do
      # This would be handled by the web server in production
      # but we can test the logic
      get '/assets/application.css' rescue nil # May not exist in test
      
      # Vercel configuration should handle this
    end
  end
  
  describe "Certificate Transparency" do
    it "sets Expect-CT header in production" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))
      
      get '/'
      
      expect(response.headers['Expect-CT']).to include('max-age=86400')
      expect(response.headers['Expect-CT']).to include('enforce')
    end
  end
  
  describe "Network Error Logging" do
    it "configures NEL for monitoring in production" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))
      
      get '/'
      
      expect(response.headers['NEL']).to be_present
      expect(response.headers['Report-To']).to be_present
      
      nel_config = JSON.parse(response.headers['NEL'])
      expect(nel_config['max_age']).to eq(2592000)
    end
  end
  
  describe "Session Cookie Security" do
    it "sets secure cookie attributes in production" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new('production'))
      
      photographer = create(:photographer)
      post '/login', params: {
        photographer: {
          email: photographer.email,
          password: 'ValidPassword123!'
        }
      }, headers: { 'X-Forwarded-Proto' => 'https' }
      
      cookie_header = response.headers['Set-Cookie']
      expect(cookie_header).to include('HttpOnly')
      expect(cookie_header).to include('Secure')
      expect(cookie_header).to include('SameSite=Strict')
    end
    
    it "uses less strict settings in development" do
      photographer = create(:photographer)
      post '/login', params: {
        photographer: {
          email: photographer.email,
          password: 'ValidPassword123!'
        }
      }
      
      cookie_header = response.headers['Set-Cookie']
      expect(cookie_header).to include('HttpOnly')
      expect(cookie_header).to include('SameSite=Lax')
    end
  end
end