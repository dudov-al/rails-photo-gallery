require 'rails_helper'

RSpec.describe Image, type: :model do
  let(:image) { build(:image) }

  describe 'associations' do
    it { should belong_to(:gallery) }
    it { should have_one_attached(:file) }
  end

  describe 'validations' do
    it { should validate_presence_of(:filename) }
    it { should validate_presence_of(:file) }
    it { should validate_presence_of(:format) }

    describe 'format validation' do
      it 'accepts valid image formats' do
        valid_formats = %w[jpeg jpg png webp avif gif heic heif]
        valid_formats.each do |format|
          image.format = format
          expect(image).to be_valid
        end
      end

      it 'rejects invalid formats' do
        invalid_formats = %w[pdf doc txt exe]
        invalid_formats.each do |format|
          image.format = format
          expect(image).to_not be_valid
        end
      end
    end

    describe 'file format validation' do
      it 'accepts valid image content types' do
        valid_types = %w[image/jpeg image/jpg image/png image/gif image/webp image/heic image/heif]
        
        valid_types.each do |content_type|
          image_with_file = build(:image, content_type: content_type)
          attach_file_to_record(image_with_file, :file, content_type: content_type)
          expect(image_with_file).to be_valid, "#{content_type} should be valid"
        end
      end

      it 'rejects invalid file types' do
        invalid_types = %w[application/pdf text/plain application/msword]
        
        invalid_types.each do |content_type|
          image_with_file = build(:image, content_type: content_type)
          attach_file_to_record(image_with_file, :file, content_type: content_type, content: 'invalid content')
          expect(image_with_file).to_not be_valid, "#{content_type} should be invalid"
        end
      end
    end

    describe 'file size validation' do
      it 'accepts files under size limit' do
        image_with_file = build(:image)
        blob = attach_file_to_record(image_with_file, :file)
        allow(blob).to receive(:byte_size).and_return(45.megabytes)
        
        expect(image_with_file).to be_valid
      end

      it 'rejects files over size limit' do
        image_with_file = build(:image)
        blob = attach_file_to_record(image_with_file, :file)
        allow(blob).to receive(:byte_size).and_return(55.megabytes)
        
        expect(image_with_file).to_not be_valid
        expect(image_with_file.errors[:file]).to include('must be less than 50MB')
      end
    end
  end

  describe 'enums' do
    it { should define_enum_for(:processing_status).with_values(pending: 0, processing: 1, completed: 2, failed: 3, retrying: 4) }
  end

  describe 'scopes' do
    let!(:image1) { create(:image, position: 2, created_at: 2.days.ago) }
    let!(:image2) { create(:image, position: 1, created_at: 1.day.ago) }
    let!(:jpeg_image) { create(:image, content_type: 'image/jpeg') }
    let!(:png_image) { create(:image, content_type: 'image/png') }
    let!(:completed_image) { create(:image, :completed) }
    let!(:failed_image) { create(:image, :failed_processing) }

    describe '.ordered' do
      it 'orders by position then created_at' do
        expect(Image.ordered).to eq([image2, image1])
      end
    end

    describe '.by_content_type' do
      it 'filters by content type' do
        expect(Image.by_content_type('image/jpeg')).to include(jpeg_image)
        expect(Image.by_content_type('image/jpeg')).not_to include(png_image)
      end
    end

    describe '.processing_incomplete' do
      it 'excludes completed images' do
        expect(Image.processing_incomplete).to include(image1, image2, failed_image)
        expect(Image.processing_incomplete).not_to include(completed_image)
      end
    end

    describe '.processing_failed' do
      it 'includes only failed and retrying images' do
        retrying_image = create(:image, :retrying_processing)
        
        expect(Image.processing_failed).to include(failed_image, retrying_image)
        expect(Image.processing_failed).not_to include(completed_image)
      end
    end
  end

  describe 'callbacks' do
    describe 'before_save :extract_metadata' do
      let(:image) { build(:image) }

      before do
        mock_image_processing
      end

      it 'extracts basic file metadata when file is attached' do
        attach_file_to_record(image, :file, filename: 'test.jpg', content_type: 'image/jpeg')
        
        image.save
        
        expect(image.content_type).to eq('image/jpeg')
        expect(image.file_size).to be > 0
        expect(image.format).to eq('jpeg')
        expect(image.filename).to eq('test.jpg')
      end

      it 'extracts image dimensions when available' do
        attach_file_to_record(image, :file)
        
        # Mock the image analysis
        allow(image.file).to receive(:analyze).and_return({ width: 1920, height: 1080 })
        
        image.save
        
        expect(image.width).to eq(1920)
        expect(image.height).to eq(1080)
      end

      it 'handles analysis failures gracefully' do
        attach_file_to_record(image, :file)
        allow(image.file).to receive(:analyze).and_raise(StandardError.new('Analysis failed'))
        
        expect { image.save }.not_to raise_error
      end

      it 'sets filename from attached file if blank' do
        image.filename = nil
        attach_file_to_record(image, :file, filename: 'uploaded_photo.jpg')
        
        image.save
        
        expect(image.filename).to eq('uploaded_photo.jpg')
      end
    end

    describe 'after_create callbacks' do
      it 'enqueues processing job' do
        expect(ImageProcessingJob).to receive(:perform_later)
        create(:image)
      end

      it 'updates gallery images count' do
        gallery = create(:gallery, images_count: 0)
        
        expect { create(:image, gallery: gallery) }.to change { gallery.reload.images_count }.by(1)
      end
    end

    describe 'after_destroy callback' do
      it 'updates gallery images count' do
        gallery = create(:gallery)
        image = create(:image, gallery: gallery)
        gallery.update_column(:images_count, 1)
        
        expect { image.destroy }.to change { gallery.reload.images_count }.by(-1)
      end
    end
  end

  describe 'variant methods' do
    let(:image) { create(:image, :completed) }

    describe '#thumbnail' do
      context 'when variant is generated' do
        it 'returns the generated variant URL' do
          expect(image).to receive(:variant_generated?).with(:thumbnail).and_return(true)
          expect(image).to receive(:variant_url).with(:thumbnail).and_return('/variants/thumb.webp')
          
          result = image.thumbnail
          expect(result).to eq('/variants/thumb.webp')
        end
      end

      context 'when variant is not generated' do
        it 'returns Active Storage variant' do
          expect(image).to receive(:variant_generated?).with(:thumbnail).and_return(false)
          
          variant = image.thumbnail
          expect(variant).to be_an(ActiveStorage::Variant)
        end
      end

      it 'accepts custom size parameters' do
        variant = image.thumbnail(size: [200, 200])
        expect(variant.variation.transformations[:resize_to_limit]).to eq([200, 200])
      end
    end

    describe '#web_size' do
      it 'returns web-optimized variant' do
        variant = image.web_size
        expect(variant.variation.transformations[:resize_to_limit]).to eq([1200, 1200])
        expect(variant.variation.transformations[:format]).to eq(:webp)
        expect(variant.variation.transformations[:quality]).to eq(90)
      end
    end

    describe '#preview_size' do
      it 'returns preview variant' do
        variant = image.preview_size
        expect(variant.variation.transformations[:resize_to_limit]).to eq([800, 600])
        expect(variant.variation.transformations[:format]).to eq(:webp)
        expect(variant.variation.transformations[:quality]).to eq(85)
      end
    end
  end

  describe 'URL methods' do
    let(:image) { create(:image) }

    describe '#download_url' do
      it 'returns signed URL for download' do
        expect(image.file.blob).to receive(:signed_url)
          .with(expires_in: 1.hour, disposition: "attachment")
          .and_return('https://example.com/download/123')
        
        url = image.download_url
        expect(url).to eq('https://example.com/download/123')
      end
    end

    describe 'variant URL methods' do
      let(:image) { create(:image, :completed) }

      it 'returns variant URLs when available' do
        %w[thumbnail_url web_url preview_url].each do |method|
          expect(image.send(method)).to be_present
        end
      end
    end
  end

  describe 'variant management' do
    let(:image) { create(:image, :completed) }

    describe '#variant_generated?' do
      it 'returns true for completed variants' do
        expect(image.variant_generated?(:thumbnail)).to be true
        expect(image.variant_generated?(:web)).to be true
        expect(image.variant_generated?(:preview)).to be true
      end

      it 'returns false for non-existent variants' do
        expect(image.variant_generated?(:nonexistent)).to be false
      end
    end

    describe '#variants_complete?' do
      it 'returns true when all variants are generated' do
        expect(image.variants_complete?).to be true
      end

      it 'returns false when variants are missing' do
        image.variants_generated = { "thumbnail" => { "status" => "completed" } }
        expect(image.variants_complete?).to be false
      end
    end

    describe '#variant_url' do
      it 'returns stored variant URL' do
        url = image.variant_url(:thumbnail)
        expect(url).to eq('/variants/thumb_123.webp')
      end
    end
  end

  describe 'processing information' do
    describe '#processing_duration' do
      context 'when processing timestamps are present' do
        let(:image) { create(:image, processing_started_at: 5.minutes.ago, processing_completed_at: 2.minutes.ago) }

        it 'calculates processing duration' do
          expect(image.processing_duration).to be_within(1.second).of(3.minutes)
        end
      end

      context 'when timestamps are missing' do
        let(:image) { create(:image, processing_started_at: nil) }

        it 'returns nil' do
          expect(image.processing_duration).to be_nil
        end
      end
    end
  end

  describe 'file information helpers' do
    describe '#file_extension' do
      it 'returns lowercase file extension' do
        image = build(:image, filename: 'MyPhoto.JPG')
        expect(image.file_extension).to eq('.jpg')
      end

      it 'handles files without extensions' do
        image = build(:image, filename: 'photo')
        expect(image.file_extension).to eq('')
      end
    end

    describe '#human_file_size' do
      it 'formats bytes correctly' do
        test_cases = [
          { size: 0, expected: '0 Bytes' },
          { size: 512, expected: '512.0 Bytes' },
          { size: 1024, expected: '1.0 KB' },
          { size: 1_048_576, expected: '1.0 MB' },
          { size: 1_073_741_824, expected: '1.0 GB' },
          { size: 1_536, expected: '1.5 KB' },
          { size: 2_621_440, expected: '2.5 MB' }
        ]

        test_cases.each do |test_case|
          image = build(:image, file_size: test_case[:size])
          expect(image.human_file_size).to eq(test_case[:expected])
        end
      end

      it 'handles nil file size' do
        image = build(:image, file_size: nil)
        expect(image.human_file_size).to eq('0 Bytes')
      end
    end
  end

  describe 'constants and configuration' do
    it 'defines variant configurations' do
      expect(Image::VARIANT_CONFIGS).to be_a(Hash)
      expect(Image::VARIANT_CONFIGS).to have_key(:thumbnail)
      expect(Image::VARIANT_CONFIGS).to have_key(:web)
      expect(Image::VARIANT_CONFIGS).to have_key(:preview)
    end

    it 'has frozen variant configurations' do
      expect(Image::VARIANT_CONFIGS).to be_frozen
    end
  end

  describe 'security validations' do
    it 'rejects executable file uploads' do
      image = build(:image, :invalid_format)
      expect(image).to_not be_valid
      expect(image.errors[:file]).to include('must be a valid image format (JPEG, PNG, GIF, WebP, HEIC, HEIF)')
    end

    it 'validates file size limits for security' do
      image = build(:image, :oversized_file)
      attach_file_to_record(image, :file, filename: 'huge.jpg', content_type: 'image/jpeg')
      
      # Mock the byte size to exceed limit
      allow_any_instance_of(ActiveStorage::Blob).to receive(:byte_size).and_return(55.megabytes)
      
      expect(image).to_not be_valid
      expect(image.errors[:file]).to include('must be less than 50MB')
    end
  end

  describe 'Active Storage integration' do
    it 'properly attaches files through factory' do
      image = create(:image, :with_jpeg_file)
      expect(image.file).to be_attached
      expect(image.file.content_type).to eq('image/jpeg')
    end

    it 'handles different image formats' do
      formats = [
        { trait: :with_jpeg_file, type: 'image/jpeg' },
        { trait: :with_png_file, type: 'image/png' },
        { trait: :with_webp_file, type: 'image/webp' }
      ]

      formats.each do |format_test|
        image = create(:image, format_test[:trait])
        expect(image.file).to be_attached
        expect(image.file.content_type).to eq(format_test[:type])
      end
    end
  end
end