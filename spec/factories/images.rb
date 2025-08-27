FactoryBot.define do
  factory :image do
    association :gallery
    sequence(:filename) { |n| "image_#{n}.jpg" }
    content_type { "image/jpeg" }
    file_size { 1.megabyte }
    width { 1920 }
    height { 1080 }
    format { "jpeg" }
    processing_status { :pending }
    position { 1 }
    metadata { { "color_mode" => "RGB", "orientation" => 1 } }
    variants_generated { {} }
    processing_started_at { nil }
    processing_completed_at { nil }

    # Attach a test file after creation
    after(:create) do |image|
      image.file.attach(
        io: StringIO.new(create_test_image_data('image/jpeg')),
        filename: image.filename,
        content_type: image.content_type
      )
    end

    trait :with_jpeg_file do
      filename { "test_image.jpg" }
      content_type { "image/jpeg" }
      format { "jpeg" }
      
      after(:create) do |image|
        image.file.attach(
          io: StringIO.new(create_test_image_data('image/jpeg')),
          filename: image.filename,
          content_type: image.content_type
        )
      end
    end

    trait :with_png_file do
      filename { "test_image.png" }
      content_type { "image/png" }
      format { "png" }
      
      after(:create) do |image|
        image.file.attach(
          io: StringIO.new(create_test_image_data('image/png')),
          filename: image.filename,
          content_type: image.content_type
        )
      end
    end

    trait :with_webp_file do
      filename { "test_image.webp" }
      content_type { "image/webp" }
      format { "webp" }
      
      after(:create) do |image|
        image.file.attach(
          io: StringIO.new(create_test_image_data('image/webp')),
          filename: image.filename,
          content_type: image.content_type
        )
      end
    end

    trait :large_file do
      file_size { 45.megabytes }
      width { 4000 }
      height { 3000 }
    end

    trait :oversized_file do
      file_size { 55.megabytes } # Over 50MB limit
      width { 8000 }
      height { 6000 }
    end

    trait :small_file do
      file_size { 100.kilobytes }
      width { 800 }
      height { 600 }
    end

    # Processing status traits
    trait :processing do
      processing_status { :processing }
      processing_started_at { 5.minutes.ago }
    end

    trait :completed do
      processing_status { :completed }
      processing_started_at { 10.minutes.ago }
      processing_completed_at { 5.minutes.ago }
      variants_generated do
        {
          "thumbnail" => { "status" => "completed", "url" => "/variants/thumb_123.webp" },
          "web" => { "status" => "completed", "url" => "/variants/web_123.webp" },
          "preview" => { "status" => "completed", "url" => "/variants/preview_123.webp" }
        }
      end
    end

    trait :failed_processing do
      processing_status { :failed }
      processing_started_at { 10.minutes.ago }
      processing_completed_at { 8.minutes.ago }
    end

    trait :retrying_processing do
      processing_status { :retrying }
      processing_started_at { 2.minutes.ago }
    end

    # Position traits for testing ordering
    trait :first_position do
      position { 1 }
    end

    trait :last_position do
      position { 999 }
    end

    # Different aspect ratios for testing
    trait :portrait do
      width { 1080 }
      height { 1920 }
    end

    trait :landscape do
      width { 1920 }
      height { 1080 }
    end

    trait :square do
      width { 1080 }
      height { 1080 }
    end

    # Invalid file types for security testing
    trait :invalid_format do
      filename { "malicious.exe" }
      content_type { "application/octet-stream" }
      format { "exe" }
      
      after(:create) do |image|
        image.file.attach(
          io: StringIO.new("This is not an image file"),
          filename: image.filename,
          content_type: image.content_type
        )
      end
    end

    # For testing metadata extraction
    trait :with_rich_metadata do
      metadata do
        {
          "color_mode" => "RGB",
          "orientation" => 1,
          "camera_make" => "Canon",
          "camera_model" => "EOS R5",
          "exposure_time" => "1/125",
          "f_number" => "f/2.8",
          "iso_speed" => 400,
          "focal_length" => "85mm",
          "date_taken" => "2023-01-15T10:30:00Z"
        }
      end
    end

    # Helper method to create test image data
    def create_test_image_data(content_type)
      case content_type
      when 'image/jpeg'
        # Minimal valid JPEG
        jpeg_header = [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46].pack('C*')
        jpeg_footer = [0xFF, 0xD9].pack('C*')
        jpeg_header + "\x00" * 100 + jpeg_footer
      when 'image/png'
        # PNG signature + minimal IHDR + IEND
        [137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 
         0, 0, 0, 1, 0, 0, 0, 1, 8, 2, 0, 0, 0, 144, 119, 83, 222,
         0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130].pack('C*')
      when 'image/webp'
        "RIFF\x20\x00\x00\x00WEBPVP8 \x14\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
      else
        "Binary image data"
      end
    end
  end
end