require 'rails_helper'

RSpec.describe "Authentication Security", type: :request do
  let(:photographer) { create(:photographer) }
  
  describe "Session Security" do
    it "regenerates session on login to prevent fixation" do
      old_session_id = session.id
      
      post '/login', params: { 
        photographer: { 
          email: photographer.email, 
          password: 'ValidPassword123!' 
        } 
      }
      
      expect(session.id).not_to eq(old_session_id)
      expect(response).to redirect_to(root_path)
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
      # Simulate old session
      session[:photographer_id] = photographer.id
      session[:login_time] = 5.hours.ago.to_s
      
      get '/galleries'
      
      expect(response).to redirect_to(login_path)
      expect(flash[:alert]).to include('expired')
    end
    
    it "detects session hijacking attempts" do
      # Login with one user agent
      post '/login', params: { 
        photographer: { 
          email: photographer.email, 
          password: 'ValidPassword123!' 
        } 
      }, headers: { 'User-Agent' => 'Original Browser' }
      
      # Try to access with different user agent
      get '/galleries', headers: { 'User-Agent' => 'Different Browser' }
      
      expect(response).to redirect_to(login_path)
      expect(flash[:alert]).to include('security reasons')
    end
  end
  
  describe "Password Security" do
    it "requires strong passwords" do
      weak_passwords = ['123456', 'password', 'abc123', 'Password1']
      
      weak_passwords.each do |weak_password|
        photographer = build(:photographer, password: weak_password)
        expect(photographer).not_to be_valid
        expect(photographer.errors[:password]).to be_present
      end
    end
    
    it "accepts strong passwords" do
      strong_passwords = ['StrongPass123!', 'MySecure@Pass99', 'Complex#Password456']
      
      strong_passwords.each do |strong_password|
        photographer = build(:photographer, password: strong_password)
        expect(photographer).to be_valid
      end
    end
  end
  
  describe "Account Lockout" do
    it "locks account after failed attempts" do
      5.times do
        post '/login', params: { 
          photographer: { 
            email: photographer.email, 
            password: 'wrong_password' 
          } 
        }
      end
      
      photographer.reload
      expect(photographer.account_locked?).to be true
    end
    
    it "prevents login when account is locked" do
      photographer.update!(
        failed_attempts: 5,
        locked_until: 1.hour.from_now
      )
      
      post '/login', params: { 
        photographer: { 
          email: photographer.email, 
          password: 'ValidPassword123!' 
        } 
      }
      
      expect(response).to redirect_to(login_path)
      expect(flash[:alert]).to include('locked')
    end
    
    it "resets failed attempts on successful login" do
      photographer.update!(failed_attempts: 3)
      
      post '/login', params: { 
        photographer: { 
          email: photographer.email, 
          password: 'ValidPassword123!' 
        } 
      }
      
      photographer.reload
      expect(photographer.failed_attempts).to eq(0)
      expect(photographer.locked_until).to be_nil
    end
  end
  
  describe "Rate Limiting" do
    it "rate limits login attempts by IP" do
      6.times do
        post '/login', params: { 
          photographer: { 
            email: photographer.email, 
            password: 'wrong_password' 
          } 
        }
      end
      
      expect(response.status).to eq(429)
    end
    
    it "rate limits registration attempts" do
      4.times do |i|
        post '/register', params: { 
          photographer: { 
            name: "Test User #{i}",
            email: "test#{i}@example.com", 
            password: 'ValidPassword123!' 
          } 
        }
      end
      
      expect(response.status).to eq(429)
    end
  end
end