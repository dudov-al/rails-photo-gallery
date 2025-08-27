require 'rails_helper'

RSpec.describe 'Authentication Flow', type: :request do
  let(:photographer) { create(:photographer, password: 'ValidPassword123!') }

  describe 'login process' do
    context 'successful login' do
      it 'allows photographer to login with valid credentials' do
        # Visit login page
        get '/login'
        expect(response).to have_http_status(:success)
        expect(response.body).to include('Sign In') || expect(response.body).to include('Login')

        # Submit login form
        post '/login', params: {
          photographer: {
            email: photographer.email,
            password: 'ValidPassword123!'
          }
        }

        # Should be redirected to galleries
        expect(response).to redirect_to(galleries_path)
        expect(session[:photographer_id]).to eq(photographer.id)
        expect(session[:login_time]).to be_present

        follow_redirect!
        expect(response).to have_http_status(:success)
        expect(response.body).to include('Welcome') || expect(flash[:notice]).to eq('Welcome back!')
      end

      it 'resets failed attempts counter on successful login' do
        photographer.update!(failed_attempts: 3, last_failed_attempt: 1.hour.ago)

        post '/login', params: {
          photographer: {
            email: photographer.email,
            password: 'ValidPassword123!'
          }
        }

        photographer.reload
        expect(photographer.failed_attempts).to eq(0)
        expect(photographer.last_failed_attempt).to be_nil
        expect(photographer.last_login_at).to be_within(5.seconds).of(Time.current)
      end

      it 'logs successful login security event' do
        expect(SecurityAuditLogger).to receive(:log).with(
          event_type: 'successful_login',
          photographer_id: photographer.id,
          ip_address: '127.0.0.1',
          additional_data: hash_including(:email)
        )

        post '/login', params: {
          photographer: {
            email: photographer.email,
            password: 'ValidPassword123!'
          }
        }
      end

      it 'stores session security information' do
        post '/login', params: {
          photographer: {
            email: photographer.email,
            password: 'ValidPassword123!'
          }
        }

        expect(session[:photographer_id]).to eq(photographer.id)
        expect(session[:login_time]).to be_present
        expect(session[:ip_address]).to eq('127.0.0.1')
        expect(session[:user_agent]).to be_present
      end
    end

    context 'failed login attempts' do
      it 'rejects login with incorrect password' do
        post '/login', params: {
          photographer: {
            email: photographer.email,
            password: 'WrongPassword'
          }
        }

        expect(response).to render_template(:new)
        expect(session[:photographer_id]).to be_nil
        expect(flash.now[:alert]).to eq('Invalid email or password')

        photographer.reload
        expect(photographer.failed_attempts).to eq(1)
        expect(photographer.last_failed_attempt).to be_within(5.seconds).of(Time.current)
      end

      it 'rejects login with non-existent email' do
        post '/login', params: {
          photographer: {
            email: 'nonexistent@example.com',
            password: 'AnyPassword123!'
          }
        }

        expect(response).to render_template(:new)
        expect(session[:photographer_id]).to be_nil
        expect(flash.now[:alert]).to eq('Invalid email or password')
      end

      it 'logs failed login attempts' do
        expect(SecurityAuditLogger).to receive(:log).with(
          event_type: 'failed_login_attempt',
          photographer_id: nil,
          ip_address: '127.0.0.1',
          additional_data: hash_including(:email, :reason)
        )

        post '/login', params: {
          photographer: {
            email: 'nonexistent@example.com',
            password: 'AnyPassword123!'
          }
        }
      end

      it 'increments failed attempts for existing photographer' do
        initial_attempts = photographer.failed_attempts

        post '/login', params: {
          photographer: {
            email: photographer.email,
            password: 'WrongPassword'
          }
        }

        photographer.reload
        expect(photographer.failed_attempts).to eq(initial_attempts + 1)
      end

      it 'locks account after maximum failed attempts' do
        photographer.update!(failed_attempts: 4) # One less than max

        post '/login', params: {
          photographer: {
            email: photographer.email,
            password: 'WrongPassword'
          }
        }

        photographer.reload
        expect(photographer.failed_attempts).to eq(5)
        expect(photographer.locked_until).to be > Time.current
        expect(photographer.account_locked?).to be true
      end

      it 'logs account lockout event' do
        photographer.update!(failed_attempts: 4)

        expect(SecurityAuditLogger).to receive(:log).with(
          event_type: 'account_locked',
          photographer_id: photographer.id,
          ip_address: '127.0.0.1',
          additional_data: hash_including(:email, :locked_until)
        )

        post '/login', params: {
          photographer: {
            email: photographer.email,
            password: 'WrongPassword'
          }
        }
      end
    end

    context 'locked account handling' do
      let(:locked_photographer) { create(:photographer, :locked, password: 'ValidPassword123!') }

      it 'prevents login for locked accounts even with correct password' do
        post '/login', params: {
          photographer: {
            email: locked_photographer.email,
            password: 'ValidPassword123!'
          }
        }

        expect(response).to render_template(:new)
        expect(session[:photographer_id]).to be_nil
        expect(flash.now[:alert]).to include('locked')
      end

      it 'shows remaining lockout time' do
        post '/login', params: {
          photographer: {
            email: locked_photographer.email,
            password: 'ValidPassword123!'
          }
        }

        expect(flash.now[:alert]).to include('minutes')
        expect(flash.now[:alert]).to match(/\d+/)
      end

      it 'automatically unlocks expired lockouts' do
        locked_photographer.update!(locked_until: 1.minute.ago)

        post '/login', params: {
          photographer: {
            email: locked_photographer.email,
            password: 'ValidPassword123!'
          }
        }

        expect(response).to redirect_to(galleries_path)
        expect(session[:photographer_id]).to eq(locked_photographer.id)
      end
    end

    context 'security measures' do
      it 'implements rate limiting for login attempts' do
        # Mock rate limiting
        allow(Rails.cache).to receive(:read).with(/login_attempts/).and_return(10)

        post '/login', params: {
          photographer: {
            email: photographer.email,
            password: 'ValidPassword123!'
          }
        }

        expect(response).to have_http_status(:forbidden)
        expect(response.body).to include('rate limit') || expect(response.body).to include('too many')
      end

      it 'implements progressive delays for repeated failures' do
        # Simulate multiple failed attempts
        allow(Rails.cache).to receive(:read).with(/login_delay/).and_return(5)

        start_time = Time.current
        post '/login', params: {
          photographer: {
            email: photographer.email,
            password: 'WrongPassword'
          }
        }
        end_time = Time.current

        # Should introduce delay
        expect(end_time - start_time).to be >= 0.5
      end

      it 'sanitizes input to prevent XSS attacks' do
        malicious_input = {
          photographer: {
            email: '<script>alert("xss")</script>test@example.com',
            password: '<img src=x onerror=alert(1)>password'
          }
        }

        post '/login', params: malicious_input

        expect(response.body).not_to include('<script>')
        expect(response.body).not_to include('onerror')
        expect(response.body).not_to include('alert')
      end

      it 'prevents SQL injection attacks' do
        sql_injection = {
          photographer: {
            email: "admin'; DROP TABLE photographers; --",
            password: 'any'
          }
        }

        expect {
          post '/login', params: sql_injection
        }.not_to change(Photographer, :count)

        # Database should remain intact
        expect(Photographer.count).to be >= 1
      end

      it 'detects suspicious login patterns' do
        # Mock suspicious activity detection
        allow_any_instance_of(ApplicationController).to receive(:detect_suspicious_activity).and_return(true)

        expect(SecurityAuditLogger).to receive(:log).with(
          event_type: 'suspicious_activity',
          photographer_id: nil,
          ip_address: '127.0.0.1',
          additional_data: hash_including(:reason)
        )

        post '/login', params: {
          photographer: {
            email: photographer.email,
            password: 'ValidPassword123!'
          }
        }
      end
    end
  end

  describe 'session management' do
    context 'session creation and maintenance' do
      before do
        post '/login', params: {
          photographer: {
            email: photographer.email,
            password: 'ValidPassword123!'
          }
        }
      end

      it 'maintains session across requests' do
        # First authenticated request
        get '/galleries'
        expect(response).to have_http_status(:success)

        # Second request should still be authenticated
        get '/galleries/new'
        expect(response).to have_http_status(:success)
      end

      it 'provides access to protected resources' do
        get '/galleries'
        expect(response).to have_http_status(:success)
        expect(response.body).to include('Galleries') || expect(response.body).to include('My Galleries')
      end

      it 'redirects unauthenticated users to login' do
        delete '/logout' # Clear session
        
        get '/galleries'
        expect(response).to redirect_to(new_session_path)
      end
    end

    context 'session security' do
      before do
        post '/login', params: {
          photographer: {
            email: photographer.email,
            password: 'ValidPassword123!'
          }
        }
      end

      it 'detects session timeout' do
        # Manually set login time to past
        session[:login_time] = 5.hours.ago.to_s

        get '/galleries'
        expect(response).to redirect_to(new_session_path)
        expect(session[:photographer_id]).to be_nil
      end

      it 'logs session timeout events' do
        session[:login_time] = 5.hours.ago.to_s

        expect(SecurityAuditLogger).to receive(:log).with(
          event_type: 'session_timeout',
          photographer_id: photographer.id,
          ip_address: '127.0.0.1',
          additional_data: hash_including(:session_age)
        )

        get '/galleries'
      end

      it 'detects IP address changes (session hijacking)' do
        # Change IP address in subsequent request
        allow_any_instance_of(ActionDispatch::Request).to receive(:remote_ip).and_return('192.168.1.100')

        expect(SecurityAuditLogger).to receive(:log).with(
          event_type: 'session_hijack_attempt',
          photographer_id: photographer.id,
          ip_address: '192.168.1.100',
          additional_data: hash_including(:original_ip, :new_ip)
        )

        get '/galleries'
        expect(response).to redirect_to(new_session_path)
        expect(session[:photographer_id]).to be_nil
      end

      it 'detects user agent changes' do
        # Change user agent
        get '/galleries', headers: { 'User-Agent' => 'Different Browser' }

        expect(response).to redirect_to(new_session_path)
        expect(session[:photographer_id]).to be_nil
      end

      it 'invalidates session on suspicious activity' do
        # Mock detection of suspicious activity
        allow_any_instance_of(ApplicationController).to receive(:detect_session_anomaly).and_return(true)

        get '/galleries'
        expect(response).to redirect_to(new_session_path)
        expect(session[:photographer_id]).to be_nil
      end
    end
  end

  describe 'logout process' do
    before do
      post '/login', params: {
        photographer: {
          email: photographer.email,
          password: 'ValidPassword123!'
        }
      }
    end

    context 'manual logout' do
      it 'allows photographer to logout' do
        delete '/logout'
        
        expect(response).to redirect_to(root_path)
        expect(session[:photographer_id]).to be_nil
        expect(session[:login_time]).to be_nil

        follow_redirect!
        expect(flash[:notice]).to eq('You have been signed out.')
      end

      it 'clears all session data on logout' do
        session[:some_other_data] = 'test_data'
        
        delete '/logout'
        
        expect(session[:photographer_id]).to be_nil
        expect(session[:login_time]).to be_nil
        expect(session[:ip_address]).to be_nil
        expect(session[:user_agent]).to be_nil
        expect(session[:some_other_data]).to be_nil
      end

      it 'logs logout security event' do
        expect(SecurityAuditLogger).to receive(:log).with(
          event_type: 'successful_logout',
          photographer_id: photographer.id,
          ip_address: '127.0.0.1',
          additional_data: hash_including(:session_duration)
        )

        delete '/logout'
      end

      it 'calculates and logs session duration' do
        login_time = 1.hour.ago
        session[:login_time] = login_time.to_s

        expect(SecurityAuditLogger).to receive(:log).with(
          event_type: 'successful_logout',
          photographer_id: photographer.id,
          ip_address: '127.0.0.1',
          additional_data: hash_including(session_duration: be_within(5.minutes).of(1.hour))
        )

        delete '/logout'
      end

      it 'redirects to root after logout' do
        delete '/logout'
        expect(response).to redirect_to(root_path)
      end
    end

    context 'automatic logout scenarios' do
      it 'automatically logs out on session timeout' do
        session[:login_time] = 5.hours.ago.to_s

        get '/galleries'
        
        expect(response).to redirect_to(new_session_path)
        expect(session[:photographer_id]).to be_nil
        expect(flash[:alert]).to include('session') || expect(flash[:alert]).to include('timeout')
      end

      it 'automatically logs out on security threat detection' do
        # Simulate session hijacking
        allow_any_instance_of(ActionDispatch::Request).to receive(:remote_ip).and_return('192.168.1.100')

        get '/galleries'
        
        expect(response).to redirect_to(new_session_path)
        expect(session[:photographer_id]).to be_nil
      end
    end
  end

  describe 'authentication state management' do
    context 'redirecting based on authentication status' do
      it 'redirects logged-in users away from login page' do
        # Log in first
        post '/login', params: {
          photographer: {
            email: photographer.email,
            password: 'ValidPassword123!'
          }
        }

        # Try to visit login page again
        get '/login'
        expect(response).to redirect_to(galleries_path)
      end

      it 'redirects logged-in users away from registration page' do
        # Log in first
        post '/login', params: {
          photographer: {
            email: photographer.email,
            password: 'ValidPassword123!'
          }
        }

        # Try to visit registration page
        get '/photographers/new'
        expect(response).to redirect_to(galleries_path)
      end

      it 'remembers intended destination after login' do
        # Try to access protected resource while logged out
        get '/galleries/new'
        expect(response).to redirect_to(new_session_path)

        # Log in
        post '/login', params: {
          photographer: {
            email: photographer.email,
            password: 'ValidPassword123!'
          }
        }

        # Should redirect to originally intended destination
        expect(response).to redirect_to(galleries_path) # or galleries/new if implemented
      end
    end

    context 'handling inactive or disabled accounts' do
      let(:inactive_photographer) { create(:photographer, :inactive, password: 'ValidPassword123!') }

      it 'prevents login for inactive accounts' do
        post '/login', params: {
          photographer: {
            email: inactive_photographer.email,
            password: 'ValidPassword123!'
          }
        }

        expect(response).to render_template(:new)
        expect(session[:photographer_id]).to be_nil
        expect(flash.now[:alert]).to include('inactive') || expect(flash.now[:alert]).to include('disabled')
      end
    end
  end

  describe 'mobile and API authentication' do
    context 'mobile device login' do
      it 'handles login from mobile devices' do
        mobile_headers = { 'User-Agent' => 'Mozilla/5.0 (iPhone; CPU iPhone OS 14_6 like Mac OS X)' }

        post '/login', 
             params: {
               photographer: {
                 email: photographer.email,
                 password: 'ValidPassword123!'
               }
             },
             headers: mobile_headers

        expect(response).to redirect_to(galleries_path)
        expect(session[:photographer_id]).to eq(photographer.id)
      end
    end

    context 'API authentication' do
      it 'supports JSON login requests' do
        headers = { 'Accept' => 'application/json', 'Content-Type' => 'application/json' }

        post '/login',
             params: {
               photographer: {
                 email: photographer.email,
                 password: 'ValidPassword123!'
               }
             }.to_json,
             headers: headers

        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response['status']).to eq('success')
      end

      it 'returns JSON errors for failed login attempts' do
        headers = { 'Accept' => 'application/json', 'Content-Type' => 'application/json' }

        post '/login',
             params: {
               photographer: {
                 email: photographer.email,
                 password: 'WrongPassword'
               }
             }.to_json,
             headers: headers

        expect(response).to have_http_status(:unauthorized)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to be_present
      end
    end
  end

  describe 'error handling and edge cases' do
    it 'handles database connection errors during login' do
      allow(Photographer).to receive(:find_by).and_raise(ActiveRecord::ConnectionTimeoutError)

      post '/login', params: {
        photographer: {
          email: photographer.email,
          password: 'ValidPassword123!'
        }
      }

      expect(response).to render_template(:new)
      expect(flash.now[:alert]).to include('temporary')
    end

    it 'handles Redis connection errors for rate limiting' do
      allow(Rails.cache).to receive(:read).and_raise(Redis::ConnectionError)

      # Should still work without rate limiting
      post '/login', params: {
        photographer: {
          email: photographer.email,
          password: 'ValidPassword123!'
        }
      }

      expect(response).to redirect_to(galleries_path)
    end

    it 'handles malformed login requests gracefully' do
      # Missing photographer parameter
      post '/login', params: { email: photographer.email, password: 'ValidPassword123!' }

      expect(response).to render_template(:new)
      expect(flash.now[:alert]).to be_present
    end
  end
end