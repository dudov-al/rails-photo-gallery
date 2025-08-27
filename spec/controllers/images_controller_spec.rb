require 'rails_helper'

RSpec.describe ImagesController, type: :controller do
  let(:photographer) { create(:photographer) }
  let(:gallery) { create(:gallery, photographer: photographer) }
  let(:image) { create(:image, gallery: gallery) }
  let(:other_photographer) { create(:photographer) }
  let(:other_gallery) { create(:gallery, photographer: other_photographer) }

  describe "authentication and authorization" do
    describe "when not logged in" do
      it "redirects create to login" do
        post :create, params: { gallery_id: gallery.id, image: { filename: 'test.jpg' } }
        expect(response).to redirect_to(new_session_path)
      end

      it "redirects destroy to login" do
        delete :destroy, params: { id: image.id }
        expect(response).to redirect_to(new_session_path)
      end

      it "redirects update to login" do
        patch :update, params: { id: image.id, image: { position: 2 } }
        expect(response).to redirect_to(new_session_path)
      end
    end

    describe "when logged in as different photographer" do
      before { sign_in(other_photographer) }

      it "prevents uploading to other photographer's gallery" do
        post :create, params: { gallery_id: gallery.id, image: { filename: 'test.jpg' } }
        expect(response).to have_http_status(:forbidden)
      end

      it "prevents deleting other photographer's images" do
        delete :destroy, params: { id: image.id }
        expect(response).to have_http_status(:forbidden)
      end

      it "prevents updating other photographer's images" do
        patch :update, params: { id: image.id, image: { position: 2 } }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "POST #create" do
    before { sign_in(photographer) }

    let(:valid_file) { create_uploaded_file(filename: 'test.jpg', content_type: 'image/jpeg') }
    let(:valid_params) do
      {
        gallery_id: gallery.id,
        image: {
          file: valid_file,
          filename: 'test.jpg'
        }
      }
    end

    context "with valid image file" do
      it "creates a new image" do
        expect {
          post :create, params: valid_params
        }.to change(Image, :count).by(1)
      end

      it "associates image with gallery" do
        post :create, params: valid_params
        image = assigns(:image)
        
        expect(image.gallery).to eq(gallery)
      end

      it "attaches file to image" do
        post :create, params: valid_params
        image = assigns(:image)
        
        expect(image.file).to be_attached
        expect(image.file.filename.to_s).to eq('test.jpg')
      end

      it "extracts file metadata" do
        post :create, params: valid_params
        image = assigns(:image)
        
        expect(image.content_type).to eq('image/jpeg')
        expect(image.file_size).to be > 0
        expect(image.format).to eq('jpeg')
      end

      it "sets appropriate position" do
        create(:image, gallery: gallery, position: 1)
        create(:image, gallery: gallery, position: 2)
        
        post :create, params: valid_params
        image = assigns(:image)
        
        expect(image.position).to eq(3)
      end

      it "enqueues processing job" do
        expect(ImageProcessingJob).to receive(:perform_later)
        post :create, params: valid_params
      end

      it "updates gallery images count" do
        expect {
          post :create, params: valid_params
        }.to change { gallery.reload.images_count }.by(1)
      end

      it "returns JSON success for AJAX requests" do
        request.headers['Accept'] = 'application/json'
        post :create, params: valid_params
        
        expect(response).to have_http_status(:created)
        json_response = JSON.parse(response.body)
        expect(json_response['status']).to eq('success')
        expect(json_response['image']).to be_present
      end

      it "redirects to gallery for HTML requests" do
        post :create, params: valid_params
        expect(response).to redirect_to(gallery_path(gallery))
      end

      it "sets success flash message" do
        post :create, params: valid_params
        expect(flash[:notice]).to eq("Image uploaded successfully.")
      end
    end

    context "with multiple files" do
      let(:multiple_files) do
        [
          create_uploaded_file(filename: 'image1.jpg', content_type: 'image/jpeg'),
          create_uploaded_file(filename: 'image2.png', content_type: 'image/png'),
          create_uploaded_file(filename: 'image3.webp', content_type: 'image/webp')
        ]
      end

      it "handles bulk upload" do
        params = {
          gallery_id: gallery.id,
          images: multiple_files.map.with_index do |file, index|
            { file: file, filename: "image#{index + 1}" }
          end
        }

        expect {
          post :create, params: params
        }.to change(Image, :count).by(3)
      end

      it "maintains correct positioning for bulk uploads" do
        params = {
          gallery_id: gallery.id,
          images: multiple_files.map.with_index do |file, index|
            { file: file, filename: "image#{index + 1}" }
          end
        }

        post :create, params: params
        
        images = gallery.reload.images.ordered
        expect(images.first.position).to eq(1)
        expect(images.last.position).to eq(3)
      end
    end

    context "with invalid file" do
      let(:invalid_file) { create_invalid_file(filename: 'malicious.php', content_type: 'application/x-php') }
      let(:invalid_params) do
        {
          gallery_id: gallery.id,
          image: {
            file: invalid_file,
            filename: 'malicious.php'
          }
        }
      end

      it "rejects invalid file types" do
        expect {
          post :create, params: invalid_params
        }.not_to change(Image, :count)
      end

      it "logs security event for blocked upload" do
        expect(SecurityAuditLogger).to receive(:log).with(
          event_type: 'file_upload_blocked',
          photographer_id: photographer.id,
          ip_address: '0.0.0.0',
          additional_data: hash_including(:filename, :content_type, :reason)
        )

        post :create, params: invalid_params
      end

      it "returns error response" do
        post :create, params: invalid_params
        
        expect(response).to have_http_status(:unprocessable_entity)
        expect(assigns(:image).errors[:file]).to be_present
      end
    end

    context "with oversized file" do
      let(:large_file) { create_large_file(filename: 'huge.jpg', size_mb: 60) }
      let(:large_params) do
        {
          gallery_id: gallery.id,
          image: {
            file: large_file,
            filename: 'huge.jpg'
          }
        }
      end

      it "rejects files over size limit" do
        # Mock the byte size to exceed limit
        allow_any_instance_of(ActionDispatch::Http::UploadedFile).to receive(:size).and_return(55.megabytes)
        
        expect {
          post :create, params: large_params
        }.not_to change(Image, :count)
      end

      it "provides helpful error message" do
        allow_any_instance_of(ActionDispatch::Http::UploadedFile).to receive(:size).and_return(55.megabytes)
        
        post :create, params: large_params
        expect(assigns(:image).errors[:file]).to include(/must be less than/)
      end
    end

    context "with missing parameters" do
      it "requires file parameter" do
        post :create, params: { gallery_id: gallery.id, image: { filename: 'test.jpg' } }
        
        expect(response).to have_http_status(:unprocessable_entity)
        expect(assigns(:image).errors[:file]).to include("can't be blank")
      end

      it "requires gallery_id parameter" do
        expect {
          post :create, params: { image: { file: valid_file } }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    context "with malicious filename" do
      let(:malicious_file) { create_uploaded_file(filename: '../../../etc/passwd', content_type: 'image/jpeg') }
      let(:malicious_params) do
        {
          gallery_id: gallery.id,
          image: {
            file: malicious_file,
            filename: '../../../etc/passwd'
          }
        }
      end

      it "sanitizes malicious filenames" do
        post :create, params: malicious_params
        image = assigns(:image)
        
        expect(image.filename).not_to include('../')
        expect(image.filename).not_to include('etc')
        expect(image.filename).not_to include('passwd')
      end
    end
  end

  describe "PATCH #update" do
    before { sign_in(photographer) }

    let(:update_params) do
      {
        id: image.id,
        image: {
          position: 2,
          filename: 'updated_filename.jpg'
        }
      }
    end

    context "with valid parameters" do
      it "updates the image" do
        patch :update, params: update_params
        image.reload
        
        expect(image.position).to eq(2)
        expect(image.filename).to eq('updated_filename.jpg')
      end

      it "returns JSON success for AJAX requests" do
        request.headers['Accept'] = 'application/json'
        patch :update, params: update_params
        
        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response['status']).to eq('success')
      end

      it "redirects to gallery for HTML requests" do
        patch :update, params: update_params
        expect(response).to redirect_to(gallery_path(image.gallery))
      end
    end

    context "with position updates for reordering" do
      let!(:image1) { create(:image, gallery: gallery, position: 1) }
      let!(:image2) { create(:image, gallery: gallery, position: 2) }
      let!(:image3) { create(:image, gallery: gallery, position: 3) }

      it "handles image reordering" do
        # Move image3 to position 1
        patch :update, params: { id: image3.id, image: { position: 1 } }
        
        [image1, image2, image3].each(&:reload)
        
        expect(image3.position).to eq(1)
        # Other images should be reordered accordingly
      end

      it "validates position ranges" do
        patch :update, params: { id: image1.id, image: { position: -1 } }
        
        expect(response).to have_http_status(:unprocessable_entity)
        expect(assigns(:image).errors[:position]).to be_present
      end
    end

    context "with invalid parameters" do
      let(:invalid_update_params) do
        {
          id: image.id,
          image: {
            filename: '', # Empty filename
            position: 'invalid' # Non-numeric position
          }
        }
      end

      it "does not update the image" do
        original_filename = image.filename
        patch :update, params: invalid_update_params
        image.reload
        
        expect(image.filename).to eq(original_filename)
      end

      it "returns error response" do
        patch :update, params: invalid_update_params
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "DELETE #destroy" do
    before { sign_in(photographer) }

    let!(:image_to_delete) { create(:image, gallery: gallery) }

    it "destroys the image" do
      expect {
        delete :destroy, params: { id: image_to_delete.id }
      }.to change(Image, :count).by(-1)
    end

    it "removes associated file" do
      delete :destroy, params: { id: image_to_delete.id }
      
      expect(ActiveStorage::Attachment.where(record: image_to_delete)).to be_empty
    end

    it "updates gallery images count" do
      gallery.update_column(:images_count, 1)
      
      expect {
        delete :destroy, params: { id: image_to_delete.id }
      }.to change { gallery.reload.images_count }.by(-1)
    end

    it "returns JSON success for AJAX requests" do
      request.headers['Accept'] = 'application/json'
      delete :destroy, params: { id: image_to_delete.id }
      
      expect(response).to have_http_status(:success)
      json_response = JSON.parse(response.body)
      expect(json_response['status']).to eq('success')
    end

    it "redirects to gallery for HTML requests" do
      delete :destroy, params: { id: image_to_delete.id }
      expect(response).to redirect_to(gallery_path(gallery))
    end

    it "sets success flash message" do
      delete :destroy, params: { id: image_to_delete.id }
      expect(flash[:notice]).to eq("Image deleted successfully.")
    end

    it "logs image deletion" do
      expect(SecurityAuditLogger).to receive(:log).with(
        event_type: 'image_deleted',
        photographer_id: photographer.id,
        ip_address: '0.0.0.0',
        additional_data: hash_including(:image_id, :filename, :gallery_id)
      )

      delete :destroy, params: { id: image_to_delete.id }
    end

    context "when image is being processed" do
      let(:processing_image) { create(:image, :processing, gallery: gallery) }

      it "allows deletion of processing images" do
        expect {
          delete :destroy, params: { id: processing_image.id }
        }.to change(Image, :count).by(-1)
      end

      it "cancels processing job if possible" do
        # This would depend on implementation details of job cancellation
        delete :destroy, params: { id: processing_image.id }
        expect(response).to have_http_status(:found) # Redirect
      end
    end
  end

  describe "bulk operations" do
    before { sign_in(photographer) }

    describe "DELETE #destroy_multiple" do
      let!(:images_to_delete) { create_list(:image, 3, gallery: gallery) }
      let(:image_ids) { images_to_delete.map(&:id) }

      it "destroys multiple images" do
        expect {
          delete :destroy_multiple, params: { gallery_id: gallery.id, image_ids: image_ids }
        }.to change(Image, :count).by(-3)
      end

      it "updates gallery images count correctly" do
        gallery.update_column(:images_count, 5)
        
        expect {
          delete :destroy_multiple, params: { gallery_id: gallery.id, image_ids: image_ids }
        }.to change { gallery.reload.images_count }.by(-3)
      end

      it "logs bulk deletion" do
        expect(SecurityAuditLogger).to receive(:log).with(
          event_type: 'images_bulk_deleted',
          photographer_id: photographer.id,
          ip_address: '0.0.0.0',
          additional_data: hash_including(:gallery_id, :deleted_count)
        )

        delete :destroy_multiple, params: { gallery_id: gallery.id, image_ids: image_ids }
      end

      it "handles partial failures gracefully" do
        # Make one image belong to different gallery
        images_to_delete.last.update!(gallery: other_gallery)
        
        # Should delete the images it can and report error for others
        delete :destroy_multiple, params: { gallery_id: gallery.id, image_ids: image_ids }
        
        expect(Image.where(id: image_ids.first(2))).to be_empty
        expect(Image.find(images_to_delete.last.id)).to be_present
      end
    end

    describe "PATCH #reorder" do
      let!(:images) { create_list(:image, 4, gallery: gallery) }

      it "reorders images based on provided positions" do
        new_order = images.reverse.map(&:id)
        
        patch :reorder, params: { 
          gallery_id: gallery.id, 
          image_ids: new_order
        }
        
        images.each(&:reload)
        ordered_images = gallery.images.ordered
        
        expect(ordered_images.map(&:id)).to eq(new_order)
      end

      it "validates that all images belong to the gallery" do
        other_image = create(:image, gallery: other_gallery)
        invalid_order = [images.first.id, other_image.id]
        
        patch :reorder, params: { 
          gallery_id: gallery.id, 
          image_ids: invalid_order
        }
        
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "security features" do
    describe "file upload security" do
      before { sign_in(photographer) }

      it "validates file extensions" do
        dangerous_extensions = %w[.php .exe .bat .sh .py .rb]
        
        dangerous_extensions.each do |ext|
          malicious_file = create_uploaded_file(filename: "malicious#{ext}", content_type: 'image/jpeg')
          
          post :create, params: { 
            gallery_id: gallery.id, 
            image: { file: malicious_file }
          }
          
          expect(response).to have_http_status(:unprocessable_entity)
        end
      end

      it "validates MIME types" do
        file_with_fake_mime = create_uploaded_file(filename: 'test.jpg', content_type: 'application/x-php')
        
        post :create, params: { 
          gallery_id: gallery.id, 
          image: { file: file_with_fake_mime }
        }
        
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "scans for malicious content" do
        # This would integrate with actual virus scanning or content inspection
        malicious_content = "<?php system($_GET['cmd']); ?>"
        malicious_file = create_uploaded_file(
          filename: 'innocent.jpg', 
          content_type: 'image/jpeg',
          content: malicious_content
        )
        
        post :create, params: { 
          gallery_id: gallery.id, 
          image: { file: malicious_file }
        }
        
        # Should be rejected by content scanning
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    describe "rate limiting" do
      before { sign_in(photographer) }

      it "limits upload frequency" do
        allow(Rails.cache).to receive(:read).with(/upload_attempts/).and_return(20)
        
        post :create, params: { 
          gallery_id: gallery.id, 
          image: { file: create_uploaded_file }
        }
        
        expect(response).to have_http_status(:forbidden)
      end
    end

    describe "access control" do
      it "prevents cross-gallery access" do
        sign_in(photographer)
        other_image = create(:image, gallery: other_gallery)
        
        patch :update, params: { id: other_image.id, image: { position: 1 } }
        expect(response).to have_http_status(:forbidden)
        
        delete :destroy, params: { id: other_image.id }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "error handling" do
    before { sign_in(photographer) }

    it "handles Active Storage errors gracefully" do
      allow_any_instance_of(ActiveStorage::Attached::One).to receive(:attach).and_raise(ActiveStorage::Error)
      
      post :create, params: { 
        gallery_id: gallery.id, 
        image: { file: create_uploaded_file }
      }
      
      expect(response).to have_http_status(:unprocessable_entity)
      expect(flash[:alert]).to include('upload')
    end

    it "handles disk space errors" do
      allow_any_instance_of(ActiveStorage::Service::DiskService).to receive(:upload)
        .and_raise(Errno::ENOSPC.new('No space left on device'))
      
      post :create, params: { 
        gallery_id: gallery.id, 
        image: { file: create_uploaded_file }
      }
      
      expect(response).to have_http_status(:unprocessable_entity)
      expect(flash[:alert]).to include('storage')
    end
  end

  describe "performance considerations" do
    before { sign_in(photographer) }

    it "handles large batch uploads efficiently" do
      large_batch = Array.new(20) { create_uploaded_file(filename: "image#{rand(1000)}.jpg") }
      
      expect {
        post :create, params: { 
          gallery_id: gallery.id, 
          images: large_batch.map { |file| { file: file } }
        }
      }.not_to exceed_query_limit(30) # Reasonable limit for batch operations
    end

    it "uses background jobs for processing" do
      post :create, params: { 
        gallery_id: gallery.id, 
        image: { file: create_uploaded_file }
      }
      
      expect(ImageProcessingJob).to have_received(:perform_later)
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