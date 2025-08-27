require 'rails_helper'

RSpec.describe SessionsController, type: :controller do
  let(:photographer) { create(:photographer, password: 'ValidPassword123!') }

  describe "GET #new" do
    context "when user is not logged in" do
      it "returns success" do
        get :new
        expect(response).to have_http_status(:success)
      end

      it "renders the new template" do
        get :new
        expect(response).to render_template(:new)
      end
    end

    context "when user is already logged in" do
      before { sign_in(photographer) }

      it "redirects to galleries" do
        get :new
        expect(response).to redirect_to(galleries_path)
      end
    end
  end

  describe "POST #create" do
    let(:valid_params) do
      {
        photographer: {
          email: photographer.email,
          password: 'ValidPassword123!'
        }
      }
    end

    context "with valid credentials" do
      it "signs in the photographer" do
        post :create, params: valid_params
        expect(session[:photographer_id]).to eq(photographer.id)
      end

      it "redirects to galleries" do
        post :create, params: valid_params
        expect(response).to redirect_to(galleries_path)
      end

      it "sets flash notice" do
        post :create, params: valid_params
        expect(flash[:notice]).to eq("Welcome back!")
      end

      it "resets failed attempts" do
        photographer.update!(failed_attempts: 3)
        expect(photographer).to receive(:reset_failed_attempts!)
        
        post :create, params: valid_params
      end

      it "logs successful login security event" do
        expect(SecurityAuditLogger).to receive(:log).with(
          event_type: 'successful_login',
          photographer_id: photographer.id,
          ip_address: '0.0.0.0',
          additional_data: hash_including(:email)
        )

        post :create, params: valid_params
      end
    end

    context "with invalid credentials" do
      let(:invalid_params) do
        {
          photographer: {
            email: photographer.email,
            password: 'WrongPassword'
          }
        }
      end

      it "does not sign in the photographer" do
        post :create, params: invalid_params
        expect(session[:photographer_id]).to be_nil
      end

      it "renders new template" do
        post :create, params: invalid_params
        expect(response).to render_template(:new)
      end

      it "sets flash alert" do
        post :create, params: invalid_params
        expect(flash.now[:alert]).to be_present
      end

      it "increments failed attempts" do
        expect(photographer).to receive(:increment_failed_attempts!)
        post :create, params: invalid_params
      end
    end

    context "with non-existent email" do
      let(:invalid_params) do
        {
          photographer: {
            email: 'nonexistent@example.com',
            password: 'AnyPassword123!'
          }
        }
      end

      it "does not sign in" do
        post :create, params: invalid_params
        expect(session[:photographer_id]).to be_nil
      end

      it "shows generic error message" do
        post :create, params: invalid_params
        expect(flash.now[:alert]).to eq("Invalid email or password")
      end

      it "logs failed login attempt" do
        expect(SecurityAuditLogger).to receive(:log).with(
          event_type: 'failed_login_attempt',
          photographer_id: nil,
          ip_address: '0.0.0.0',
          additional_data: hash_including(:email, :reason)
        )

        post :create, params: invalid_params
      end
    end

    context "with locked account" do
      let(:locked_photographer) { create(:photographer, :locked, password: 'ValidPassword123!') }
      let(:locked_params) do
        {
          photographer: {
            email: locked_photographer.email,
            password: 'ValidPassword123!'
          }
        }
      end

      it "does not sign in" do
        post :create, params: locked_params
        expect(session[:photographer_id]).to be_nil
      end

      it "shows account locked message" do
        post :create, params: locked_params
        expect(flash.now[:alert]).to match(/account.*locked/i)
      end

      it "provides unlock time information" do
        post :create, params: locked_params
        expect(flash.now[:alert]).to include('minutes')
      end
    end

    context "with rate limiting" do
      before do
        allow(Rails.cache).to receive(:read).with(/login_attempts/).and_return(10)
      end

      it "blocks login attempts when rate limited" do
        post :create, params: valid_params
        expect(response).to have_http_status(:forbidden)
      end

      it "returns JSON error for API requests" do
        request.headers['Accept'] = 'application/json'
        post :create, params: valid_params
        
        expect(response).to have_http_status(:forbidden)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to include('rate limit')
      end
    end

    context "with suspicious activity detection" do
      before do
        # Mock suspicious IP detection
        allow_any_instance_of(ApplicationController).to receive(:detect_suspicious_activity).and_return(true)
      end

      it "logs suspicious activity" do
        expect(SecurityAuditLogger).to receive(:log).with(
          event_type: 'suspicious_activity',
          photographer_id: nil,
          ip_address: '0.0.0.0',
          additional_data: hash_including(:reason)
        )

        post :create, params: valid_params
      end
    end
  end

  describe "DELETE #destroy" do
    context "when logged in" do
      before { sign_in(photographer) }

      it "signs out the photographer" do
        delete :destroy
        expect(session[:photographer_id]).to be_nil
      end

      it "redirects to root" do
        delete :destroy
        expect(response).to redirect_to(root_path)
      end

      it "sets flash notice" do
        delete :destroy
        expect(flash[:notice]).to eq("You have been signed out.")
      end

      it "logs logout security event" do
        expect(SecurityAuditLogger).to receive(:log).with(
          event_type: 'successful_logout',
          photographer_id: photographer.id,
          ip_address: '0.0.0.0',
          additional_data: hash_including(:session_duration)
        )

        delete :destroy
      end

      it "clears all session data" do
        session[:some_other_data] = 'test'
        delete :destroy
        
        expect(session[:photographer_id]).to be_nil
        expect(session[:login_time]).to be_nil
        expect(session[:some_other_data]).to be_nil
      end
    end

    context "when not logged in" do
      it "redirects to root" do
        delete :destroy
        expect(response).to redirect_to(root_path)
      end

      it "does not log security event" do
        expect(SecurityAuditLogger).not_to receive(:log)
        delete :destroy
      end
    end
  end

  describe "security features" do
    describe "session timeout" do
      before do
        sign_in(photographer)
        session[:login_time] = 5.hours.ago.to_s
      end

      it "automatically logs out expired sessions" do
        get :new # Any action will trigger session check
        expect(session[:photographer_id]).to be_nil
      end

      it "logs session timeout event" do
        expect(SecurityAuditLogger).to receive(:log).with(
          event_type: 'session_timeout',
          photographer_id: photographer.id,
          ip_address: '0.0.0.0',
          additional_data: hash_including(:session_age)
        )

        get :new
      end
    end

    describe "session hijacking protection" do
      before do
        sign_in(photographer)
        session[:ip_address] = '127.0.0.1'
        session[:user_agent] = 'Original Browser'
      end

      it "detects IP address changes" do
        request.env['REMOTE_ADDR'] = '192.168.1.100'
        
        expect(SecurityAuditLogger).to receive(:log).with(
          event_type: 'session_hijack_attempt',
          photographer_id: photographer.id,
          ip_address: '192.168.1.100',
          additional_data: hash_including(:original_ip, :new_ip)
        )

        get :new
        expect(session[:photographer_id]).to be_nil
      end

      it "detects user agent changes" do
        request.env['HTTP_USER_AGENT'] = 'Different Browser'
        
        expect(SecurityAuditLogger).to receive(:log).with(
          event_type: 'session_hijack_attempt',
          photographer_id: photographer.id,
          ip_address: '0.0.0.0',
          additional_data: hash_including(:original_user_agent, :new_user_agent)
        )

        get :new
        expect(session[:photographer_id]).to be_nil
      end
    end

    describe "brute force protection" do
      before do
        # Simulate multiple failed attempts
        10.times { post :create, params: { photographer: { email: photographer.email, password: 'wrong' } } }
      end

      it "implements progressive delays" do
        start_time = Time.current
        post :create, params: { photographer: { email: photographer.email, password: 'wrong' } }
        end_time = Time.current
        
        expect(end_time - start_time).to be > 0.5 # Should have some delay
      end
    end

    describe "CSRF protection" do
      before do
        # Enable CSRF protection for this test
        allow_any_instance_of(ActionController::Base).to receive(:protect_against_forgery?).and_return(true)
      end

      it "requires valid CSRF token" do
        expect {
          post :create, params: valid_params
        }.to raise_error(ActionController::InvalidAuthenticityToken)
      end
    end
  end

  describe "input sanitization" do
    it "sanitizes email input" do
      malicious_params = {
        photographer: {
          email: "<script>alert('xss')</script>test@example.com",
          password: 'ValidPassword123!'
        }
      }

      post :create, params: malicious_params
      # Email should be sanitized and login should fail due to invalid email
      expect(session[:photographer_id]).to be_nil
    end

    it "handles SQL injection attempts" do
      malicious_params = {
        photographer: {
          email: "test@example.com'; DROP TABLE photographers; --",
          password: 'ValidPassword123!'
        }
      }

      expect { post :create, params: malicious_params }.not_to change(Photographer, :count)
      expect(session[:photographer_id]).to be_nil
    end
  end

  describe "error handling" do
    it "handles database connection errors gracefully" do
      allow(Photographer).to receive(:find_by).and_raise(ActiveRecord::ConnectionTimeoutError)
      
      post :create, params: valid_params
      
      expect(response).to render_template(:new)
      expect(flash.now[:alert]).to include('temporary')
    end

    it "handles unexpected errors gracefully" do
      allow(Photographer).to receive(:find_by).and_raise(StandardError.new('Unexpected error'))
      
      post :create, params: valid_params
      
      expect(response).to render_template(:new)
      expect(flash.now[:alert]).to be_present
    end
  end

  describe "accessibility and UX" do
    it "provides helpful error messages" do
      post :create, params: { photographer: { email: '', password: '' } }
      
      expect(flash.now[:alert]).to be_present
      expect(flash.now[:alert]).not_to include('nil')
      expect(flash.now[:alert]).not_to include('undefined')
    end

    it "maintains form data on validation errors" do
      post :create, params: { photographer: { email: 'test@example.com', password: 'wrong' } }
      
      expect(assigns(:photographer)).to be_present
      expect(assigns(:photographer).email).to eq('test@example.com')
    end
  end

  # Helper method to sign in a photographer
  def sign_in(photographer)
    session[:photographer_id] = photographer.id
    session[:login_time] = Time.current.to_s
    session[:ip_address] = request.remote_ip
    session[:user_agent] = request.user_agent
  end
end