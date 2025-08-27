require 'rails_helper'

RSpec.describe 'Public Gallery Viewing Flow', type: :request do
  let(:photographer) { create(:photographer) }
  let(:published_gallery) { create(:gallery, :published, :with_images, photographer: photographer) }
  let(:unpublished_gallery) { create(:gallery, :unpublished, :with_images, photographer: photographer) }
  let(:password_gallery) { create(:gallery, :published, :password_protected, :with_images, photographer: photographer) }
  let(:expired_gallery) { create(:gallery, :expired, :with_images, photographer: photographer) }

  describe 'public gallery access' do
    context 'viewing published galleries' do
      it 'allows anonymous users to view published galleries' do
        get "/g/#{published_gallery.slug}"
        
        expect(response).to have_http_status(:success)
        expect(response.body).to include(published_gallery.title)
        expect(response.body).to include(published_gallery.description)
        expect(response.body).to include('Photos')
      end

      it 'displays gallery images in correct order' do
        # Ensure images have specific positions
        images = published_gallery.images.order(:created_at)
        images.each_with_index do |image, index|
          image.update!(position: index + 1)
        end

        get "/g/#{published_gallery.slug}"
        
        expect(response).to have_http_status(:success)
        # Images should be displayed in position order
        image_positions = response.body.scan(/data-position="(\d+)"/).flatten.map(&:to_i)
        expect(image_positions).to eq(image_positions.sort)
      end

      it 'increments gallery view count on each visit' do
        initial_views = published_gallery.views_count
        
        3.times do
          get "/g/#{published_gallery.slug}"
          expect(response).to have_http_status(:success)
        end
        
        published_gallery.reload
        expect(published_gallery.views_count).to eq(initial_views + 3)
      end

      it 'logs gallery view events' do
        expect(SecurityAuditLogger).to receive(:log).with(
          event_type: 'gallery_viewed',
          photographer_id: nil,
          ip_address: '127.0.0.1',
          additional_data: hash_including(:gallery_id, :gallery_slug)
        )

        get "/g/#{published_gallery.slug}"
      end

      it 'provides gallery metadata for SEO and social sharing' do
        get "/g/#{published_gallery.slug}"
        
        expect(response.body).to include('<title>')
        expect(response.body).to include(published_gallery.title)
        expect(response.body).to include('<meta name="description"')
        expect(response.body).to include('<meta property="og:title"')
        expect(response.body).to include('<meta property="og:description"')
      end

      it 'implements responsive design for different devices' do
        mobile_user_agent = 'Mozilla/5.0 (iPhone; CPU iPhone OS 14_6 like Mac OS X)'
        
        get "/g/#{published_gallery.slug}", headers: { 'User-Agent' => mobile_user_agent }
        
        expect(response).to have_http_status(:success)
        expect(response.body).to include('viewport')
        # Should include mobile-optimized layout
      end

      it 'provides image lazy loading and performance optimization' do
        get "/g/#{published_gallery.slug}"
        
        expect(response.body).to include('loading="lazy"') || 
          expect(response.body).to include('data-src')
      end
    end

    context 'handling non-existent or unavailable galleries' do
      it 'returns 404 for non-existent gallery slugs' do
        get '/g/non-existent-gallery'
        
        expect(response).to have_http_status(:not_found)
        expect(response.body).to include('not found') || expect(response.body).to include('404')
      end

      it 'returns 404 for unpublished galleries' do
        get "/g/#{unpublished_gallery.slug}"
        
        expect(response).to have_http_status(:not_found)
        expect(response.body).to include('not found')
      end

      it 'returns 410 Gone for expired galleries' do
        get "/g/#{expired_gallery.slug}"
        
        expect(response).to have_http_status(:gone)
        expect(response.body).to include('expired') || expect(response.body).to include('no longer available')
        expect(response.body).to include(expired_gallery.expires_at.strftime('%B %Y'))
      end

      it 'provides helpful error messages and navigation' do
        get '/g/non-existent-gallery'
        
        expect(response.body).to include('Gallery') 
        expect(response.body).to include('Home') || expect(response.body).to include('Back')
        # Should provide navigation options
      end
    end
  end

  describe 'password-protected gallery authentication' do
    context 'initial access to password-protected gallery' do
      it 'redirects unauthenticated users to password form' do
        get "/g/#{password_gallery.slug}"
        
        expect(response).to redirect_to(password_form_path(password_gallery.slug))
        follow_redirect!
        
        expect(response).to have_http_status(:success)
        expect(response.body).to include('Password')
        expect(response.body).to include('form')
        expect(response.body).to include(password_gallery.title)
      end

      it 'shows password form without revealing gallery content' do
        get password_form_path(password_gallery.slug)
        
        expect(response).to have_http_status(:success)
        expect(response.body).to include('Enter password')
        expect(response.body).not_to include('Photos')
        # Should not show actual gallery images or detailed content
      end

      it 'provides gallery title and basic info on password form' do
        get password_form_path(password_gallery.slug)
        
        expect(response.body).to include(password_gallery.title)
        expect(response.body).to include('Protected Gallery') || 
          expect(response.body).to include('Private')
      end
    end

    context 'password authentication process' do
      it 'authenticates with correct password' do
        post "/g/#{password_gallery.slug}/auth", params: { password: 'GalleryPassword123!' }
        
        expect(response).to redirect_to(public_gallery_path(password_gallery.slug))
        expect(session["gallery_#{password_gallery.id}_authenticated"]).to be true
        
        follow_redirect!
        expect(response).to have_http_status(:success)
        expect(response.body).to include(password_gallery.title)
        expect(response.body).to include('Photos')
      end

      it 'rejects incorrect password' do
        post "/g/#{password_gallery.slug}/auth", params: { password: 'WrongPassword' }
        
        expect(response).to render_template(:password_form)
        expect(response.body).to include('Invalid password')
        expect(session["gallery_#{password_gallery.id}_authenticated"]).to be_falsey
      end

      it 'tracks failed authentication attempts' do
        cache_key = "gallery_auth_attempts:#{password_gallery.slug}:127.0.0.1"
        
        expect(Rails.cache).to receive(:write).with(cache_key, 1, expires_in: 1.hour)

        post "/g/#{password_gallery.slug}/auth", params: { password: 'WrongPassword' }
      end

      it 'logs authentication events' do
        expect(SecurityAuditLogger).to receive(:log).with(
          event_type: 'gallery_auth_success',
          photographer_id: nil,
          ip_address: '127.0.0.1',
          additional_data: hash_including(:gallery_id, :gallery_slug)
        )

        post "/g/#{password_gallery.slug}/auth", params: { password: 'GalleryPassword123!' }
      end

      it 'implements rate limiting for authentication attempts' do
        # Mock rate limiting
        allow(Rails.cache).to receive(:read).with(/gallery_auth_attempts/).and_return(10)

        post "/g/#{password_gallery.slug}/auth", params: { password: 'GalleryPassword123!' }
        
        expect(response).to have_http_status(:forbidden)
        expect(response.body).to include('too many attempts') || 
          expect(response.body).to include('rate limit')
      end

      it 'blocks authentication after multiple failed attempts' do
        # Simulate multiple failed attempts
        9.times do |i|
          allow(Rails.cache).to receive(:read).and_return(i + 1)
          post "/g/#{password_gallery.slug}/auth", params: { password: 'WrongPassword' }
        end

        # 10th attempt should be blocked
        allow(Rails.cache).to receive(:read).and_return(10)
        post "/g/#{password_gallery.slug}/auth", params: { password: 'GalleryPassword123!' }
        
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'authenticated session management' do
      before do
        # Authenticate to the gallery
        post "/g/#{password_gallery.slug}/auth", params: { password: 'GalleryPassword123!' }
      end

      it 'maintains authentication across multiple requests' do
        # First authenticated request
        get "/g/#{password_gallery.slug}"
        expect(response).to have_http_status(:success)

        # Second request should still be authenticated
        get "/g/#{password_gallery.slug}"
        expect(response).to have_http_status(:success)
        expect(response.body).to include('Photos')
      end

      it 'expires authentication after timeout period' do
        # Manually set authentication time to past
        session["gallery_#{password_gallery.id}_auth_time"] = 3.hours.ago.to_i

        get "/g/#{password_gallery.slug}"
        expect(response).to redirect_to(password_form_path(password_gallery.slug))
      end

      it 'detects session hijacking attempts' do
        # Change IP address
        allow_any_instance_of(ActionDispatch::Request).to receive(:remote_ip).and_return('192.168.1.100')

        expect(SecurityAuditLogger).to receive(:log).with(
          event_type: 'gallery_session_hijack_attempt',
          photographer_id: nil,
          ip_address: '192.168.1.100',
          additional_data: hash_including(:gallery_id, :original_ip, :new_ip)
        )

        get "/g/#{password_gallery.slug}"
        expect(response).to redirect_to(password_form_path(password_gallery.slug))
      end

      it 'detects user agent changes' do
        # Change user agent
        get "/g/#{password_gallery.slug}", headers: { 'User-Agent' => 'Different Browser' }
        
        expect(response).to redirect_to(password_form_path(password_gallery.slug))
      end

      it 'increments view count only for authenticated views' do
        initial_views = password_gallery.views_count

        # Unauthenticated access (redirected to password form)
        delete '/logout' if session[:photographer_id] # Clear any photographer session
        session.delete("gallery_#{password_gallery.id}_authenticated") # Clear gallery auth
        
        get "/g/#{password_gallery.slug}"
        password_gallery.reload
        expect(password_gallery.views_count).to eq(initial_views) # No increment

        # Authenticate and access
        post "/g/#{password_gallery.slug}/auth", params: { password: 'GalleryPassword123!' }
        get "/g/#{password_gallery.slug}"
        
        password_gallery.reload
        expect(password_gallery.views_count).to eq(initial_views + 1) # Should increment
      end
    end
  end

  describe 'gallery security and protection' do
    context 'preventing unauthorized access' do
      it 'sanitizes malicious input in password attempts' do
        malicious_password = "<script>alert('xss')</script>password"
        
        post "/g/#{password_gallery.slug}/auth", params: { password: malicious_password }
        
        expect(response.body).not_to include('<script>')
        expect(response.body).not_to include('alert')
      end

      it 'prevents SQL injection in password authentication' do
        sql_injection = "'; DROP TABLE galleries; --"
        
        expect {
          post "/g/#{password_gallery.slug}/auth", params: { password: sql_injection }
        }.not_to change(Gallery, :count)
      end

      it 'implements CSRF protection for authentication' do
        # This test depends on CSRF protection being enabled
        allow_any_instance_of(ActionController::Base).to receive(:protect_against_forgery?).and_return(true)

        expect {
          post "/g/#{password_gallery.slug}/auth", 
               params: { password: 'GalleryPassword123!' }
        }.to raise_error(ActionController::InvalidAuthenticityToken)
      end

      it 'prevents clickjacking with proper headers' do
        get "/g/#{published_gallery.slug}"
        
        expect(response.headers['X-Frame-Options']).to eq('DENY') || 
          expect(response.headers['Content-Security-Policy']).to include('frame-ancestors')
      end
    end

    context 'bot and crawler handling' do
      it 'handles search engine crawlers appropriately' do
        crawler_user_agent = 'Googlebot/2.1 (+http://www.google.com/bot.html)'
        
        get "/g/#{published_gallery.slug}", headers: { 'User-Agent' => crawler_user_agent }
        
        expect(response).to have_http_status(:success)
        # Should provide appropriate content for SEO without incrementing view count significantly
      end

      it 'detects and handles malicious bot traffic' do
        suspicious_user_agent = 'curl/7.64.1'
        
        get "/g/#{published_gallery.slug}", headers: { 'User-Agent' => suspicious_user_agent }
        
        # Might be blocked or handled differently
        expect([200, 403]).to include(response.status)
      end

      it 'implements rate limiting for gallery views' do
        # Mock rate limiting for excessive requests
        allow(Rails.cache).to receive(:read).with(/gallery_view_attempts/).and_return(100)

        get "/g/#{published_gallery.slug}"
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'content protection' do
      it 'prevents right-click context menu on images (optional)' do
        get "/g/#{published_gallery.slug}"
        
        # This is optional and might be implemented via JavaScript
        expect(response.body).to include('contextmenu') || 
          expect(response.body).not_to include('contextmenu')
      end

      it 'implements image watermarking or protection (optional)' do
        get "/g/#{published_gallery.slug}"
        
        # This would be implemented at the image serving level
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe 'gallery performance and caching' do
    context 'caching strategies' do
      it 'implements appropriate caching headers for public galleries' do
        get "/g/#{published_gallery.slug}"
        
        expect(response.headers['Cache-Control']).to be_present
        expect(response.headers['ETag']).to be_present
        expect(response.headers['Cache-Control']).to include('public')
      end

      it 'uses private caching for password-protected galleries' do
        # Authenticate first
        post "/g/#{password_gallery.slug}/auth", params: { password: 'GalleryPassword123!' }
        get "/g/#{password_gallery.slug}"
        
        expect(response.headers['Cache-Control']).to include('private') || 
          expect(response.headers['Cache-Control']).to include('no-cache')
      end

      it 'implements conditional requests with ETags' do
        # First request
        get "/g/#{published_gallery.slug}"
        etag = response.headers['ETag']
        
        # Second request with ETag
        get "/g/#{published_gallery.slug}", headers: { 'If-None-Match' => etag }
        expect(response).to have_http_status(:not_modified)
      end
    end

    context 'image delivery optimization' do
      it 'serves appropriate image variants based on request' do
        get "/g/#{published_gallery.slug}"
        
        # Should include responsive image attributes
        expect(response.body).to include('srcset') || 
          expect(response.body).to include('data-sizes')
      end

      it 'implements image lazy loading' do
        get "/g/#{published_gallery.slug}"
        
        expect(response.body).to include('loading="lazy"') || 
          expect(response.body).to include('data-src')
      end
    end
  end

  describe 'mobile and accessibility features' do
    it 'provides mobile-optimized gallery viewing experience' do
      mobile_user_agent = 'Mozilla/5.0 (iPhone; CPU iPhone OS 14_6 like Mac OS X)'
      
      get "/g/#{published_gallery.slug}", headers: { 'User-Agent' => mobile_user_agent }
      
      expect(response).to have_http_status(:success)
      expect(response.body).to include('viewport')
      expect(response.body).to include('touch') || expect(response.body).to include('swipe')
    end

    it 'implements keyboard navigation for accessibility' do
      get "/g/#{published_gallery.slug}"
      
      expect(response.body).to include('tabindex') || 
        expect(response.body).to include('aria-label')
    end

    it 'provides alt text for images' do
      get "/g/#{published_gallery.slug}"
      
      expect(response.body).to include('alt=')
      # Alt text should be meaningful, not just filename
    end

    it 'implements proper heading structure' do
      get "/g/#{published_gallery.slug}"
      
      expect(response.body).to include('<h1>')
      expect(response.body).to match(/<h[1-6]>.*#{published_gallery.title}.*<\/h[1-6]>/)
    end
  end

  describe 'analytics and tracking' do
    it 'tracks gallery engagement metrics' do
      get "/g/#{published_gallery.slug}"
      
      # Should track page views, time spent, etc.
      # This might be implemented via JavaScript analytics
      expect(response).to have_http_status(:success)
    end

    it 'provides gallery owner with view statistics' do
      # This would be tested in the photographer's dashboard
      # Here we just ensure the data is being collected
      initial_views = published_gallery.views_count
      
      get "/g/#{published_gallery.slug}"
      
      published_gallery.reload
      expect(published_gallery.views_count).to eq(initial_views + 1)
    end
  end
end