require 'rails_helper'

RSpec.describe "Input Sanitization", type: :request do
  let(:photographer) { create(:photographer) }
  
  describe "XSS Prevention" do
    it "sanitizes malicious scripts in gallery titles" do
      sign_in photographer
      
      malicious_title = "<script>alert('XSS')</script>Gallery Title"
      
      post '/galleries', params: {
        gallery: {
          title: malicious_title,
          description: "Test description"
        }
      }
      
      expect(response.status).to eq(422)
      # Should be blocked by malicious input detection
    end
    
    it "sanitizes JavaScript URLs" do
      sign_in photographer
      
      malicious_url = "javascript:alert('XSS')"
      
      post '/galleries', params: {
        gallery: {
          title: "Test Gallery",
          description: "Visit my site: #{malicious_url}"
        }
      }
      
      expect(response.status).to eq(422)
    end
    
    it "removes dangerous HTML attributes" do
      sign_in photographer
      
      malicious_description = '<p onload="alert(\'XSS\')">Description</p>'
      
      post '/galleries', params: {
        gallery: {
          title: "Test Gallery",
          description: malicious_description
        }
      }
      
      expect(response.status).to eq(422)
    end
  end
  
  describe "SQL Injection Prevention" do
    it "detects SQL injection in search parameters" do
      sign_in photographer
      
      malicious_search = "'; DROP TABLE photographers; --"
      
      get '/galleries', params: { search: malicious_search }
      
      expect(response.status).to eq(403) # Should be blocked
    end
    
    it "sanitizes UNION-based SQL injection" do
      sign_in photographer
      
      malicious_input = "1' UNION SELECT password FROM photographers--"
      
      get '/galleries', params: { q: malicious_input }
      
      expect(response.status).to eq(403)
    end
  end
  
  describe "Path Traversal Prevention" do
    it "blocks path traversal in filenames" do
      sign_in photographer
      
      malicious_filename = "../../../etc/passwd"
      sanitized = InputSanitizer.sanitize_filename(malicious_filename)
      
      expect(sanitized).not_to include('../')
      expect(sanitized).to match(/\A\w+\.\w+\z/)
    end
    
    it "prevents directory traversal in parameters" do
      sign_in photographer
      
      malicious_path = "../../../../etc/passwd"
      
      get '/galleries', params: { file: malicious_path }
      
      expect(response.status).to eq(403)
    end
  end
  
  describe "Command Injection Prevention" do
    it "detects command injection patterns" do
      command_injections = [
        "; ls -la",
        "| cat /etc/passwd",
        "&& rm -rf /",
        "`whoami`",
        "$(id)"
      ]
      
      command_injections.each do |injection|
        threats = InputSanitizer.detect_threats(injection)
        expect(threats).to include('COMMAND_INJECTION_ATTEMPT')
      end
    end
  end
  
  describe "Email Sanitization" do
    it "validates email format" do
      valid_emails = [
        'user@example.com',
        'test.user@domain.co.uk',
        'user+tag@example.org'
      ]
      
      invalid_emails = [
        '<script>alert("xss")</script>@example.com',
        'user@exam<script>ple.com',
        'user"@example.com',
        'user@',
        '@example.com',
        'plainaddress'
      ]
      
      valid_emails.each do |email|
        result = InputSanitizer.sanitize_email(email)
        expect(result).to eq(email.downcase)
      end
      
      invalid_emails.each do |email|
        result = InputSanitizer.sanitize_email(email)
        expect(result).to be_nil
      end
    end
  end
  
  describe "URL Sanitization" do
    it "validates URL schemes" do
      valid_urls = [
        'https://example.com',
        'http://subdomain.example.org/path'
      ]
      
      invalid_urls = [
        'javascript:alert("xss")',
        'data:text/html,<script>alert("xss")</script>',
        'ftp://example.com',
        'file:///etc/passwd',
        'mailto:user@example.com'
      ]
      
      valid_urls.each do |url|
        result = InputSanitizer.sanitize_url(url)
        expect(result).to eq(url)
      end
      
      invalid_urls.each do |url|
        result = InputSanitizer.sanitize_url(url)
        expect(result).to be_nil
      end
    end
    
    it "blocks dangerous domains" do
      dangerous_urls = [
        'http://localhost/admin',
        'https://127.0.0.1/internal',
        'http://192.168.1.1/router',
        'https://10.0.0.1/private'
      ]
      
      dangerous_urls.each do |url|
        result = InputSanitizer.sanitize_url(url)
        expect(result).to be_nil
      end
    end
  end
  
  describe "Gallery Password Security" do
    it "enforces strong gallery passwords" do
      sign_in photographer
      
      weak_passwords = [
        'weak',
        '12345678',
        'password',
        'Password',
        'PASSWORD123'
      ]
      
      weak_passwords.each do |weak_password|
        post '/galleries', params: {
          gallery: {
            title: "Test Gallery",
            password: weak_password
          }
        }
        
        expect(response.status).to eq(422)
        gallery = Gallery.new(password: weak_password)
        gallery.valid?
        expect(gallery.errors[:password]).to be_present
      end
    end
    
    it "accepts strong gallery passwords" do
      sign_in photographer
      
      strong_passwords = [
        'StrongGallery123!',
        'MySecure@Pass99',
        'Complex#Password456'
      ]
      
      strong_passwords.each do |strong_password|
        gallery = build(:gallery, password: strong_password)
        expect(gallery).to be_valid
      end
    end
  end
  
  describe "Security Logging" do
    it "logs malicious input attempts" do
      expect(SecurityAuditLogger).to receive(:log).with(
        event_type: 'malicious_input_detected',
        hash_including(
          photographer_id: nil,
          additional_data: hash_including(:threats)
        )
      )
      
      get '/', params: { malicious: "<script>alert('xss')</script>" }
    end
  end
end