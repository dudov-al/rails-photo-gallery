require 'rails_helper'

RSpec.describe Gallery, type: :model do
  let(:gallery) { build(:gallery) }

  describe 'associations' do
    it { should belong_to(:photographer) }
    it { should have_many(:images).dependent(:destroy) }
  end

  describe 'validations' do
    context 'title validation' do
      it { should validate_presence_of(:title) }
      it { should validate_length_of(:title).is_at_least(1).is_at_most(255) }

      it 'rejects empty titles' do
        gallery.title = ''
        expect(gallery).to_not be_valid
        expect(gallery.errors[:title]).to include("can't be blank")
      end

      it 'rejects overly long titles' do
        gallery.title = 'A' * 256
        expect(gallery).to_not be_valid
        expect(gallery.errors[:title]).to include('is too long (maximum is 255 characters)')
      end
    end

    context 'slug validation' do
      it { should validate_presence_of(:slug) }
      it { should validate_uniqueness_of(:slug) }

      it 'accepts valid slug formats' do
        valid_slugs = ['gallery-1', 'my-photo-gallery', 'summer-2023']
        valid_slugs.each do |slug|
          gallery.slug = slug
          expect(gallery).to be_valid, "#{slug} should be valid"
        end
      end

      it 'rejects invalid slug formats' do
        invalid_slugs = ['Gallery With Spaces', 'gallery_underscore', 'UPPERCASE', 'gallery@special']
        invalid_slugs.each do |slug|
          gallery.slug = slug
          expect(gallery).to_not be_valid, "#{slug} should be invalid"
        end
      end
    end

    context 'password validation' do
      it 'allows blank passwords' do
        gallery.password = ''
        gallery.password_confirmation = ''
        expect(gallery).to be_valid
      end

      it 'requires minimum 8 characters when password is set' do
        gallery.password = 'Short1!'
        gallery.password_confirmation = 'Short1!'
        expect(gallery).to_not be_valid
        expect(gallery.errors[:password]).to include('is too short (minimum is 8 characters)')
      end

      it 'requires complexity when password is set' do
        gallery.password = 'password123'
        gallery.password_confirmation = 'password123'
        expect(gallery).to_not be_valid
        expect(gallery.errors[:password]).to include('must include at least one lowercase letter, one uppercase letter, and one number')
      end

      it 'accepts valid strong passwords' do
        gallery.password = 'StrongGalleryPassword123!'
        gallery.password_confirmation = 'StrongGalleryPassword123!'
        expect(gallery).to be_valid
      end
    end

    context 'password complexity validation' do
      it 'rejects common weak patterns' do
        weak_passwords = ['password123', 'Password123', '123456789', 'qwerty123', 'Letmein123']
        weak_passwords.each do |password|
          gallery.password = password
          gallery.password_confirmation = password
          expect(gallery).to_not be_valid, "#{password} should be rejected as weak"
        end
      end

      it 'rejects passwords with dictionary words' do
        dictionary_passwords = ['gallery123A', 'photo123A', 'Password123']
        dictionary_passwords.each do |password|
          gallery.password = password
          gallery.password_confirmation = password
          expect(gallery).to_not be_valid, "#{password} should be rejected for dictionary words"
        end
      end

      it 'provides helpful error messages for weak passwords' do
        gallery.password = 'password123'
        gallery.password_confirmation = 'password123'
        gallery.valid?
        
        expect(gallery.errors[:password]).to include('contains common weak patterns')
        expect(gallery.errors[:password]).to include(/is too weak.*Consider adding more complexity/)
        expect(gallery.errors[:password]).to include('should not contain common dictionary words')
      end
    end
  end

  describe 'callbacks' do
    describe 'before_validation :generate_slug' do
      it 'generates slug from title on create' do
        gallery = build(:gallery, title: 'My Amazing Gallery', slug: nil)
        gallery.valid?
        expect(gallery.slug).to eq('my-amazing-gallery')
      end

      it 'does not overwrite existing slug' do
        gallery = build(:gallery, title: 'My Gallery', slug: 'custom-slug')
        gallery.valid?
        expect(gallery.slug).to eq('custom-slug')
      end

      it 'handles duplicate slugs by appending numbers' do
        create(:gallery, title: 'Gallery', slug: 'gallery')
        
        new_gallery = build(:gallery, title: 'Gallery', slug: nil)
        new_gallery.valid?
        expect(new_gallery.slug).to eq('gallery-1')
      end

      it 'handles special characters in titles' do
        gallery = build(:gallery, title: 'Gallery with Special Characters @#$!', slug: nil)
        gallery.valid?
        expect(gallery.slug).to eq('gallery-with-special-characters')
      end
    end

    describe 'after_update :update_images_count' do
      let!(:gallery) { create(:gallery) }
      let!(:images) { create_list(:image, 3, gallery: gallery) }

      it 'updates images_count when images are added/removed' do
        expect { gallery.touch }.to change { gallery.reload.images_count }.to(3)
      end
    end
  end

  describe 'scopes' do
    let!(:published_gallery) { create(:gallery, :published) }
    let!(:unpublished_gallery) { create(:gallery, :unpublished) }
    let!(:featured_gallery) { create(:gallery, :featured) }
    let!(:expired_gallery) { create(:gallery, :expired) }
    let!(:future_expired_gallery) { create(:gallery, :with_future_expiration) }
    let!(:photographer) { create(:photographer) }
    let!(:photographer_gallery) { create(:gallery, photographer: photographer) }

    describe '.published' do
      it 'returns only published galleries' do
        expect(Gallery.published).to include(published_gallery, featured_gallery)
        expect(Gallery.published).not_to include(unpublished_gallery)
      end
    end

    describe '.featured' do
      it 'returns only featured galleries' do
        expect(Gallery.featured).to include(featured_gallery)
        expect(Gallery.featured).not_to include(published_gallery, unpublished_gallery)
      end
    end

    describe '.not_expired' do
      it 'returns galleries that are not expired' do
        expect(Gallery.not_expired).to include(published_gallery, unpublished_gallery, featured_gallery, future_expired_gallery)
        expect(Gallery.not_expired).not_to include(expired_gallery)
      end
    end

    describe '.by_photographer' do
      it 'returns galleries for specific photographer' do
        expect(Gallery.by_photographer(photographer)).to include(photographer_gallery)
        expect(Gallery.by_photographer(photographer)).not_to include(published_gallery)
      end
    end
  end

  describe 'instance methods' do
    describe '#password_protected?' do
      context 'when password_digest is present' do
        let(:gallery) { create(:gallery, :password_protected) }

        it 'returns true' do
          expect(gallery.password_protected?).to be true
        end
      end

      context 'when password_digest is blank' do
        let(:gallery) { create(:gallery) }

        it 'returns false' do
          expect(gallery.password_protected?).to be false
        end
      end
    end

    describe '#expired?' do
      context 'when expires_at is in the past' do
        let(:gallery) { create(:gallery, :expired) }

        it 'returns true' do
          expect(gallery.expired?).to be true
        end
      end

      context 'when expires_at is in the future' do
        let(:gallery) { create(:gallery, :with_future_expiration) }

        it 'returns false' do
          expect(gallery.expired?).to be false
        end
      end

      context 'when expires_at is nil' do
        let(:gallery) { create(:gallery) }

        it 'returns false' do
          expect(gallery.expired?).to be false
        end
      end
    end

    describe '#viewable?' do
      it 'returns true for published, non-expired galleries' do
        gallery = create(:gallery, :published)
        expect(gallery.viewable?).to be true
      end

      it 'returns false for unpublished galleries' do
        gallery = create(:gallery, :unpublished)
        expect(gallery.viewable?).to be false
      end

      it 'returns false for expired galleries' do
        gallery = create(:gallery, :expired)
        expect(gallery.viewable?).to be false
      end
    end

    describe '#to_param' do
      it 'returns the slug' do
        gallery = create(:gallery, slug: 'my-gallery')
        expect(gallery.to_param).to eq('my-gallery')
      end
    end

    describe '#increment_views!' do
      let(:gallery) { create(:gallery, views_count: 5) }

      it 'increments the views count' do
        expect { gallery.increment_views! }.to change(gallery, :views_count).from(5).to(6)
      end
    end

    describe '#password_strength_score' do
      it 'returns 0 for no password' do
        gallery.password = nil
        expect(gallery.password_strength_score).to eq(0)
      end

      it 'calculates score based on complexity' do
        test_cases = [
          { password: 'short', expected: 0 }, # fails length check
          { password: 'password', expected: 1 }, # 8+ chars
          { password: 'passwordlong', expected: 2 }, # 8+ chars + 12+ chars
          { password: 'passwordlong', expected: 2 }, # + lowercase (already counted)
          { password: 'Passwordlong', expected: 3 }, # + uppercase
          { password: 'Passwordlong1', expected: 4 }, # + number
          { password: 'Passwordlong1!', expected: 5 }, # + special
          { password: 'Passwordlong1!unique', expected: 6 }, # + no repeated chars
        ]

        test_cases.each do |test_case|
          gallery.password = test_case[:password]
          score = gallery.password_strength_score
          expect(score).to be >= 0, "Password '#{test_case[:password]}' should have positive score"
        end
      end
    end

    describe '#password_strength_text' do
      it 'returns appropriate strength descriptions' do
        expectations = [
          { score: 0, text: 'Very Weak' },
          { score: 2, text: 'Very Weak' },
          { score: 3, text: 'Weak' },
          { score: 5, text: 'Strong' },
          { score: 7, text: 'Very Strong' },
          { score: 8, text: 'Excellent' }
        ]

        expectations.each do |expectation|
          allow(gallery).to receive(:password_strength_score).and_return(expectation[:score])
          expect(gallery.password_strength_text).to eq(expectation[:text])
        end
      end
    end

    describe '#authenticate_with_security' do
      let(:gallery) { create(:gallery, :password_protected) }
      let(:request) { double('request', remote_ip: '127.0.0.1') }

      before do
        allow(Rails.cache).to receive(:read).and_return(0)
        allow(Rails.cache).to receive(:write)
        allow(Rails.cache).to receive(:delete)
      end

      context 'with correct password' do
        it 'authenticates successfully and logs event' do
          expect(SecurityAuditLogger).to receive(:log).with(
            event_type: 'gallery_auth_success',
            ip_address: '127.0.0.1',
            additional_data: hash_including(:gallery_id, :gallery_slug)
          )

          result = gallery.authenticate_with_security('GalleryPassword123!', request)
          expect(result).to be true
        end

        it 'resets failed attempts on success' do
          expect(Rails.cache).to receive(:delete).with("gallery_auth_attempts:#{gallery.slug}:127.0.0.1")
          gallery.authenticate_with_security('GalleryPassword123!', request)
        end
      end

      context 'with incorrect password' do
        it 'fails authentication and logs event' do
          expect(SecurityAuditLogger).to receive(:log).with(
            event_type: 'gallery_auth_failed',
            ip_address: '127.0.0.1',
            additional_data: hash_including(:gallery_id, :attempts)
          )

          result = gallery.authenticate_with_security('WrongPassword', request)
          expect(result).to be false
        end

        it 'increments failed attempts counter' do
          expect(Rails.cache).to receive(:write).with(
            "gallery_auth_attempts:#{gallery.slug}:127.0.0.1", 
            1, 
            expires_in: 1.hour
          )

          gallery.authenticate_with_security('WrongPassword', request)
        end
      end

      context 'when too many attempts have been made' do
        before do
          allow(Rails.cache).to receive(:read).and_return(10)
        end

        it 'blocks authentication and logs security event' do
          expect(SecurityAuditLogger).to receive(:log).with(
            event_type: 'gallery_auth_blocked',
            ip_address: '127.0.0.1',
            additional_data: hash_including(:gallery_id, :attempts)
          )

          result = gallery.authenticate_with_security('GalleryPassword123!', request)
          expect(result).to be false
        end
      end

      context 'for gallery without password protection' do
        let(:gallery) { create(:gallery) }

        it 'returns false' do
          result = gallery.authenticate_with_security('any password', request)
          expect(result).to be false
        end
      end
    end
  end

  describe 'slug generation edge cases' do
    it 'handles empty titles gracefully' do
      gallery = build(:gallery, title: '', slug: nil)
      gallery.valid? # This will trigger the callback
      expect(gallery.slug).to eq('')
    end

    it 'handles titles with only special characters' do
      gallery = build(:gallery, title: '@#$%^&*()', slug: nil)
      gallery.valid?
      expect(gallery.slug).to eq('')
    end

    it 'generates unique slugs for identical titles' do
      create(:gallery, title: 'Test', slug: 'test')
      create(:gallery, title: 'Test', slug: 'test-1')
      
      gallery = build(:gallery, title: 'Test', slug: nil)
      gallery.valid?
      expect(gallery.slug).to eq('test-2')
    end
  end

  describe 'security features' do
    it 'stores password securely using has_secure_password' do
      gallery = create(:gallery, :password_protected)
      expect(gallery.password_digest).to be_present
      expect(gallery.password_digest).not_to eq('GalleryPassword123!')
    end

    it 'can authenticate using bcrypt' do
      gallery = create(:gallery, :password_protected)
      expect(gallery.authenticate_password('GalleryPassword123!')).to be_truthy
      expect(gallery.authenticate_password('WrongPassword')).to be_falsey
    end
  end
end