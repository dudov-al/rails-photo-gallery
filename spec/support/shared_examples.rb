# Shared examples for common test patterns

RSpec.shared_examples "requires authentication" do
  it "redirects to login when not authenticated" do
    expect(response).to redirect_to(new_session_path)
    expect(flash[:alert]).to eq("Please log in to continue.")
  end
end

RSpec.shared_examples "requires photographer ownership" do
  it "returns forbidden for non-owners" do
    expect(response).to have_http_status(:forbidden)
  end
end

RSpec.shared_examples "validates presence of" do |attribute|
  it "validates presence of #{attribute}" do
    subject.send("#{attribute}=", nil)
    expect(subject).not_to be_valid
    expect(subject.errors[attribute]).to include("can't be blank")
  end
end

RSpec.shared_examples "validates uniqueness of" do |attribute|
  it "validates uniqueness of #{attribute}" do
    existing_record = create(described_class.name.underscore.to_sym)
    subject.send("#{attribute}=", existing_record.send(attribute))
    expect(subject).not_to be_valid
    expect(subject.errors[attribute]).to include("has already been taken")
  end
end

RSpec.shared_examples "validates length of" do |attribute, options|
  if options[:minimum]
    it "validates minimum length of #{attribute}" do
      subject.send("#{attribute}=", 'a' * (options[:minimum] - 1))
      expect(subject).not_to be_valid
      expect(subject.errors[attribute]).to include("is too short (minimum is #{options[:minimum]} characters)")
    end
  end

  if options[:maximum]
    it "validates maximum length of #{attribute}" do
      subject.send("#{attribute}=", 'a' * (options[:maximum] + 1))
      expect(subject).not_to be_valid
      expect(subject.errors[attribute]).to include("is too long (maximum is #{options[:maximum]} characters)")
    end
  end
end

RSpec.shared_examples "logs security event" do |event_type, additional_data = {}|
  it "logs #{event_type} security event" do
    expect(SecurityAuditLogger).to receive(:log).with(
      event_type: event_type,
      photographer_id: anything,
      ip_address: anything,
      additional_data: hash_including(additional_data)
    )
    
    subject
  end
end

RSpec.shared_examples "sanitizes input" do |attribute, malicious_input|
  it "sanitizes malicious input in #{attribute}" do
    subject.send("#{attribute}=", malicious_input)
    subject.save if subject.respond_to?(:save)
    
    sanitized_value = subject.send(attribute)
    expect(sanitized_value).not_to include('<script>')
    expect(sanitized_value).not_to include('javascript:')
    expect(sanitized_value).not_to include('onerror=')
    expect(sanitized_value).not_to include('onload=')
  end
end

RSpec.shared_examples "rate limited endpoint" do |rate_limit_key|
  it "enforces rate limiting" do
    allow(Rails.cache).to receive(:read).with(/#{rate_limit_key}/).and_return(100)
    
    subject
    
    expect(response).to have_http_status(:forbidden)
    expect(response.body).to include('rate limit') || expect(response.body).to include('too many')
  end
end

RSpec.shared_examples "secure file upload" do
  it "blocks dangerous file extensions" do
    dangerous_files = %w[.exe .php .bat .js .sh .py .rb .pl]
    
    dangerous_files.each do |extension|
      malicious_file = create_uploaded_file(filename: "malicious#{extension}", content_type: 'application/octet-stream')
      
      expect {
        perform_file_upload(malicious_file)
      }.not_to change(Image, :count)
      
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  it "validates file size limits" do
    large_file = create_large_file(filename: 'huge.jpg', size_mb: 60)
    allow(large_file).to receive(:size).and_return(55.megabytes)
    
    expect {
      perform_file_upload(large_file)
    }.not_to change(Image, :count)
    
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "validates MIME types" do
    fake_image = create_uploaded_file(filename: 'fake.jpg', content_type: 'image/jpeg', content: 'not an image')
    
    expect {
      perform_file_upload(fake_image)
    }.not_to change(Image, :count)
    
    expect(response).to have_http_status(:unprocessable_entity)
  end
end

RSpec.shared_examples "password protected resource" do
  context "when password protected" do
    let(:resource) { create(resource_type, :password_protected) }

    it "requires password authentication" do
      subject
      expect(response).to redirect_to(password_form_path(resource.slug))
    end

    it "allows access after authentication" do
      authenticate_to_resource(resource)
      subject
      expect(response).to have_http_status(:success)
    end

    it "logs authentication attempts" do
      expect(SecurityAuditLogger).to receive(:log).with(
        event_type: match(/auth/),
        photographer_id: nil,
        ip_address: anything,
        additional_data: hash_including(:resource_id)
      )

      post_authentication_request(resource, 'wrong_password')
    end
  end
end

RSpec.shared_examples "handles database errors gracefully" do
  it "handles connection timeouts gracefully" do
    allow_any_instance_of(ActiveRecord::Base).to receive(:save!).and_raise(ActiveRecord::ConnectionTimeoutError)
    
    subject
    
    expect(response).to have_http_status(:service_unavailable) ||
      expect(response).to render_template(:error) ||
      expect(flash[:alert]).to include('temporary')
  end

  it "handles database lock timeouts gracefully" do
    allow_any_instance_of(ActiveRecord::Base).to receive(:save!).and_raise(ActiveRecord::LockWaitTimeout)
    
    subject
    
    expect(response).to have_http_status(:service_unavailable) ||
      expect(flash[:alert]).to include('busy')
  end
end

RSpec.shared_examples "validates email format" do |email_attribute = :email|
  it "accepts valid email formats" do
    valid_emails = %w[
      user@example.com
      test.email+tag@domain.co.uk
      user123@sub.domain.com
      firstname.lastname@company.org
    ]

    valid_emails.each do |email|
      subject.send("#{email_attribute}=", email)
      subject.valid?
      expect(subject.errors[email_attribute]).to be_empty, "#{email} should be valid"
    end
  end

  it "rejects invalid email formats" do
    invalid_emails = %w[
      plainaddress
      @domain.com
      user@
      user..double.dot@domain.com
      user@domain
      user name@domain.com
    ]

    invalid_emails.each do |email|
      subject.send("#{email_attribute}=", email)
      expect(subject).not_to be_valid, "#{email} should be invalid"
      expect(subject.errors[email_attribute]).to be_present
    end
  end
end

RSpec.shared_examples "timestamped model" do
  it "sets created_at timestamp" do
    subject.save!
    expect(subject.created_at).to be_within(1.second).of(Time.current)
  end

  it "updates updated_at timestamp" do
    subject.save!
    original_updated_at = subject.updated_at
    
    sleep(1)
    subject.touch
    
    expect(subject.updated_at).to be > original_updated_at
  end
end

RSpec.shared_examples "soft deletable" do
  it "implements soft deletion" do
    subject.save!
    
    expect { subject.destroy }.not_to change { described_class.count }
    expect(subject.reload.deleted_at).to be_present
  end

  it "excludes soft deleted records from default scope" do
    subject.save!
    subject.destroy
    
    expect(described_class.all).not_to include(subject)
  end
end

RSpec.shared_examples "auditable model" do
  it "creates audit trail on creation" do
    expect { subject.save! }.to change(SecurityEvent, :count).by(1)
    
    event = SecurityEvent.last
    expect(event.event_type).to eq("#{subject.class.name.downcase}_created")
  end

  it "creates audit trail on update" do
    subject.save!
    
    expect { subject.touch }.to change(SecurityEvent, :count).by(1)
    
    event = SecurityEvent.last
    expect(event.event_type).to eq("#{subject.class.name.downcase}_updated")
  end

  it "creates audit trail on deletion" do
    subject.save!
    
    expect { subject.destroy }.to change(SecurityEvent, :count).by(1)
    
    event = SecurityEvent.last
    expect(event.event_type).to eq("#{subject.class.name.downcase}_deleted")
  end
end

# Helper methods for shared examples
def perform_file_upload(file)
  raise NotImplementedError, "Define perform_file_upload method in your test"
end

def authenticate_to_resource(resource)
  raise NotImplementedError, "Define authenticate_to_resource method in your test"
end

def post_authentication_request(resource, password)
  raise NotImplementedError, "Define post_authentication_request method in your test"
end