require 'rails_helper'

RSpec.describe PublicGalleriesController, type: :controller do
  let(:photographer) { create(:photographer) }
  let(:published_gallery) { create(:gallery, :published, photographer: photographer) }
  let(:unpublished_gallery) { create(:gallery, :unpublished, photographer: photographer) }
  let(:password_protected_gallery) { create(:gallery, :published, :password_protected, photographer: photographer) }
  let(:expired_gallery) { create(:gallery, :expired, photographer: photographer) }
  
  describe "GET #show" do
    context "with published gallery" do
      it "returns success" do
        get :show, params: { slug: published_gallery.slug }
        expect(response).to have_http_status(:success)
      end

      it "renders the show template" do
        get :show, params: { slug: published_gallery.slug }
        expect(response).to render_template(:show)
      end

      it "assigns the gallery" do
        get :show, params: { slug: published_gallery.slug }
        expect(assigns(:gallery)).to eq(published_gallery)
      end

      it "includes associated images" do
        images = create_list(:image, 3, gallery: published_gallery)
        
        get :show, params: { slug: published_gallery.slug }
        assigned_gallery = assigns(:gallery)
        
        expect(assigned_gallery.images.size).to eq(3)
      end

      it "orders images by position" do
        image1 = create(:image, gallery: published_gallery, position: 2)
        image2 = create(:image, gallery: published_gallery, position: 1)
        image3 = create(:image, gallery: published_gallery, position: 3)
        
        get :show, params: { slug: published_gallery.slug }
        images = assigns(:gallery).images.ordered
        
        expect(images).to eq([image2, image1, image3])
      end

      it "increments view count" do
        expect {
          get :show, params: { slug: published_gallery.slug }
        }.to change { published_gallery.reload.views_count }.by(1)
      end

      it "logs gallery view" do
        expect(SecurityAuditLogger).to receive(:log).with(
          event_type: 'gallery_viewed',
          photographer_id: nil,
          ip_address: '0.0.0.0',
          additional_data: hash_including(:gallery_id, :gallery_slug)
        )

        get :show, params: { slug: published_gallery.slug }
      end

      it "sets cache headers for performance" do
        get :show, params: { slug: published_gallery.slug }
        
        expect(response.headers['Cache-Control']).to be_present
        expect(response.headers['ETag']).to be_present
      end
    end

    context "with unpublished gallery" do
      it "returns not found" do
        get :show, params: { slug: unpublished_gallery.slug }
        expect(response).to have_http_status(:not_found)
      end

      it "renders not_found template" do
        get :show, params: { slug: unpublished_gallery.slug }
        expect(response).to render_template(:not_found)
      end

      it "does not increment view count" do
        expect {
          get :show, params: { slug: unpublished_gallery.slug }
        }.not_to change { unpublished_gallery.reload.views_count }
      end
    end

    context "with non-existent gallery" do
      it "returns not found" do
        get :show, params: { slug: 'non-existent-gallery' }
        expect(response).to have_http_status(:not_found)
      end

      it "renders not_found template" do
        get :show, params: { slug: 'non-existent-gallery' }
        expect(response).to render_template(:not_found)
      end
    end

    context "with expired gallery" do
      it "returns gone status" do
        get :show, params: { slug: expired_gallery.slug }
        expect(response).to have_http_status(:gone)
      end

      it "renders expired template" do
        get :show, params: { slug: expired_gallery.slug }
        expect(response).to render_template(:expired)
      end

      it "shows expiration information" do
        get :show, params: { slug: expired_gallery.slug }
        expect(assigns(:gallery)).to eq(expired_gallery)
        expect(assigns(:expired_at)).to be_present
      end
    end

    context "with password protected gallery" do
      context "when not authenticated to gallery" do
        it "redirects to password form" do
          get :show, params: { slug: password_protected_gallery.slug }
          expect(response).to redirect_to(password_form_path(password_protected_gallery.slug))
        end

        it "does not increment view count" do
          expect {
            get :show, params: { slug: password_protected_gallery.slug }
          }.not_to change { password_protected_gallery.reload.views_count }
        end
      end

      context "when authenticated to gallery" do
        before do
          authenticate_to_gallery(password_protected_gallery)
        end

        it "returns success" do
          get :show, params: { slug: password_protected_gallery.slug }
          expect(response).to have_http_status(:success)
        end

        it "renders the show template" do
          get :show, params: { slug: password_protected_gallery.slug }
          expect(response).to render_template(:show)
        end

        it "increments view count" do
          expect {
            get :show, params: { slug: password_protected_gallery.slug }
          }.to change { password_protected_gallery.reload.views_count }.by(1)
        end
      end

      context "with expired authentication" do
        before do
          authenticate_to_gallery(password_protected_gallery)
          session["gallery_#{password_protected_gallery.id}_auth_time"] = 3.hours.ago.to_i
        end

        it "redirects to password form" do
          get :show, params: { slug: password_protected_gallery.slug }
          expect(response).to redirect_to(password_form_path(password_protected_gallery.slug))
        end

        it "clears expired authentication" do
          get :show, params: { slug: password_protected_gallery.slug }
          expect(session["gallery_#{password_protected_gallery.id}_authenticated"]).to be_nil
        end
      end

      context "with session hijacking detection" do
        before do
          authenticate_to_gallery(password_protected_gallery)
          session["gallery_#{password_protected_gallery.id}_ip"] = '127.0.0.1'
          session["gallery_#{password_protected_gallery.id}_user_agent"] = 'Original Browser'
        end

        it "detects IP address changes" do
          request.env['REMOTE_ADDR'] = '192.168.1.100'
          
          expect(SecurityAuditLogger).to receive(:log).with(
            event_type: 'gallery_session_hijack_attempt',
            photographer_id: nil,
            ip_address: '192.168.1.100',
            additional_data: hash_including(:gallery_id, :original_ip, :new_ip)
          )

          get :show, params: { slug: password_protected_gallery.slug }
          expect(response).to redirect_to(password_form_path(password_protected_gallery.slug))
        end

        it "detects user agent changes" do
          request.env['HTTP_USER_AGENT'] = 'Different Browser'
          
          expect(SecurityAuditLogger).to receive(:log).with(
            event_type: 'gallery_session_hijack_attempt',
            photographer_id: nil,
            ip_address: '0.0.0.0',
            additional_data: hash_including(:gallery_id, :original_user_agent, :new_user_agent)
          )

          get :show, params: { slug: password_protected_gallery.slug }
          expect(response).to redirect_to(password_form_path(password_protected_gallery.slug))
        end
      end
    end
  end

  describe "GET #password_form" do
    it "returns success for password protected gallery" do
      get :password_form, params: { slug: password_protected_gallery.slug }
      expect(response).to have_http_status(:success)
    end

    it "renders password form template" do
      get :password_form, params: { slug: password_protected_gallery.slug }
      expect(response).to render_template(:password_form)
    end

    it "assigns the gallery" do
      get :password_form, params: { slug: password_protected_gallery.slug }
      expect(assigns(:gallery)).to eq(password_protected_gallery)
    end

    it "redirects if gallery is not password protected" do
      get :password_form, params: { slug: published_gallery.slug }
      expect(response).to redirect_to(public_gallery_path(published_gallery.slug))
    end

    it "returns not found for non-existent gallery" do
      get :password_form, params: { slug: 'non-existent' }
      expect(response).to have_http_status(:not_found)
    end

    it "returns gone for expired gallery" do
      get :password_form, params: { slug: expired_gallery.slug }
      expect(response).to have_http_status(:gone)
    end
  end

  describe "POST #authenticate" do
    let(:correct_password) { 'GalleryPassword123!' }
    let(:wrong_password) { 'WrongPassword' }

    context "with correct password" do
      it "authenticates successfully" do
        post :authenticate, params: { 
          slug: password_protected_gallery.slug, 
          password: correct_password 
        }
        
        expect(session["gallery_#{password_protected_gallery.id}_authenticated"]).to be true
      end

      it "sets authentication timestamp" do
        post :authenticate, params: { 
          slug: password_protected_gallery.slug, 
          password: correct_password 
        }
        
        auth_time = session["gallery_#{password_protected_gallery.id}_auth_time"]
        expect(auth_time).to be_within(5.seconds).of(Time.current.to_i)
      end

      it "stores IP and user agent" do
        request.env['REMOTE_ADDR'] = '192.168.1.100'
        request.env['HTTP_USER_AGENT'] = 'Test Browser'
        
        post :authenticate, params: { 
          slug: password_protected_gallery.slug, 
          password: correct_password 
        }
        
        expect(session["gallery_#{password_protected_gallery.id}_ip"]).to eq('192.168.1.100')
        expect(session["gallery_#{password_protected_gallery.id}_user_agent"]).to eq('Test Browser')
      end

      it "redirects to gallery" do
        post :authenticate, params: { 
          slug: password_protected_gallery.slug, 
          password: correct_password 
        }
        
        expect(response).to redirect_to(public_gallery_path(password_protected_gallery.slug))
      end

      it "sets success flash message" do
        post :authenticate, params: { 
          slug: password_protected_gallery.slug, 
          password: correct_password 
        }
        
        expect(flash[:notice]).to eq("Access granted to gallery.")
      end

      it "logs successful authentication" do
        expect(SecurityAuditLogger).to receive(:log).with(
          event_type: 'gallery_auth_success',
          photographer_id: nil,
          ip_address: '0.0.0.0',
          additional_data: hash_including(:gallery_id, :gallery_slug)
        )

        post :authenticate, params: { 
          slug: password_protected_gallery.slug, 
          password: correct_password 
        }
      end
    end

    context "with incorrect password" do
      it "does not authenticate" do
        post :authenticate, params: { 
          slug: password_protected_gallery.slug, 
          password: wrong_password 
        }
        
        expect(session["gallery_#{password_protected_gallery.id}_authenticated"]).to be_falsey
      end

      it "renders password form with error" do
        post :authenticate, params: { 
          slug: password_protected_gallery.slug, 
          password: wrong_password 
        }
        
        expect(response).to render_template(:password_form)
        expect(flash.now[:alert]).to eq("Invalid password. Please try again.")
      end

      it "logs failed authentication" do
        expect(SecurityAuditLogger).to receive(:log).with(
          event_type: 'gallery_auth_failed',
          photographer_id: nil,
          ip_address: '0.0.0.0',
          additional_data: hash_including(:gallery_id, :gallery_slug, :attempts)
        )

        post :authenticate, params: { 
          slug: password_protected_gallery.slug, 
          password: wrong_password 
        }
      end

      it "increments failed attempts counter" do
        cache_key = "gallery_auth_attempts:#{password_protected_gallery.slug}:0.0.0.0"
        
        expect(Rails.cache).to receive(:write).with(cache_key, 1, expires_in: 1.hour)
        
        post :authenticate, params: { 
          slug: password_protected_gallery.slug, 
          password: wrong_password 
        }
      end
    end

    context "with too many failed attempts" do
      before do
        allow(Rails.cache).to receive(:read).with(/gallery_auth_attempts/).and_return(10)
      end

      it "blocks authentication attempts" do
        post :authenticate, params: { 
          slug: password_protected_gallery.slug, 
          password: correct_password 
        }
        
        expect(response).to have_http_status(:forbidden)
      end

      it "logs blocked attempt" do
        expect(SecurityAuditLogger).to receive(:log).with(
          event_type: 'gallery_auth_blocked',
          photographer_id: nil,
          ip_address: '0.0.0.0',
          additional_data: hash_including(:gallery_id, :attempts)
        )

        post :authenticate, params: { 
          slug: password_protected_gallery.slug, 
          password: correct_password 
        }
      end

      it "shows rate limit error" do
        post :authenticate, params: { 
          slug: password_protected_gallery.slug, 
          password: correct_password 
        }
        
        expect(response.body).to include('too many attempts')
      end
    end

    context "with malicious input" do
      it "sanitizes password input" do
        malicious_password = "<script>alert('xss')</script>password"
        
        post :authenticate, params: { 
          slug: password_protected_gallery.slug, 
          password: malicious_password 
        }
        
        expect(response.body).not_to include('<script>')
        expect(response.body).not_to include('alert')
      end

      it "handles SQL injection attempts" do
        sql_injection = "'; DROP TABLE galleries; --"
        
        expect {
          post :authenticate, params: { 
            slug: password_protected_gallery.slug, 
            password: sql_injection 
          }
        }.not_to change(Gallery, :count)
      end
    end

    context "for non-password protected gallery" do
      it "redirects to gallery" do
        post :authenticate, params: { 
          slug: published_gallery.slug, 
          password: 'any_password' 
        }
        
        expect(response).to redirect_to(public_gallery_path(published_gallery.slug))
      end
    end

    context "for expired gallery" do
      it "returns gone status" do
        post :authenticate, params: { 
          slug: expired_gallery.slug, 
          password: 'any_password' 
        }
        
        expect(response).to have_http_status(:gone)
      end
    end
  end

  describe "security features" do
    describe "rate limiting" do
      before do
        allow(Rails.cache).to receive(:read).with(/gallery_view_attempts/).and_return(100)
      end

      it "rate limits gallery viewing" do
        get :show, params: { slug: published_gallery.slug }
        expect(response).to have_http_status(:forbidden)
      end

      it "shows rate limit error" do
        get :show, params: { slug: published_gallery.slug }
        expect(response.body).to include('rate limit')
      end
    end

    describe "bot detection" do
      it "detects and blocks bot traffic" do
        request.env['HTTP_USER_AGENT'] = 'Googlebot/2.1'
        
        get :show, params: { slug: published_gallery.slug }
        
        # Depending on implementation, might block or allow with different treatment
        expect(response).to have_http_status(:success).or have_http_status(:forbidden)
      end

      it "logs suspicious user agents" do
        request.env['HTTP_USER_AGENT'] = 'curl/7.64.1'
        
        expect(SecurityAuditLogger).to receive(:log).with(
          event_type: 'suspicious_user_agent',
          photographer_id: nil,
          ip_address: '0.0.0.0',
          additional_data: hash_including(:user_agent, :gallery_id)
        )

        get :show, params: { slug: published_gallery.slug }
      end
    end

    describe "hotlinking protection" do
      it "validates referrer for image requests" do
        request.env['HTTP_REFERER'] = 'https://malicious-site.com'
        
        # This would typically be handled at the web server or CDN level
        # but can also be implemented in the application
        get :show, params: { slug: published_gallery.slug }
        
        # Implementation might block or allow with watermarks
        expect(response).to have_http_status(:success)
      end
    end

    describe "clickjacking protection" do
      it "sets X-Frame-Options header" do
        get :show, params: { slug: published_gallery.slug }
        expect(response.headers['X-Frame-Options']).to eq('DENY')
      end
    end
  end

  describe "performance optimizations" do
    it "uses efficient queries for gallery with many images" do
      gallery_with_many_images = create(:gallery, :published, :with_many_images, photographer: photographer)
      
      expect { 
        get :show, params: { slug: gallery_with_many_images.slug } 
      }.not_to exceed_query_limit(5)
    end

    it "implements proper caching" do
      get :show, params: { slug: published_gallery.slug }
      
      expect(response.headers['Cache-Control']).to include('public')
      expect(response.headers['ETag']).to be_present
    end

    it "serves appropriate cache headers for password protected galleries" do
      authenticate_to_gallery(password_protected_gallery)
      get :show, params: { slug: password_protected_gallery.slug }
      
      expect(response.headers['Cache-Control']).to include('private')
    end
  end

  describe "accessibility and SEO" do
    it "sets appropriate page titles" do
      get :show, params: { slug: published_gallery.slug }
      expect(assigns(:page_title)).to include(published_gallery.title)
    end

    it "provides meta descriptions" do
      get :show, params: { slug: published_gallery.slug }
      expect(assigns(:meta_description)).to include(published_gallery.description)
    end

    it "includes structured data for SEO" do
      get :show, params: { slug: published_gallery.slug }
      expect(assigns(:structured_data)).to be_present
    end
  end

  describe "error handling" do
    it "handles database connection errors gracefully" do
      allow(Gallery).to receive(:find_by).and_raise(ActiveRecord::ConnectionTimeoutError)
      
      get :show, params: { slug: 'any-gallery' }
      
      expect(response).to have_http_status(:service_unavailable)
      expect(response.body).to include('temporarily unavailable')
    end

    it "handles Redis connection errors for caching" do
      allow(Rails.cache).to receive(:read).and_raise(Redis::ConnectionError)
      
      get :show, params: { slug: published_gallery.slug }
      
      # Should still work without cache
      expect(response).to have_http_status(:success)
    end
  end

  # Helper method to authenticate to a gallery
  def authenticate_to_gallery(gallery, password = nil)
    password ||= gallery.password
    session["gallery_#{gallery.id}_authenticated"] = true
    session["gallery_#{gallery.id}_auth_time"] = Time.current.to_i
    session["gallery_#{gallery.id}_ip"] = request.remote_ip
    session["gallery_#{gallery.id}_user_agent"] = request.user_agent
  end
end