module ActiveStorageHelpers
  def create_file_blob(filename: 'test.jpg', content_type: 'image/jpeg', content: nil)
    content ||= create_test_image_data(content_type)
    
    ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(content),
      filename: filename,
      content_type: content_type
    )
  end

  def attach_file_to_record(record, attribute, filename: 'test.jpg', content_type: 'image/jpeg', content: nil)
    blob = create_file_blob(filename: filename, content_type: content_type, content: content)
    record.public_send(attribute).attach(blob)
    blob
  end

  def create_test_image_data(content_type = 'image/jpeg')
    case content_type
    when 'image/jpeg'
      # Minimal valid JPEG header and footer
      jpeg_header = [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46].pack('C*')
      jpeg_body = "\x00" * 100  # Minimal body
      jpeg_footer = [0xFF, 0xD9].pack('C*')
      jpeg_header + jpeg_body + jpeg_footer
    when 'image/png'
      # PNG signature + minimal IHDR chunk + IEND chunk
      png_signature = [137, 80, 78, 71, 13, 10, 26, 10].pack('C*')
      ihdr = [0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8, 2, 0, 0, 0, 144, 119, 83, 222].pack('C*')
      iend = [0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130].pack('C*')
      png_signature + ihdr + iend
    when 'image/gif'
      # GIF87a header + minimal data
      "GIF87a\x01\x00\x01\x00\x00\x00\x00!\xF9\x04\x01\x00\x00\x00\x00,\x00\x00\x00\x00\x01\x00\x01\x00\x00\x02\x02\x04\x01\x00;"
    when 'image/webp'
      # WebP RIFF header + minimal VP8 data
      "RIFF\x20\x00\x00\x00WEBPVP8 \x14\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
    else
      # Fallback generic binary data
      "Binary file content for #{content_type}"
    end
  end

  def create_uploaded_file(filename: 'test.jpg', content_type: 'image/jpeg', content: nil)
    content ||= create_test_image_data(content_type)
    temp_file = Tempfile.new([File.basename(filename, '.*'), File.extname(filename)])
    
    if content_type.start_with?('image/')
      temp_file.binmode
    end
    
    temp_file.write(content)
    temp_file.rewind

    ActionDispatch::Http::UploadedFile.new(
      tempfile: temp_file,
      filename: filename,
      type: content_type
    )
  end

  def create_invalid_file(filename: 'malicious.php', content_type: 'application/x-php')
    content = "<?php echo 'This should not be processed'; ?>"
    create_uploaded_file(filename: filename, content_type: content_type, content: content)
  end

  def create_large_file(filename: 'large.jpg', size_mb: 60)
    content = create_test_image_data('image/jpeg')
    # Pad with additional data to reach desired size
    padding = 'x' * (size_mb * 1024 * 1024 - content.length)
    create_uploaded_file(filename: filename, content_type: 'image/jpeg', content: content + padding)
  end

  def mock_image_processing
    # Mock ImageProcessingJob for tests
    allow(ImageProcessingJob).to receive(:perform_later)
  end

  def stub_active_storage_service
    # Stub Active Storage service calls for faster tests
    allow_any_instance_of(ActiveStorage::Service::DiskService).to receive(:upload)
    allow_any_instance_of(ActiveStorage::Service::DiskService).to receive(:download)
  end
end

RSpec.configure do |config|
  config.include ActiveStorageHelpers
end