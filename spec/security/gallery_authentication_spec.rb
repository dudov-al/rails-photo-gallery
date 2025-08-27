require 'rails_helper'

RSpec.describe "Gallery Authentication Security", type: :request do
  let(:gallery) { create(:gallery, password: 'SecureGallery123!') }
  
  describe "Gallery Password Authentication" do
    it "requires password for protected galleries" do
      get "/g/#{gallery.slug}"
      
      expect(response.status).to eq(401)
      expect(response.body).to include('password')
    end
    
    it "allows access with correct password" do
      post "/g/#{gallery.slug}/auth", params: { password: 'SecureGallery123!' }
      
      expect(response).to redirect_to(public_gallery_path(gallery.slug))
      expect(session["gallery_#{gallery.id}_authenticated"]).to be true
    end
    
    it "blocks access with incorrect password" do
      post "/g/#{gallery.slug}/auth", params: { password: 'wrong_password' }
      
      expect(response.status).to eq(401)
      expect(session["gallery_#{gallery.id}_authenticated"]).to be_falsy
    end
    
    it "sets secure session attributes on authentication" do
      post "/g/#{gallery.slug}/auth", params: { password: 'SecureGallery123!' }
      
      expect(session["gallery_#{gallery.id}_authenticated"]).to be true
      expect(session["gallery_#{gallery.id}_auth_time"]).to be_present
      expect(session["gallery_#{gallery.id}_ip"]).to eq('127.0.0.1')
      expect(session["gallery_#{gallery.id}_user_agent"]).to be_present
    end
  end
  
  describe "Session Security" do
    before do
      # Authenticate to gallery
      post "/g/#{gallery.slug}/auth", params: { password: 'SecureGallery123!' }
    end
    
    it "expires gallery session after timeout" do
      # Simulate old session
      session["gallery_#{gallery.id}_auth_time"] = 3.hours.ago.to_i
      
      get "/g/#{gallery.slug}"
      
      expect(response.status).to eq(401)
      expect(response.body).to include('password')
    end
    
    it "detects session hijacking attempts" do
      # Authenticate with one user agent
      post "/g/#{gallery.slug}/auth", 
           params: { password: 'SecureGallery123!' },
           headers: { 'User-Agent' => 'Original Browser' }
      
      # Try to access with different user agent
      get "/g/#{gallery.slug}", 
          headers: { 'User-Agent' => 'Different Browser' }
      
      expect(response.status).to eq(401)
    end
    
    it "allows continued access within timeout period" do
      get "/g/#{gallery.slug}"
      
      expect(response.status).to eq(200)
      expect(session["gallery_#{gallery.id}_auth_time"]).to be > 1.minute.ago.to_i
    end
  end
  
  describe "Rate Limiting" do
    it "rate limits gallery password attempts by IP" do
      11.times do
        post "/g/#{gallery.slug}/auth", params: { password: 'wrong_password' }
      end
      
      # Should be blocked after 10 attempts
      expect(response.status).to eq(401)
      
      # Verify attempt tracking
      cache_key = "gallery_auth_attempts:#{gallery.slug}:127.0.0.1"
      attempts = Rails.cache.read(cache_key)
      expect(attempts).to be >= 10
    end
    
    it "allows successful authentication after failed attempts" do
      # Make some failed attempts
      5.times do
        post "/g/#{gallery.slug}/auth", params: { password: 'wrong_password' }
      end
      
      # Successful authentication should still work and reset attempts
      post "/g/#{gallery.slug}/auth", params: { password: 'SecureGallery123!' }
      
      expect(response).to redirect_to(public_gallery_path(gallery.slug))
      
      # Verify attempts were reset
      cache_key = "gallery_auth_attempts:#{gallery.slug}:127.0.0.1"
      attempts = Rails.cache.read(cache_key)
      expect(attempts).to be_nil
    end
  end
  
  describe "Gallery Access Control" do
    it "blocks access to unpublished galleries" do
      gallery.update!(published: false)
      
      get "/g/#{gallery.slug}"
      
      expect(response.status).to eq(404)
    end
    
    it "blocks access to expired galleries" do
      gallery.update!(expires_at: 1.day.ago)
      
      get "/g/#{gallery.slug}"
      
      expect(response.status).to eq(410) # Gone
    end
    
    it "allows access to public galleries without password" do
      public_gallery = create(:gallery, password: nil)
      
      get "/g/#{public_gallery.slug}"
      
      expect(response.status).to eq(200)
    end
  end
  
  describe "Security Logging" do
    it "logs successful gallery authentication" do
      expect(SecurityAuditLogger).to receive(:log).with(
        event_type: 'gallery_auth_success',
        hash_including(
          ip_address: '127.0.0.1',
          additional_data: hash_including(
            gallery_id: gallery.id,
            gallery_slug: gallery.slug
          )
        )
      )
      
      post "/g/#{gallery.slug}/auth", params: { password: 'SecureGallery123!' }
    end
    
    it "logs failed authentication attempts" do
      expect(SecurityAuditLogger).to receive(:log).with(
        event_type: 'gallery_auth_failed',
        hash_including(
          ip_address: '127.0.0.1',
          additional_data: hash_including(
            gallery_id: gallery.id,
            gallery_slug: gallery.slug
          )
        )
      )
      
      post "/g/#{gallery.slug}/auth", params: { password: 'wrong_password' }
    end
    
    it "logs session expiration" do
      # Authenticate first
      post "/g/#{gallery.slug}/auth", params: { password: 'SecureGallery123!' }
      
      # Simulate expired session
      session["gallery_#{gallery.id}_auth_time"] = 3.hours.ago.to_i
      
      expect(SecurityAuditLogger).to receive(:log).with(
        event_type: 'gallery_session_expired',
        hash_including(
          ip_address: '127.0.0.1',
          additional_data: hash_including(
            gallery_id: gallery.id,
            gallery_slug: gallery.slug
          )
        )
      )
      
      get "/g/#{gallery.slug}"
    end
    
    it "logs session hijacking attempts" do
      # Authenticate with one user agent
      post "/g/#{gallery.slug}/auth", 
           params: { password: 'SecureGallery123!' },
           headers: { 'User-Agent' => 'Original Browser' }
      
      expect(SecurityAuditLogger).to receive(:log).with(
        event_type: 'gallery_session_hijack_attempt',
        hash_including(
          ip_address: '127.0.0.1',
          additional_data: hash_including(
            gallery_id: gallery.id,
            gallery_slug: gallery.slug,
            original_user_agent: 'Original Browser',
            current_user_agent: 'Different Browser'
          )
        )
      )
      
      # Try to access with different user agent
      get "/g/#{gallery.slug}", 
          headers: { 'User-Agent' => 'Different Browser' }
    end
  end
  
  describe "Download Security" do
    let(:image) { create(:image, gallery: gallery) }
    
    it "requires gallery authentication for downloads" do
      get "/g/#{gallery.slug}/download/#{image.id}"
      
      expect(response.status).to eq(401)
    end
    
    it "allows downloads after authentication" do
      post "/g/#{gallery.slug}/auth", params: { password: 'SecureGallery123!' }
      
      get "/g/#{gallery.slug}/download/#{image.id}"
      
      expect(response.status).to eq(302) # Redirect to signed URL
    end
    
    it "blocks bulk downloads when disabled" do
      gallery.update!(allow_downloads: false)
      post "/g/#{gallery.slug}/auth", params: { password: 'SecureGallery123!' }
      
      get "/g/#{gallery.slug}/download_all"
      
      expect(response.status).to eq(403)
    end
  end
end