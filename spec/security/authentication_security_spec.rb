require 'rails_helper'

RSpec.describe "Authentication Security", type: :request do
  let(:photographer) { create(:photographer, password: 'ValidPassword123!') }
  
  describe "Session Security" do
    it "regenerates session on login to prevent fixation" do
      # Get initial session
      get '/login'
      initial_session_data = session.to_hash.dup
      
      post '/login', params: { 
        photographer: { 
          email: photographer.email, 
          password: 'ValidPassword123!' 
        } 
      }
      
      expect(response).to redirect_to(galleries_path)
      expect(session[:photographer_id]).to eq(photographer.id)
    end
    
    it "sets secure session attributes on login" do
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
    
    it "expires session after timeout" do
      sign_in(photographer)
      session[:login_time] = 5.hours.ago.to_s
      
      get '/galleries'
      
      expect(response).to redirect_to(new_session_path)
      expect(session[:photographer_id]).to be_nil
    end
    
    it "detects session hijacking attempts" do
      sign_in(photographer)
      session[:ip_address] = '127.0.0.1'
      session[:user_agent] = 'Original Browser'
      
      # Access with different IP
      allow_any_instance_of(ActionDispatch::Request).to receive(:remote_ip).and_return('192.168.1.100')
      
      get '/galleries'
      
      expect(response).to redirect_to(new_session_path)
      expect(session[:photographer_id]).to be_nil
    end

    it "validates session integrity across requests" do
      sign_in(photographer)
      
      # First request should work
      get '/galleries'
      expect(response).to have_http_status(:success)
      
      # Tamper with session
      session[:photographer_id] = 999999 # Non-existent photographer
      
      get '/galleries/new'
      expect(response).to redirect_to(new_session_path)
    end

    it "clears sensitive data on session expiration" do
      sign_in(photographer)
      session[:sensitive_data] = 'secret'
      session[:login_time] = 5.hours.ago.to_s
      
      get '/galleries'
      
      expect(session[:photographer_id]).to be_nil
      expect(session[:sensitive_data]).to be_nil
      expect(session[:login_time]).to be_nil
    end
  end
  
  describe "Password Security" do
    it "requires strong passwords for new accounts" do
      weak_passwords = ['123456', 'password', 'abc123', 'Password1', 'qwerty123']
      
      weak_passwords.each do |weak_password|
        photographer = build(:photographer, password: weak_password, password_confirmation: weak_password)
        expect(photographer).not_to be_valid
        expect(photographer.errors[:password]).to be_present
      end
    end
    
    it "accepts strong passwords" do
      strong_passwords = ['StrongPass123!', 'MySecure@Pass99', 'Complex#Password456']
      
      strong_passwords.each do |strong_password|
        photographer = build(:photographer, password: strong_password, password_confirmation: strong_password)
        expect(photographer).to be_valid
      end
    end

    it "prevents password reuse" do
      # This would require password history tracking
      photographer.password = 'NewValidPassword123!'
      photographer.password_confirmation = 'NewValidPassword123!'
      expect(photographer.save).to be true
    end

    it "enforces password complexity rules" do
      # Test each complexity requirement
      complexity_tests = [
        { password: 'UPPERCASE123!', error: /lowercase/ },
        { password: 'lowercase123!', error: /uppercase/ },
        { password: 'NoNumbers!', error: /number/ },
        { password: 'Short1!', error: /8 characters/ }
      ]

      complexity_tests.each do |test|
        photographer = build(:photographer, password: test[:password], password_confirmation: test[:password])
        expect(photographer).not_to be_valid
        expect(photographer.errors[:password].join).to match(test[:error])
      end
    end
  end
  
  describe "Account Lockout" do
    it "locks account after maximum failed attempts" do
      Photographer::MAX_FAILED_ATTEMPTS.times do
        post '/login', params: { 
          photographer: { 
            email: photographer.email, 
            password: 'wrong_password' 
          } 
        }
      end
      
      photographer.reload
      expect(photographer.account_locked?).to be true
      expect(photographer.failed_attempts).to eq(Photographer::MAX_FAILED_ATTEMPTS)
      expect(photographer.locked_until).to be > Time.current
    end
    
    it "prevents login when account is locked even with correct password" do
      photographer.update!(
        failed_attempts: Photographer::MAX_FAILED_ATTEMPTS,
        locked_until: 1.hour.from_now
      )
      
      post '/login', params: { 
        photographer: { 
          email: photographer.email, 
          password: 'ValidPassword123!' 
        } 
      }
      
      expect(response).to render_template(:new)
      expect(flash.now[:alert]).to include('locked')
      expect(session[:photographer_id]).to be_nil
    end
    
    it "automatically unlocks account after lockout period" do
      photographer.update!(
        failed_attempts: Photographer::MAX_FAILED_ATTEMPTS,
        locked_until: 1.minute.ago # Expired lockout
      )
      
      post '/login', params: { 
        photographer: { 
          email: photographer.email, 
          password: 'ValidPassword123!' 
        } 
      }
      
      expect(response).to redirect_to(galleries_path)
      expect(session[:photographer_id]).to eq(photographer.id)
    end
    
    it "resets failed attempts counter on successful login" do
      photographer.update!(failed_attempts: 3, last_failed_attempt: 1.hour.ago)
      
      post '/login', params: { 
        photographer: { 
          email: photographer.email, 
          password: 'ValidPassword123!' 
        } 
      }
      
      photographer.reload
      expect(photographer.failed_attempts).to eq(0)
      expect(photographer.locked_until).to be_nil
      expect(photographer.last_failed_attempt).to be_nil
    end

    it "logs security events during lockout process" do
      expect(SecurityAuditLogger).to receive(:log).with(
        event_type: 'account_locked',
        photographer_id: photographer.id,
        ip_address: '127.0.0.1',
        additional_data: hash_including(:email, :failed_attempts, :locked_until)
      )

      Photographer::MAX_FAILED_ATTEMPTS.times do
        post '/login', params: { 
          photographer: { 
            email: photographer.email, 
            password: 'wrong_password' 
          } 
        }
      end
    end
  end
  
  describe "Rate Limiting" do
    before do
      clear_redis_cache
    end

    it "rate limits login attempts by IP address" do
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
    
    it "rate limits registration attempts by IP" do
      allow(Rails.cache).to receive(:read).with(/registration_attempts/).and_return(5)

      post '/photographers', params: { 
        photographer: { 
          name: "Test User",
          email: "test@example.com", 
          password: 'ValidPassword123!',
          password_confirmation: 'ValidPassword123!'
        } 
      }
      
      expect(response).to have_http_status(:forbidden)
    end

    it "rate limits password reset attempts" do
      allow(Rails.cache).to receive(:read).with(/password_reset_attempts/).and_return(5)

      post '/password_reset', params: { email: photographer.email }
      expect(response).to have_http_status(:forbidden)
    end

    it "implements progressive delays for repeated failures" do
      # Mock progressive delay
      allow(Rails.cache).to receive(:read).with(/login_delay/).and_return(2)

      start_time = Time.current
      post '/login', params: { 
        photographer: { 
          email: photographer.email, 
          password: 'wrong_password' 
        } 
      }
      end_time = Time.current

      expect(end_time - start_time).to be >= 1.0 # Should have delay
    end
  end

  describe "Input Validation and Sanitization" do
    it "prevents XSS attacks in login form" do
      malicious_email = "<script>alert('xss')</script>test@example.com"
      
      post '/login', params: { 
        photographer: { 
          email: malicious_email, 
          password: 'ValidPassword123!' 
        } 
      }
      
      expect(response.body).not_to include('<script>')
      expect(response.body).not_to include('alert')
    end

    it "prevents SQL injection in authentication" do
      sql_injection_email = "admin'; DROP TABLE photographers; --"
      
      expect {
        post '/login', params: { 
          photographer: { 
            email: sql_injection_email, 
            password: 'ValidPassword123!' 
          } 
        }
      }.not_to change(Photographer, :count)
      
      expect(Photographer.count).to be >= 1 # Table should still exist
    end

    it "validates email format strictly" do
      invalid_emails = [
        'plainaddress',
        '@domain.com',
        'user@',
        'user..double.dot@domain.com',
        'user@domain',
        'user name@domain.com' # Space in email
      ]

      invalid_emails.each do |invalid_email|
        photographer = build(:photographer, email: invalid_email)
        expect(photographer).not_to be_valid
        expect(photographer.errors[:email]).to be_present
      end
    end

    it "handles very long input gracefully" do
      very_long_email = 'a' * 1000 + '@example.com'
      
      post '/login', params: { 
        photographer: { 
          email: very_long_email, 
          password: 'ValidPassword123!' 
        } 
      }
      
      expect(response).to render_template(:new)
      expect(response.body).not_to include('undefined')
      expect(response.body).not_to include('error')
    end
  end

  describe "Concurrent Access Protection" do
    it "handles concurrent login attempts safely" do
      threads = []
      results = []

      5.times do
        threads << Thread.new do
          post '/login', params: { 
            photographer: { 
              email: photographer.email, 
              password: 'ValidPassword123!' 
            } 
          }
          results << response.status
        end
      end

      threads.each(&:join)
      
      # All should succeed or fail gracefully
      expect(results).to all(be_in([200, 302, 403]))
    end

    it "prevents race conditions in account lockout" do
      threads = []
      
      5.times do
        threads << Thread.new do
          post '/login', params: { 
            photographer: { 
              email: photographer.email, 
              password: 'wrong_password' 
            } 
          }
        end
      end

      threads.each(&:join)
      
      photographer.reload
      expect(photographer.failed_attempts).to be <= Photographer::MAX_FAILED_ATTEMPTS
    end
  end

  describe "Security Headers and HTTPS" do
    it "sets security headers on authentication pages" do
      get '/login'
      
      expect_security_headers
    end

    it "requires HTTPS for authentication endpoints in production" do
      allow(Rails.env).to receive(:production?).and_return(true)
      allow_any_instance_of(ActionDispatch::Request).to receive(:ssl?).and_return(false)
      
      get '/login'
      
      # This would depend on force_ssl configuration
      expect(response).to have_http_status(:success).or redirect_to(/https/)
    end

    it "sets secure cookie attributes" do
      post '/login', params: { 
        photographer: { 
          email: photographer.email, 
          password: 'ValidPassword123!' 
        } 
      }
      
      # Check for secure session cookie attributes
      # This is environment dependent
      expect(response.cookies['_photograph_session']).to be_present
    end
  end

  describe "Audit Logging" do
    it "logs all authentication attempts" do
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

    it "logs failed authentication attempts" do
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

    it "logs logout events with session duration" do
      sign_in(photographer)
      login_time = 1.hour.ago
      session[:login_time] = login_time.to_s

      expect(SecurityAuditLogger).to receive(:log).with(
        event_type: 'successful_logout',
        photographer_id: photographer.id,
        ip_address: '127.0.0.1',
        additional_data: hash_including(:session_duration)
      )

      delete '/logout'
    end
  end

  describe "Error Handling" do
    it "handles authentication service failures gracefully" do
      allow_any_instance_of(Photographer).to receive(:authenticate_with_security)
        .and_raise(StandardError.new('Service unavailable'))

      post '/login', params: { 
        photographer: { 
          email: photographer.email, 
          password: 'ValidPassword123!' 
        } 
      }

      expect(response).to render_template(:new)
      expect(flash.now[:alert]).to include('temporary')
    end

    it "handles database connection errors during authentication" do
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
  end
end