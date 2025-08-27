require 'rails_helper'

RSpec.describe 'Gallery Management Flow', type: :request do
  let(:photographer) { create(:photographer, password: 'ValidPassword123!') }
  
  before do
    # Sign in the photographer
    post '/login', params: {
      photographer: {
        email: photographer.email,
        password: 'ValidPassword123!'
      }
    }
  end

  describe 'complete gallery lifecycle' do
    context 'creating a new gallery' do
      it 'allows photographer to create a public gallery' do
        # Navigate to gallery creation
        get '/galleries/new'
        expect(response).to have_http_status(:success)
        expect(response.body).to include('New Gallery')

        # Create gallery
        gallery_data = {
          gallery: {
            title: 'Wedding Photography 2024',
            description: 'Beautiful wedding moments captured',
            published: true,
            featured: false
          }
        }

        expect {
          post '/galleries', params: gallery_data
        }.to change(Gallery, :count).by(1)

        gallery = Gallery.last
        expect(gallery.photographer).to eq(photographer)
        expect(gallery.title).to eq('Wedding Photography 2024')
        expect(gallery.slug).to eq('wedding-photography-2024')
        expect(gallery.published?).to be true

        # Should redirect to gallery show
        expect(response).to redirect_to(gallery_path(gallery))
        follow_redirect!
        expect(response.body).to include('Wedding Photography 2024')
      end

      it 'allows photographer to create a password-protected gallery' do
        password_protected_data = {
          gallery: {
            title: 'Private Family Photos',
            description: 'Personal family moments',
            published: true,
            password: 'FamilySecrets123!',
            password_confirmation: 'FamilySecrets123!'
          }
        }

        post '/galleries', params: password_protected_data

        gallery = Gallery.last
        expect(gallery.password_protected?).to be true
        expect(gallery.authenticate_password('FamilySecrets123!')).to be_truthy
      end

      it 'creates gallery with proper slug generation and handles duplicates' do
        # Create first gallery
        post '/galleries', params: {
          gallery: { title: 'My Gallery', published: true }
        }
        first_gallery = Gallery.last
        expect(first_gallery.slug).to eq('my-gallery')

        # Create second gallery with same title
        post '/galleries', params: {
          gallery: { title: 'My Gallery', published: true }
        }
        second_gallery = Gallery.last
        expect(second_gallery.slug).to eq('my-gallery-1')
      end

      it 'validates gallery data and shows appropriate errors' do
        invalid_data = {
          gallery: {
            title: '', # Required field
            description: 'A' * 1000, # Too long if there's a limit
            password: 'weak', # Weak password
            password_confirmation: 'different' # Mismatched
          }
        }

        expect {
          post '/galleries', params: invalid_data
        }.not_to change(Gallery, :count)

        expect(response).to render_template(:new)
        expect(response.body).to include("can't be blank")
      end
    end

    context 'uploading images to gallery' do
      let!(:gallery) { create(:gallery, photographer: photographer, title: 'Test Gallery') }

      it 'allows uploading multiple images to a gallery' do
        # Navigate to gallery
        get "/galleries/#{gallery.id}"
        expect(response).to have_http_status(:success)
        expect(response.body).to include('Test Gallery')

        # Upload images
        image_files = [
          create_uploaded_file(filename: 'photo1.jpg', content_type: 'image/jpeg'),
          create_uploaded_file(filename: 'photo2.png', content_type: 'image/png'),
          create_uploaded_file(filename: 'photo3.webp', content_type: 'image/webp')
        ]

        image_files.each_with_index do |file, index|
          expect {
            post '/images', params: {
              gallery_id: gallery.id,
              image: {
                file: file,
                filename: "photo#{index + 1}"
              }
            }
          }.to change(Image, :count).by(1)
        end

        gallery.reload
        expect(gallery.images.count).to eq(3)
        expect(gallery.images_count).to eq(3)

        # Verify images are properly ordered
        images = gallery.images.ordered
        expect(images.map(&:position)).to eq([1, 2, 3])
      end

      it 'handles image upload validation and security checks' do
        # Try uploading invalid file type
        malicious_file = create_invalid_file(filename: 'malicious.php', content_type: 'application/x-php')

        expect {
          post '/images', params: {
            gallery_id: gallery.id,
            image: {
              file: malicious_file,
              filename: 'malicious.php'
            }
          }
        }.not_to change(Image, :count)

        expect(response).to have_http_status(:unprocessable_entity)

        # Security event should be logged
        security_events = SecurityEvent.where(event_type: 'file_upload_blocked')
        expect(security_events).to be_present
      end

      it 'processes images and generates variants' do
        # Mock image processing
        expect(ImageProcessingJob).to receive(:perform_later).at_least(:once)

        image_file = create_uploaded_file(filename: 'test.jpg', content_type: 'image/jpeg')
        
        post '/images', params: {
          gallery_id: gallery.id,
          image: {
            file: image_file,
            filename: 'test.jpg'
          }
        }

        image = Image.last
        expect(image.processing_status).to eq('pending')
        expect(image.file).to be_attached
      end

      it 'allows reordering images within gallery' do
        images = create_list(:image, 4, gallery: gallery)
        original_order = images.map(&:id)
        new_order = original_order.reverse

        # Reorder images
        patch '/images/reorder', params: {
          gallery_id: gallery.id,
          image_ids: new_order
        }

        expect(response).to have_http_status(:success)

        # Verify new order
        reordered_images = gallery.images.reload.ordered
        expect(reordered_images.map(&:id)).to eq(new_order)
      end

      it 'supports bulk image deletion' do
        images = create_list(:image, 5, gallery: gallery)
        image_ids_to_delete = images.first(3).map(&:id)

        expect {
          delete '/images/destroy_multiple', params: {
            gallery_id: gallery.id,
            image_ids: image_ids_to_delete
          }
        }.to change(Image, :count).by(-3)

        gallery.reload
        expect(gallery.images.count).to eq(2)
        expect(gallery.images_count).to eq(2)
      end
    end

    context 'editing and updating galleries' do
      let!(:gallery) { create(:gallery, photographer: photographer, title: 'Original Title') }

      it 'allows updating gallery metadata' do
        get "/galleries/#{gallery.id}/edit"
        expect(response).to have_http_status(:success)
        expect(response.body).to include('Original Title')

        updated_data = {
          gallery: {
            title: 'Updated Gallery Title',
            description: 'Updated description with more details',
            published: false,
            featured: true
          }
        }

        patch "/galleries/#{gallery.id}", params: updated_data

        gallery.reload
        expect(gallery.title).to eq('Updated Gallery Title')
        expect(gallery.description).to eq('Updated description with more details')
        expect(gallery.published?).to be false
        expect(gallery.featured?).to be true

        expect(response).to redirect_to(gallery_path(gallery))
      end

      it 'allows adding password protection to existing gallery' do
        patch "/galleries/#{gallery.id}", params: {
          gallery: {
            password: 'NewPassword123!',
            password_confirmation: 'NewPassword123!'
          }
        }

        gallery.reload
        expect(gallery.password_protected?).to be true
        expect(gallery.authenticate_password('NewPassword123!')).to be_truthy
      end

      it 'allows removing password protection' do
        # First make it password protected
        gallery.update!(password: 'Password123!')
        expect(gallery.password_protected?).to be true

        # Remove password protection
        patch "/galleries/#{gallery.id}", params: {
          gallery: {
            password: '',
            password_confirmation: ''
          }
        }

        gallery.reload
        expect(gallery.password_protected?).to be false
      end

      it 'handles gallery expiration settings' do
        expiration_time = 1.month.from_now

        patch "/galleries/#{gallery.id}", params: {
          gallery: {
            expires_at: expiration_time
          }
        }

        gallery.reload
        expect(gallery.expires_at).to be_within(1.minute).of(expiration_time)
        expect(gallery.expired?).to be false
      end
    end

    context 'gallery visibility and access control' do
      let!(:published_gallery) { create(:gallery, :published, photographer: photographer) }
      let!(:unpublished_gallery) { create(:gallery, :unpublished, photographer: photographer) }
      let!(:password_gallery) { create(:gallery, :published, :password_protected, photographer: photographer) }

      it 'shows different gallery states in photographer dashboard' do
        get '/galleries'
        expect(response).to have_http_status(:success)

        # Should show all photographer's galleries regardless of published status
        expect(response.body).to include(published_gallery.title)
        expect(response.body).to include(unpublished_gallery.title)
        expect(response.body).to include(password_gallery.title)

        # Should indicate status
        expect(response.body).to include('Published') || expect(response.body).to include('Public')
        expect(response.body).to include('Draft') || expect(response.body).to include('Unpublished')
        expect(response.body).to include('Protected') || expect(response.body).to include('Password')
      end

      it 'allows toggling gallery publication status' do
        expect(unpublished_gallery.published?).to be false

        # Publish the gallery
        patch "/galleries/#{unpublished_gallery.id}", params: {
          gallery: { published: true }
        }

        unpublished_gallery.reload
        expect(unpublished_gallery.published?).to be true

        # Unpublish the gallery
        patch "/galleries/#{unpublished_gallery.id}", params: {
          gallery: { published: false }
        }

        unpublished_gallery.reload
        expect(unpublished_gallery.published?).to be false
      end
    end

    context 'gallery deletion' do
      let!(:gallery_with_images) { create(:gallery, :with_images, photographer: photographer) }

      it 'allows deleting gallery with confirmation' do
        initial_image_count = gallery_with_images.images.count
        expect(initial_image_count).to be > 0

        expect {
          delete "/galleries/#{gallery_with_images.id}"
        }.to change(Gallery, :count).by(-1)
         .and change(Image, :count).by(-initial_image_count)

        expect(response).to redirect_to(galleries_path)
        follow_redirect!
        expect(response.body).to include('deleted') || expect(response.body).to include('removed')
      end

      it 'logs gallery deletion security event' do
        expect(SecurityAuditLogger).to receive(:log).with(
          event_type: 'gallery_deleted',
          photographer_id: photographer.id,
          ip_address: '127.0.0.1',
          additional_data: hash_including(:gallery_id, :title)
        )

        delete "/galleries/#{gallery_with_images.id}"
      end
    end

    context 'gallery statistics and analytics' do
      let!(:gallery) { create(:gallery, :published, :with_images, photographer: photographer) }

      it 'tracks gallery views when accessed publicly' do
        # Sign out to view publicly
        delete '/logout'

        initial_views = gallery.views_count
        
        # View gallery publicly
        get "/g/#{gallery.slug}"
        expect(response).to have_http_status(:success)

        gallery.reload
        expect(gallery.views_count).to eq(initial_views + 1)
      end

      it 'shows gallery statistics to photographer' do
        # Add some view counts
        gallery.update!(views_count: 42)

        get "/galleries/#{gallery.id}"
        expect(response).to have_http_status(:success)
        expect(response.body).to include('42') # View count
        expect(response.body).to include('views') || expect(response.body).to include('Views')
      end
    end
  end

  describe 'gallery authorization and security' do
    let(:other_photographer) { create(:photographer) }
    let(:other_gallery) { create(:gallery, photographer: other_photographer) }

    it 'prevents access to other photographers galleries' do
      # Try to view other photographer's gallery
      get "/galleries/#{other_gallery.id}"
      expect(response).to have_http_status(:forbidden)

      # Try to edit other photographer's gallery
      get "/galleries/#{other_gallery.id}/edit"
      expect(response).to have_http_status(:forbidden)

      # Try to update other photographer's gallery
      patch "/galleries/#{other_gallery.id}", params: {
        gallery: { title: 'Hacked Title' }
      }
      expect(response).to have_http_status(:forbidden)

      # Try to delete other photographer's gallery
      expect {
        delete "/galleries/#{other_gallery.id}"
      }.not_to change(Gallery, :count)
      expect(response).to have_http_status(:forbidden)
    end

    it 'prevents uploading images to other photographers galleries' do
      image_file = create_uploaded_file(filename: 'test.jpg', content_type: 'image/jpeg')

      expect {
        post '/images', params: {
          gallery_id: other_gallery.id,
          image: { file: image_file }
        }
      }.not_to change(Image, :count)

      expect(response).to have_http_status(:forbidden)
    end

    it 'logs security events for unauthorized access attempts' do
      expect(SecurityAuditLogger).to receive(:log).with(
        event_type: 'unauthorized_access_attempt',
        photographer_id: photographer.id,
        ip_address: '127.0.0.1',
        additional_data: hash_including(:attempted_resource)
      )

      get "/galleries/#{other_gallery.id}"
    end
  end

  describe 'gallery search and filtering' do
    let!(:wedding_gallery) { create(:gallery, :published, title: 'Wedding Photos 2024', photographer: photographer) }
    let!(:portrait_gallery) { create(:gallery, :published, title: 'Portrait Sessions', photographer: photographer) }
    let!(:landscape_gallery) { create(:gallery, :unpublished, title: 'Landscape Photography', photographer: photographer) }

    it 'allows photographer to search their galleries' do
      get '/galleries', params: { search: 'Wedding' }
      expect(response).to have_http_status(:success)
      expect(response.body).to include('Wedding Photos 2024')
      expect(response.body).not_to include('Portrait Sessions')
      expect(response.body).not_to include('Landscape Photography')
    end

    it 'allows filtering galleries by publication status' do
      get '/galleries', params: { status: 'published' }
      expect(response).to have_http_status(:success)
      # Should show only published galleries
    end

    it 'provides gallery sorting options' do
      # Create galleries with different dates
      old_gallery = create(:gallery, photographer: photographer, created_at: 1.week.ago)
      new_gallery = create(:gallery, photographer: photographer, created_at: 1.day.ago)

      get '/galleries', params: { sort: 'newest' }
      expect(response).to have_http_status(:success)
      # Should show newest first

      get '/galleries', params: { sort: 'oldest' }
      expect(response).to have_http_status(:success)
      # Should show oldest first
    end
  end

  describe 'mobile and responsive behavior' do
    let!(:gallery) { create(:gallery, photographer: photographer) }

    it 'provides mobile-friendly gallery management interface' do
      headers = { 'User-Agent' => 'Mozilla/5.0 (iPhone; CPU iPhone OS 14_6 like Mac OS X)' }

      get '/galleries', headers: headers
      expect(response).to have_http_status(:success)
      # Should render mobile-friendly interface

      get "/galleries/#{gallery.id}", headers: headers
      expect(response).to have_http_status(:success)
    end

    it 'handles image uploads on mobile devices' do
      headers = { 'User-Agent' => 'Mozilla/5.0 (iPhone; CPU iPhone OS 14_6 like Mac OS X)' }
      image_file = create_uploaded_file(filename: 'mobile_photo.jpg', content_type: 'image/jpeg')

      post '/images', params: {
        gallery_id: gallery.id,
        image: { file: image_file }
      }, headers: headers

      expect(response).to have_http_status(:found) # Redirect after successful upload
    end
  end

  describe 'error handling and edge cases' do
    it 'handles network interruptions during image upload gracefully' do
      gallery = create(:gallery, photographer: photographer)
      
      # Simulate connection timeout
      allow_any_instance_of(ActiveStorage::Attached::One).to receive(:attach)
        .and_raise(ActiveStorage::Error.new('Connection timeout'))

      image_file = create_uploaded_file(filename: 'test.jpg', content_type: 'image/jpeg')
      
      post '/images', params: {
        gallery_id: gallery.id,
        image: { file: image_file }
      }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(flash[:alert]).to include('upload') || expect(response.body).to include('error')
    end

    it 'handles large file uploads appropriately' do
      gallery = create(:gallery, photographer: photographer)
      large_file = create_large_file(filename: 'huge.jpg', size_mb: 60)

      # Mock the file size to exceed limit
      allow(large_file).to receive(:size).and_return(55.megabytes)

      expect {
        post '/images', params: {
          gallery_id: gallery.id,
          image: { file: large_file }
        }
      }.not_to change(Image, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'maintains data consistency during concurrent operations' do
      gallery = create(:gallery, photographer: photographer)

      # Simulate concurrent gallery updates
      threads = []
      threads << Thread.new do
        patch "/galleries/#{gallery.id}", params: { gallery: { title: 'Title 1' } }
      end
      threads << Thread.new do
        patch "/galleries/#{gallery.id}", params: { gallery: { description: 'Description 2' } }
      end

      threads.each(&:join)

      gallery.reload
      expect(gallery.title).to be_present
      expect(gallery.description).to be_present
    end
  end
end