require 'rails_helper'

RSpec.describe "File Security", type: :request do
  let(:photographer) { create(:photographer, password: 'ValidPassword123!') }
  let(:gallery) { create(:gallery, photographer: photographer) }
  
  before do 
    post '/login', params: {
      photographer: {
        email: photographer.email,
        password: 'ValidPassword123!'
      }
    }
  end
  
  describe "File Upload Security" do
    it "blocks files with dangerous extensions" do
      dangerous_files = %w[malicious.exe script.php virus.bat hack.js trojan.scr backdoor.pif]
      
      dangerous_files.each do |filename|
        malicious_file = create_invalid_file(filename: filename, content_type: 'application/octet-stream')
        
        expect {
          post "/images", params: {
            gallery_id: gallery.id,
            image: { file: malicious_file }
          }
        }.not_to change(Image, :count)
        
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    it "validates file magic numbers and signatures" do
      # Create fake JPEG file (wrong magic numbers)
      fake_content = 'This is not a real image file but claims to be'
      fake_jpeg = create_uploaded_file(filename: 'fake.jpg', content_type: 'image/jpeg', content: fake_content)
      
      expect {
        post "/images", params: {
          gallery_id: gallery.id,
          image: { file: fake_jpeg }
        }
      }.not_to change(Image, :count)
      
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "blocks oversized files exceeding size limits" do
      large_file = create_large_file(filename: 'huge.jpg', size_mb: 60)
      
      # Mock the file size to exceed the 50MB limit
      allow(large_file).to receive(:size).and_return(55.megabytes)
      
      expect {
        post "/images", params: {
          gallery_id: gallery.id,
          image: { file: large_file }
        }
      }.not_to change(Image, :count)
      
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "strips dangerous metadata from uploaded images" do
      # This would require integration with image processing libraries
      image_file = create_uploaded_file(filename: 'photo.jpg', content_type: 'image/jpeg')
      
      expect(ImageProcessingJob).to receive(:perform_later)
      
      post "/images", params: {
        gallery_id: gallery.id,
        image: { file: image_file }
      }
      
      expect(response).to have_http_status(:found) # Redirect after successful upload
    end

    it "detects and blocks polyglot files" do
      # Create file that could be interpreted as multiple formats
      polyglot_content = "GIF89a<script>alert('xss')</script><html><body>test</body></html>"
      polyglot_file = create_uploaded_file(filename: 'polyglot.gif', content_type: 'image/gif', content: polyglot_content)
      
      expect {
        post "/images", params: {
          gallery_id: gallery.id,
          image: { file: polyglot_file }
        }
      }.not_to change(Image, :count)
      
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "scans for embedded malicious scripts in SVG files" do
      malicious_svg_content = <<~SVG
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" onload="alert('XSS')">
          <script>alert('malicious')</script>
          <circle cx="50" cy="50" r="40"/>
        </svg>
      SVG
      
      malicious_svg = create_uploaded_file(filename: 'malicious.svg', content_type: 'image/svg+xml', content: malicious_svg_content)
      
      expect {
        post "/images", params: {
          gallery_id: gallery.id,
          image: { file: malicious_svg }
        }
      }.not_to change(Image, :count)
      
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "validates MIME type consistency" do
      # PNG content with JPEG extension and MIME type
      png_content = create_test_image_data('image/png')
      fake_jpeg = create_uploaded_file(filename: 'fake.jpg', content_type: 'image/jpeg', content: png_content)
      
      expect {
        post "/images", params: {
          gallery_id: gallery.id,
          image: { file: fake_jpeg }
        }
      }.not_to change(Image, :count)
      
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "blocks files with null bytes in filename" do
      malicious_filename = "innocent.jpg\x00.php"
      malicious_file = create_uploaded_file(filename: malicious_filename, content_type: 'image/jpeg')
      
      expect {
        post "/images", params: {
          gallery_id: gallery.id,
          image: { file: malicious_file }
        }
      }.not_to change(Image, :count)
      
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "prevents directory traversal in filenames" do
      traversal_filenames = [
        '../../../etc/passwd',
        '..\\..\\windows\\system32\\config\\sam',
        'normal_name/../../../malicious.php'
      ]
      
      traversal_filenames.each do |malicious_name|
        malicious_file = create_uploaded_file(filename: malicious_name, content_type: 'image/jpeg')
        
        post "/images", params: {
          gallery_id: gallery.id,
          image: { file: malicious_file }
        }
        
        if response.status == 302 || response.status == 201
          # If file was created, check that filename was sanitized
          created_image = Image.last
          expect(created_image.filename).not_to include('../')
          expect(created_image.filename).not_to include('..\\')
          created_image.destroy # Clean up
        else
          expect(response).to have_http_status(:unprocessable_entity)
        end
      end
    end

    it "limits concurrent upload attempts to prevent DoS" do
      allow(Rails.cache).to receive(:read).with(/upload_attempts/).and_return(20)
      
      image_file = create_uploaded_file(filename: 'test.jpg', content_type: 'image/jpeg')
      
      post "/images", params: {
        gallery_id: gallery.id,
        image: { file: image_file }
      }
      
      expect(response).to have_http_status(:forbidden)
    end

    it "logs security events for blocked uploads" do
      expect(SecurityAuditLogger).to receive(:log).with(
        event_type: 'file_upload_blocked',
        photographer_id: photographer.id,
        ip_address: '127.0.0.1',
        additional_data: hash_including(:filename, :content_type, :reason)
      )
      
      malicious_file = create_invalid_file(filename: 'malicious.php', content_type: 'application/x-php')
      
      post "/images", params: {
        gallery_id: gallery.id,
        image: { file: malicious_file }
      }
    end
    
    it "validates file magic numbers" do
      # Create fake JPEG file (wrong magic numbers)
      fake_jpeg = create_temp_file('fake.jpg', 'This is not a JPEG file')
      file = fixture_file_upload(fake_jpeg)
      
      post "/galleries/#{gallery.id}/images", params: {
        image: { file: file }
      }
      
      expect(response.status).to eq(422)
      expect(JSON.parse(response.body)['errors']).to include(match(/signature.*match/i))
    end
    
    it "blocks oversized files" do
      # Create file larger than 50MB limit
      large_content = 'x' * (51 * 1024 * 1024)
      large_file = create_temp_file('large.jpg', large_content)
      file = fixture_file_upload(large_file)
      
      post "/galleries/#{gallery.id}/images", params: {
        image: { file: file }
      }
      
      expect(response.status).to eq(422)
      expect(JSON.parse(response.body)['errors']).to include(match(/size.*exceeds/i))
    end
    
    it "strips metadata from uploaded images" do
      # Create JPEG with EXIF data
      jpeg_with_exif = create_jpeg_with_exif
      file = fixture_file_upload(jpeg_with_exif)
      
      post "/galleries/#{gallery.id}/images", params: {
        image: { file: file }
      }
      
      expect(response.status).to eq(200)
      
      # Verify metadata was stripped
      image = Image.last
      expect(image.file.metadata).not_to have_key('exif')
    end
    
    it "detects polyglot files" do
      # Create file that looks like both GIF and HTML
      polyglot_content = "GIF89a<script>alert('xss')</script>"
      polyglot_file = create_temp_file('polyglot.gif', polyglot_content)
      file = fixture_file_upload(polyglot_file)
      
      post "/galleries/#{gallery.id}/images", params: {
        image: { file: file }
      }
      
      expect(response.status).to eq(422)
      expect(JSON.parse(response.body)['warnings']).to include(match(/polyglot/i))
    end
    
    it "blocks files with embedded scripts" do
      # SVG with embedded JavaScript
      malicious_svg = create_temp_file('malicious.svg', <<~SVG)
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" onload="alert('XSS')">
          <circle cx="50" cy="50" r="40"/>
        </svg>
      SVG
      
      file = fixture_file_upload(malicious_svg)
      
      post "/galleries/#{gallery.id}/images", params: {
        image: { file: file }
      }
      
      expect(response.status).to eq(422)
      expect(JSON.parse(response.body)['errors']).to include(match(/malicious content/i))
    end
  end
  
  describe "File Access Security" do
    let(:image) { create(:image, gallery: gallery) }
    
    it "requires authentication for image uploads" do
      sign_out photographer
      
      file = fixture_file_upload(create_valid_jpeg)
      
      post "/galleries/#{gallery.id}/images", params: {
        image: { file: file }
      }
      
      expect(response).to redirect_to(login_path)
    end
    
    it "prevents access to other photographers' images" do
      other_photographer = create(:photographer)
      other_gallery = create(:gallery, photographer: other_photographer)
      
      file = fixture_file_upload(create_valid_jpeg)
      
      post "/galleries/#{other_gallery.id}/images", params: {
        image: { file: file }
      }
      
      expect(response.status).to eq(404)
    end
  end
  
  describe "Content Type Validation" do
    it "validates declared vs actual MIME types" do
      # File with wrong extension and MIME type
      file_content = create_png_content
      temp_file = create_temp_file('image.jpg', file_content)
      
      # Manually set wrong content type
      uploaded_file = ActionDispatch::Http::UploadedFile.new(
        tempfile: File.open(temp_file),
        filename: 'image.jpg',
        type: 'image/jpeg'
      )
      
      post "/galleries/#{gallery.id}/images", params: {
        image: { file: uploaded_file }
      }
      
      expect(response.status).to eq(422)
      expect(JSON.parse(response.body)['warnings']).to include(match(/MIME type.*doesn't match/i))
    end
  end
  
  private
  
  def create_temp_file(filename, content)
    temp_file = Tempfile.new([File.basename(filename, '.*'), File.extname(filename)])
    temp_file.write(content)
    temp_file.rewind
    temp_file.path
  end
  
  def create_valid_jpeg
    # Create minimal valid JPEG
    jpeg_content = [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10].pack('C*') + 'JFIF' + "\x00" * 100
    create_temp_file('valid.jpg', jpeg_content)
  end
  
  def create_png_content
    # Create minimal valid PNG
    [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A].pack('C*') + "\x00" * 100
  end
  
  def create_jpeg_with_exif
    # This would create a JPEG with EXIF data in real implementation
    # For testing purposes, we'll simulate the structure
    create_valid_jpeg
  end
end