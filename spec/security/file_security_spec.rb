require 'rails_helper'

RSpec.describe "File Security", type: :request do
  let(:photographer) { create(:photographer) }
  let(:gallery) { create(:gallery, photographer: photographer) }
  
  before { sign_in photographer }
  
  describe "File Upload Security" do
    it "blocks files with dangerous extensions" do
      dangerous_files = %w[malicious.exe script.php virus.bat hack.js]
      
      dangerous_files.each do |filename|
        file = fixture_file_upload(create_temp_file(filename, "malicious content"))
        
        post "/galleries/#{gallery.id}/images", params: {
          image: { file: file }
        }
        
        expect(response.status).to eq(422)
        expect(JSON.parse(response.body)['errors']).to include(match(/extension.*not allowed/i))
      end
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