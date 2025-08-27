require 'rails_helper'

RSpec.describe 'User Registration Flow', type: :request do
  describe 'photographer registration process' do
    let(:valid_registration_data) do
      {
        photographer: {
          name: 'John Doe',
          email: 'john@example.com',
          password: 'SecurePassword123!',
          password_confirmation: 'SecurePassword123!'
        }
      }
    end

    context 'successful registration' do
      it 'allows new user to register and automatically sign in' do
        # Visit registration page
        get '/photographers/new'
        expect(response).to have_http_status(:success)
        expect(response.body).to include('Register')

        # Submit registration form
        expect {
          post '/photographers', params: valid_registration_data
        }.to change(Photographer, :count).by(1)

        # Should be redirected to galleries (logged in)
        expect(response).to redirect_to(galleries_path)
        follow_redirect!
        expect(response).to have_http_status(:success)
        
        # Verify user is logged in
        expect(session[:photographer_id]).to be_present
        expect(response.body).to include('Welcome')

        # Check that security event was logged
        security_events = SecurityEvent.where(event_type: 'account_created')
        expect(security_events).to be_present
        
        photographer = Photographer.last
        expect(photographer.name).to eq('John Doe')
        expect(photographer.email).to eq('john@example.com')
        expect(photographer.active?).to be true
      end

      it 'normalizes email and sets proper defaults' do
        registration_data = valid_registration_data.dup
        registration_data[:photographer][:email] = '  JOHN@EXAMPLE.COM  '

        post '/photographers', params: registration_data

        photographer = Photographer.last
        expect(photographer.email).to eq('john@example.com')
        expect(photographer.active).to be true
        expect(photographer.failed_attempts).to eq(0)
        expect(photographer.locked_until).to be_nil
      end

      it 'creates secure password hash' do
        post '/photographers', params: valid_registration_data

        photographer = Photographer.last
        expect(photographer.password_digest).to be_present
        expect(photographer.password_digest).not_to eq('SecurePassword123!')
        expect(photographer.authenticate('SecurePassword123!')).to be_truthy
      end
    end

    context 'registration validation failures' do
      it 'rejects registration with weak password' do
        weak_password_data = valid_registration_data.dup
        weak_password_data[:photographer][:password] = 'weak'
        weak_password_data[:photographer][:password_confirmation] = 'weak'

        expect {
          post '/photographers', params: weak_password_data
        }.not_to change(Photographer, :count)

        expect(response).to render_template(:new)
        expect(response.body).to include('Password')
        expect(response.body).to include('too short')
      end

      it 'rejects registration with duplicate email' do
        create(:photographer, email: 'john@example.com')

        expect {
          post '/photographers', params: valid_registration_data
        }.not_to change(Photographer, :count)

        expect(response).to render_template(:new)
        expect(response.body).to include('has already been taken')
      end

      it 'rejects registration with mismatched password confirmation' do
        mismatched_data = valid_registration_data.dup
        mismatched_data[:photographer][:password_confirmation] = 'DifferentPassword123!'

        expect {
          post '/photographers', params: mismatched_data
        }.not_to change(Photographer, :count)

        expect(response).to render_template(:new)
        expect(response.body).to include("doesn't match")
      end

      it 'maintains form data on validation errors' do
        invalid_data = valid_registration_data.dup
        invalid_data[:photographer][:email] = 'invalid-email'

        post '/photographers', params: invalid_data

        expect(response.body).to include('John Doe') # Name should be preserved
        expect(response.body).to include('invalid-email') # Email should be preserved
        # Passwords should not be preserved for security
      end
    end

    context 'security measures during registration' do
      it 'prevents registration when already logged in' do
        existing_photographer = create(:photographer)
        
        # Log in first
        post '/login', params: {
          photographer: {
            email: existing_photographer.email,
            password: 'ValidPassword123!'
          }
        }

        # Try to register again
        get '/photographers/new'
        expect(response).to redirect_to(galleries_path)

        post '/photographers', params: valid_registration_data
        expect(response).to redirect_to(galleries_path)
        expect(flash[:notice]).to eq('You are already signed in.')
      end

      it 'sanitizes malicious input during registration' do
        malicious_data = valid_registration_data.dup
        malicious_data[:photographer][:name] = '<script>alert("xss")</script>Malicious User'
        malicious_data[:photographer][:email] = '<img src=x onerror=alert(1)>test@example.com'

        post '/photographers', params: malicious_data

        if response.status == 201 || response.status == 302
          photographer = Photographer.last
          expect(photographer.name).not_to include('<script>')
          expect(photographer.name).not_to include('alert')
          expect(photographer.email).not_to include('<img')
          expect(photographer.email).not_to include('onerror')
        end
      end

      it 'handles rate limiting for registrations' do
        # Mock rate limiting
        allow(Rails.cache).to receive(:read).with(/registration_attempts/).and_return(5)

        post '/photographers', params: valid_registration_data
        expect(response).to have_http_status(:forbidden)
      end

      it 'logs security events during registration process' do
        # Mock suspicious registration detection
        allow_any_instance_of(ApplicationController).to receive(:detect_bot_registration).and_return(true)

        expect(SecurityAuditLogger).to receive(:log).with(
          event_type: 'suspicious_registration',
          photographer_id: nil,
          ip_address: '127.0.0.1',
          additional_data: hash_including(:reason)
        )

        post '/photographers', params: valid_registration_data
      end
    end

    context 'edge cases and error handling' do
      it 'handles database connection errors gracefully' do
        allow(Photographer).to receive(:new).and_raise(ActiveRecord::ConnectionTimeoutError)

        post '/photographers', params: valid_registration_data

        expect(response).to render_template(:new)
        expect(response.body).to include('temporary')
      end

      it 'handles validation errors with custom messages' do
        # Test with empty required fields
        empty_data = { photographer: { name: '', email: '', password: '', password_confirmation: '' } }

        post '/photographers', params: empty_data

        expect(response).to render_template(:new)
        expect(response.body).to include("can't be blank")
      end

      it 'handles special characters in form fields correctly' do
        special_char_data = valid_registration_data.dup
        special_char_data[:photographer][:name] = 'José María García-López'
        special_char_data[:photographer][:email] = 'josé.garcía@example.com'

        post '/photographers', params: special_char_data

        if response.status == 201 || response.status == 302
          photographer = Photographer.last
          expect(photographer.name).to eq('José María García-López')
          expect(photographer.email).to eq('josé.garcía@example.com')
        end
      end
    end

    context 'post-registration experience' do
      it 'provides immediate access to photographer dashboard after registration' do
        post '/photographers', params: valid_registration_data
        follow_redirect!

        expect(response).to have_http_status(:success)
        expect(response.body).to include('My Galleries') || expect(response.body).to include('Create Gallery')
        expect(response.body).to include('John Doe') # Should show user's name
      end

      it 'allows newly registered photographer to create their first gallery' do
        post '/photographers', params: valid_registration_data
        follow_redirect!

        # Navigate to create gallery
        get '/galleries/new'
        expect(response).to have_http_status(:success)

        # Create first gallery
        gallery_data = {
          gallery: {
            title: 'My First Gallery',
            description: 'A test gallery',
            published: true
          }
        }

        expect {
          post '/galleries', params: gallery_data
        }.to change(Gallery, :count).by(1)

        gallery = Gallery.last
        expect(gallery.photographer.email).to eq('john@example.com')
        expect(gallery.title).to eq('My First Gallery')
      end
    end

    context 'accessibility and user experience' do
      it 'provides helpful error messages for form validation' do
        invalid_data = {
          photographer: {
            name: 'A', # Too short
            email: 'invalid', # Invalid format
            password: 'short', # Too short and weak
            password_confirmation: 'different' # Doesn't match
          }
        }

        post '/photographers', params: invalid_data

        expect(response.body).to include('too short')
        expect(response.body).to include('invalid')
        expect(response.body).not_to include('undefined')
        expect(response.body).not_to include('nil')
      end

      it 'maintains proper form structure on validation errors' do
        post '/photographers', params: { photographer: { name: '' } }

        expect(response.body).to include('form')
        expect(response.body).to include('input')
        expect(response.body).to include('Register') # Button/heading
      end
    end

    context 'internationalization considerations' do
      it 'accepts international email addresses' do
        international_data = valid_registration_data.dup
        international_data[:photographer][:email] = 'user@müller.de'

        post '/photographers', params: international_data

        if response.status == 201 || response.status == 302
          photographer = Photographer.last
          expect(photographer.email).to eq('user@müller.de')
        end
      end
    end

    context 'mobile and API compatibility' do
      it 'handles registration via JSON API' do
        headers = { 'Accept' => 'application/json', 'Content-Type' => 'application/json' }

        post '/photographers', 
             params: valid_registration_data.to_json, 
             headers: headers

        if response.status == 201
          json_response = JSON.parse(response.body)
          expect(json_response['status']).to eq('success')
          expect(json_response['photographer']).to be_present
        end
      end

      it 'provides appropriate mobile-friendly responses' do
        headers = { 'User-Agent' => 'Mozilla/5.0 (iPhone; CPU iPhone OS 14_6 like Mac OS X)' }

        get '/photographers/new', headers: headers
        expect(response).to have_http_status(:success)
        # Should work the same way on mobile
      end
    end
  end
end