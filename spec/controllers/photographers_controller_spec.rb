require 'rails_helper'

RSpec.describe PhotographersController, type: :controller do
  let(:photographer) { create(:photographer) }
  let(:valid_attributes) do
    {
      name: 'John Doe',
      email: 'john@example.com',
      password: 'SecurePassword123!',
      password_confirmation: 'SecurePassword123!'
    }
  end

  let(:invalid_attributes) do
    {
      name: '',
      email: 'invalid-email',
      password: 'weak',
      password_confirmation: 'different'
    }
  end

  describe "GET #new" do
    context "when not logged in" do
      it "returns success" do
        get :new
        expect(response).to have_http_status(:success)
      end

      it "renders the new template" do
        get :new
        expect(response).to render_template(:new)
      end

      it "assigns a new photographer" do
        get :new
        expect(assigns(:photographer)).to be_a_new(Photographer)
      end
    end

    context "when already logged in" do
      before { sign_in(photographer) }

      it "redirects to galleries" do
        get :new
        expect(response).to redirect_to(galleries_path)
      end

      it "sets flash notice" do
        get :new
        expect(flash[:notice]).to eq("You are already signed in.")
      end
    end
  end

  describe "POST #create" do
    context "with valid parameters" do
      it "creates a new photographer" do
        expect {
          post :create, params: { photographer: valid_attributes }
        }.to change(Photographer, :count).by(1)
      end

      it "assigns attributes correctly" do
        post :create, params: { photographer: valid_attributes }
        photographer = assigns(:photographer)
        
        expect(photographer.name).to eq('John Doe')
        expect(photographer.email).to eq('john@example.com')
        expect(photographer.active).to be true
      end

      it "signs in the new photographer automatically" do
        post :create, params: { photographer: valid_attributes }
        expect(session[:photographer_id]).to eq(assigns(:photographer).id)
      end

      it "redirects to galleries" do
        post :create, params: { photographer: valid_attributes }
        expect(response).to redirect_to(galleries_path)
      end

      it "sets success flash message" do
        post :create, params: { photographer: valid_attributes }
        expect(flash[:notice]).to eq("Welcome! Your account has been created.")
      end

      it "logs account creation security event" do
        expect(SecurityAuditLogger).to receive(:log).with(
          event_type: 'account_created',
          photographer_id: kind_of(Integer),
          ip_address: '0.0.0.0',
          additional_data: hash_including(:email)
        )

        post :create, params: { photographer: valid_attributes }
      end

      it "normalizes email address" do
        attrs = valid_attributes.merge(email: '  JOHN@EXAMPLE.COM  ')
        post :create, params: { photographer: attrs }
        
        expect(assigns(:photographer).email).to eq('john@example.com')
      end
    end

    context "with invalid parameters" do
      it "does not create a photographer" do
        expect {
          post :create, params: { photographer: invalid_attributes }
        }.not_to change(Photographer, :count)
      end

      it "renders the new template" do
        post :create, params: { photographer: invalid_attributes }
        expect(response).to render_template(:new)
      end

      it "does not sign in the user" do
        post :create, params: { photographer: invalid_attributes }
        expect(session[:photographer_id]).to be_nil
      end

      it "assigns the photographer with errors" do
        post :create, params: { photographer: invalid_attributes }
        photographer = assigns(:photographer)
        
        expect(photographer).to be_a_new(Photographer)
        expect(photographer.errors).to be_present
      end

      it "preserves form data" do
        post :create, params: { photographer: invalid_attributes }
        photographer = assigns(:photographer)
        
        expect(photographer.name).to eq('')
        expect(photographer.email).to eq('invalid-email')
      end
    end

    context "with weak password" do
      let(:weak_password_attrs) do
        valid_attributes.merge(
          password: 'password123',
          password_confirmation: 'password123'
        )
      end

      it "rejects weak passwords" do
        post :create, params: { photographer: weak_password_attrs }
        
        photographer = assigns(:photographer)
        expect(photographer.errors[:password]).to be_present
        expect(response).to render_template(:new)
      end
    end

    context "with duplicate email" do
      before { create(:photographer, email: 'john@example.com') }

      it "rejects duplicate email addresses" do
        post :create, params: { photographer: valid_attributes }
        
        photographer = assigns(:photographer)
        expect(photographer.errors[:email]).to include('has already been taken')
        expect(response).to render_template(:new)
      end

      it "handles case-insensitive email duplicates" do
        attrs = valid_attributes.merge(email: 'JOHN@EXAMPLE.COM')
        post :create, params: { photographer: attrs }
        
        photographer = assigns(:photographer)
        expect(photographer.errors[:email]).to include('has already been taken')
      end
    end

    context "with malicious input" do
      it "sanitizes HTML in name field" do
        malicious_attrs = valid_attributes.merge(
          name: '<script>alert("xss")</script>Malicious User'
        )
        
        post :create, params: { photographer: malicious_attrs }
        photographer = assigns(:photographer)
        
        expect(photographer.name).not_to include('<script>')
        expect(photographer.name).not_to include('alert')
      end

      it "sanitizes email input" do
        malicious_attrs = valid_attributes.merge(
          email: '<img src=x onerror=alert(1)>@example.com'
        )
        
        post :create, params: { photographer: malicious_attrs }
        photographer = assigns(:photographer)
        
        expect(photographer.email).not_to include('<img')
        expect(photographer.email).not_to include('onerror')
      end
    end

    context "with SQL injection attempts" do
      it "prevents SQL injection in email field" do
        malicious_attrs = valid_attributes.merge(
          email: "test'; DROP TABLE photographers; --@example.com"
        )
        
        expect {
          post :create, params: { photographer: malicious_attrs }
        }.not_to change(Photographer, :count)
        
        # Verify photographers table still exists
        expect(Photographer.count).to be >= 0
      end
    end

    context "when already logged in" do
      before { sign_in(photographer) }

      it "redirects to galleries" do
        post :create, params: { photographer: valid_attributes }
        expect(response).to redirect_to(galleries_path)
      end

      it "does not create a new photographer" do
        expect {
          post :create, params: { photographer: valid_attributes }
        }.not_to change(Photographer, :count)
      end

      it "sets flash notice" do
        post :create, params: { photographer: valid_attributes }
        expect(flash[:notice]).to eq("You are already signed in.")
      end
    end
  end

  describe "security features" do
    describe "rate limiting" do
      before do
        allow(Rails.cache).to receive(:read).with(/registration_attempts/).and_return(5)
      end

      it "blocks registration when rate limited" do
        post :create, params: { photographer: valid_attributes }
        expect(response).to have_http_status(:forbidden)
      end

      it "returns JSON error for API requests" do
        request.headers['Accept'] = 'application/json'
        post :create, params: { photographer: valid_attributes }
        
        expect(response).to have_http_status(:forbidden)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to include('rate limit')
      end
    end

    describe "CSRF protection" do
      before do
        allow_any_instance_of(ActionController::Base).to receive(:protect_against_forgery?).and_return(true)
      end

      it "requires valid CSRF token" do
        expect {
          post :create, params: { photographer: valid_attributes }
        }.to raise_error(ActionController::InvalidAuthenticityToken)
      end
    end

    describe "suspicious activity detection" do
      it "logs suspicious registration patterns" do
        # Simulate bot-like behavior
        allow_any_instance_of(ApplicationController).to receive(:detect_bot_registration).and_return(true)
        
        expect(SecurityAuditLogger).to receive(:log).with(
          event_type: 'suspicious_registration',
          photographer_id: nil,
          ip_address: '0.0.0.0',
          additional_data: hash_including(:reason)
        )

        post :create, params: { photographer: valid_attributes }
      end
    end

    describe "password security validation" do
      it "enforces minimum password complexity" do
        weak_passwords = [
          'password',
          '12345678',
          'Password',
          'password123'
        ]

        weak_passwords.each do |weak_password|
          attrs = valid_attributes.merge(
            password: weak_password,
            password_confirmation: weak_password
          )
          
          post :create, params: { photographer: attrs }
          photographer = assigns(:photographer)
          
          expect(photographer.errors[:password]).to be_present,
            "Password '#{weak_password}' should be rejected"
        end
      end

      it "requires password confirmation match" do
        attrs = valid_attributes.merge(password_confirmation: 'DifferentPassword123!')
        
        post :create, params: { photographer: attrs }
        photographer = assigns(:photographer)
        
        expect(photographer.errors[:password_confirmation]).to include("doesn't match Password")
      end
    end
  end

  describe "error handling" do
    it "handles database connection errors gracefully" do
      allow(Photographer).to receive(:new).and_raise(ActiveRecord::ConnectionTimeoutError)
      
      post :create, params: { photographer: valid_attributes }
      
      expect(response).to render_template(:new)
      expect(flash.now[:alert]).to include('temporary')
    end

    it "handles validation errors gracefully" do
      # Simulate a validation error that might not be caught by model validations
      allow_any_instance_of(Photographer).to receive(:save).and_return(false)
      allow_any_instance_of(Photographer).to receive(:errors).and_return(
        double(full_messages: ['Something went wrong'])
      )
      
      post :create, params: { photographer: valid_attributes }
      
      expect(response).to render_template(:new)
      expect(flash.now[:alert]).to be_present
    end

    it "handles unexpected errors gracefully" do
      allow(Photographer).to receive(:new).and_raise(StandardError.new('Unexpected error'))
      
      post :create, params: { photographer: valid_attributes }
      
      expect(response).to render_template(:new)
      expect(flash.now[:alert]).to include('error')
    end
  end

  describe "performance considerations" do
    it "does not trigger N+1 queries" do
      expect { post :create, params: { photographer: valid_attributes } }
        .not_to exceed_query_limit(10) # Reasonable limit for creation
    end
  end

  describe "accessibility and user experience" do
    it "provides helpful validation messages" do
      post :create, params: { photographer: invalid_attributes }
      photographer = assigns(:photographer)
      
      expect(photographer.errors.full_messages).to all(be_a(String))
      expect(photographer.errors.full_messages).to all(be_present)
    end

    it "maintains form state on errors" do
      partial_attrs = {
        name: 'John Doe',
        email: 'invalid-email',
        password: 'ValidPassword123!',
        password_confirmation: 'ValidPassword123!'
      }
      
      post :create, params: { photographer: partial_attrs }
      photographer = assigns(:photographer)
      
      expect(photographer.name).to eq('John Doe')
      expect(photographer.email).to eq('invalid-email')
      # Password should not be preserved for security
      expect(photographer.password).to be_blank
    end

    it "sets appropriate page title" do
      get :new
      expect(assigns(:page_title)).to include('Register') || be_nil
    end
  end

  describe "email format validation" do
    it "accepts valid email formats" do
      valid_emails = [
        'user@example.com',
        'test.email+tag@domain.co.uk',
        'user123@sub.domain.com',
        'firstname.lastname@company.org'
      ]

      valid_emails.each do |email|
        attrs = valid_attributes.merge(email: email)
        post :create, params: { photographer: attrs }
        
        expect(assigns(:photographer).errors[:email]).to be_empty,
          "Email '#{email}' should be valid"
      end
    end

    it "rejects invalid email formats" do
      invalid_emails = [
        'plainaddress',
        '@missingdomain.com',
        'missing@.com',
        'spaces in@email.com',
        'double..dots@example.com'
      ]

      invalid_emails.each do |email|
        attrs = valid_attributes.merge(email: email)
        post :create, params: { photographer: attrs }
        
        expect(assigns(:photographer).errors[:email]).to be_present,
          "Email '#{email}' should be invalid"
      end
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