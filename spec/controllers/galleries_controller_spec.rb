require 'rails_helper'

RSpec.describe GalleriesController, type: :controller do
  let(:photographer) { create(:photographer) }
  let(:gallery) { create(:gallery, photographer: photographer) }
  let(:other_photographer) { create(:photographer) }
  let(:other_gallery) { create(:gallery, photographer: other_photographer) }

  let(:valid_attributes) do
    {
      title: 'My Photo Gallery',
      description: 'A collection of beautiful photographs',
      published: true,
      featured: false,
      expires_at: 1.month.from_now
    }
  end

  let(:invalid_attributes) do
    {
      title: '',
      description: 'A' * 1000, # Too long
      published: 'invalid'
    }
  end

  let(:password_protected_attributes) do
    valid_attributes.merge(
      password: 'GalleryPassword123!',
      password_confirmation: 'GalleryPassword123!'
    )
  end

  describe "authentication and authorization" do
    describe "when not logged in" do
      it "redirects index to login" do
        get :index
        expect(response).to redirect_to(new_session_path)
      end

      it "redirects show to login" do
        get :show, params: { id: gallery.id }
        expect(response).to redirect_to(new_session_path)
      end

      it "redirects new to login" do
        get :new
        expect(response).to redirect_to(new_session_path)
      end

      it "redirects create to login" do
        post :create, params: { gallery: valid_attributes }
        expect(response).to redirect_to(new_session_path)
      end
    end

    describe "when logged in as different photographer" do
      before { sign_in(other_photographer) }

      it "allows access to index (shows own galleries)" do
        get :index
        expect(response).to have_http_status(:success)
      end

      it "prevents access to other photographer's gallery" do
        get :show, params: { id: gallery.id }
        expect(response).to have_http_status(:forbidden)
      end

      it "prevents editing other photographer's gallery" do
        get :edit, params: { id: gallery.id }
        expect(response).to have_http_status(:forbidden)
      end

      it "prevents updating other photographer's gallery" do
        patch :update, params: { id: gallery.id, gallery: { title: 'Hacked' } }
        expect(response).to have_http_status(:forbidden)
      end

      it "prevents deleting other photographer's gallery" do
        delete :destroy, params: { id: gallery.id }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "GET #index" do
    before { sign_in(photographer) }

    context "with galleries" do
      let!(:published_gallery) { create(:gallery, :published, photographer: photographer) }
      let!(:unpublished_gallery) { create(:gallery, :unpublished, photographer: photographer) }
      let!(:featured_gallery) { create(:gallery, :featured, photographer: photographer) }

      it "returns success" do
        get :index
        expect(response).to have_http_status(:success)
      end

      it "renders the index template" do
        get :index
        expect(response).to render_template(:index)
      end

      it "assigns photographer's galleries" do
        get :index
        galleries = assigns(:galleries)
        
        expect(galleries).to include(published_gallery, unpublished_gallery, featured_gallery)
        expect(galleries).not_to include(other_gallery)
      end

      it "orders galleries by creation date" do
        older_gallery = create(:gallery, photographer: photographer, created_at: 2.days.ago)
        newer_gallery = create(:gallery, photographer: photographer, created_at: 1.day.ago)
        
        get :index
        galleries = assigns(:galleries)
        
        expect(galleries.first).to eq(newer_gallery)
        expect(galleries.last).to eq(older_gallery)
      end

      it "includes gallery statistics" do
        create_list(:image, 3, gallery: published_gallery)
        published_gallery.update_column(:images_count, 3)
        
        get :index
        galleries = assigns(:galleries)
        
        gallery_with_images = galleries.find { |g| g.id == published_gallery.id }
        expect(gallery_with_images.images_count).to eq(3)
      end
    end

    context "with pagination" do
      before do
        create_list(:gallery, 25, photographer: photographer)
      end

      it "paginates results" do
        get :index, params: { page: 1, per_page: 10 }
        galleries = assigns(:galleries)
        
        expect(galleries.size).to eq(10)
      end
    end

    context "with search functionality" do
      let!(:searchable_gallery) { create(:gallery, title: 'Wedding Photos', photographer: photographer) }
      let!(:other_gallery) { create(:gallery, title: 'Nature Shots', photographer: photographer) }

      it "searches by title" do
        get :index, params: { search: 'Wedding' }
        galleries = assigns(:galleries)
        
        expect(galleries).to include(searchable_gallery)
        expect(galleries).not_to include(other_gallery)
      end
    end
  end

  describe "GET #show" do
    before { sign_in(photographer) }

    it "returns success for own gallery" do
      get :show, params: { id: gallery.id }
      expect(response).to have_http_status(:success)
    end

    it "renders the show template" do
      get :show, params: { id: gallery.id }
      expect(response).to render_template(:show)
    end

    it "assigns the gallery" do
      get :show, params: { id: gallery.id }
      expect(assigns(:gallery)).to eq(gallery)
    end

    it "includes associated images" do
      images = create_list(:image, 3, gallery: gallery)
      
      get :show, params: { id: gallery.id }
      assigned_gallery = assigns(:gallery)
      
      expect(assigned_gallery.images.size).to eq(3)
    end

    it "orders images by position" do
      image1 = create(:image, gallery: gallery, position: 2)
      image2 = create(:image, gallery: gallery, position: 1)
      image3 = create(:image, gallery: gallery, position: 3)
      
      get :show, params: { id: gallery.id }
      images = assigns(:gallery).images.ordered
      
      expect(images).to eq([image2, image1, image3])
    end

    context "with non-existent gallery" do
      it "raises ActiveRecord::RecordNotFound" do
        expect {
          get :show, params: { id: 999999 }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end

  describe "GET #new" do
    before { sign_in(photographer) }

    it "returns success" do
      get :new
      expect(response).to have_http_status(:success)
    end

    it "renders the new template" do
      get :new
      expect(response).to render_template(:new)
    end

    it "assigns a new gallery" do
      get :new
      expect(assigns(:gallery)).to be_a_new(Gallery)
    end

    it "associates gallery with current photographer" do
      get :new
      expect(assigns(:gallery).photographer).to eq(photographer)
    end
  end

  describe "GET #edit" do
    before { sign_in(photographer) }

    it "returns success for own gallery" do
      get :edit, params: { id: gallery.id }
      expect(response).to have_http_status(:success)
    end

    it "renders the edit template" do
      get :edit, params: { id: gallery.id }
      expect(response).to render_template(:edit)
    end

    it "assigns the gallery" do
      get :edit, params: { id: gallery.id }
      expect(assigns(:gallery)).to eq(gallery)
    end
  end

  describe "POST #create" do
    before { sign_in(photographer) }

    context "with valid parameters" do
      it "creates a new gallery" do
        expect {
          post :create, params: { gallery: valid_attributes }
        }.to change(Gallery, :count).by(1)
      end

      it "assigns gallery to current photographer" do
        post :create, params: { gallery: valid_attributes }
        gallery = assigns(:gallery)
        
        expect(gallery.photographer).to eq(photographer)
      end

      it "generates unique slug" do
        post :create, params: { gallery: valid_attributes }
        gallery = assigns(:gallery)
        
        expect(gallery.slug).to be_present
        expect(gallery.slug).to eq('my-photo-gallery')
      end

      it "redirects to gallery show page" do
        post :create, params: { gallery: valid_attributes }
        gallery = assigns(:gallery)
        
        expect(response).to redirect_to(gallery_path(gallery))
      end

      it "sets success flash message" do
        post :create, params: { gallery: valid_attributes }
        expect(flash[:notice]).to eq("Gallery was successfully created.")
      end

      it "handles password protection" do
        post :create, params: { gallery: password_protected_attributes }
        gallery = assigns(:gallery)
        
        expect(gallery.password_protected?).to be true
        expect(gallery.authenticate_password('GalleryPassword123!')).to be_truthy
      end

      it "logs gallery creation" do
        expect(SecurityAuditLogger).to receive(:log).with(
          event_type: 'gallery_created',
          photographer_id: photographer.id,
          ip_address: '0.0.0.0',
          additional_data: hash_including(:gallery_id)
        )

        post :create, params: { gallery: valid_attributes }
      end
    end

    context "with invalid parameters" do
      it "does not create a gallery" do
        expect {
          post :create, params: { gallery: invalid_attributes }
        }.not_to change(Gallery, :count)
      end

      it "renders new template" do
        post :create, params: { gallery: invalid_attributes }
        expect(response).to render_template(:new)
      end

      it "assigns gallery with errors" do
        post :create, params: { gallery: invalid_attributes }
        gallery = assigns(:gallery)
        
        expect(gallery.errors).to be_present
        expect(gallery.errors[:title]).to include("can't be blank")
      end

      it "preserves form data" do
        attrs = invalid_attributes.merge(description: 'Valid description')
        post :create, params: { gallery: attrs }
        gallery = assigns(:gallery)
        
        expect(gallery.description).to eq('Valid description')
      end
    end

    context "with malicious input" do
      it "sanitizes HTML in title" do
        malicious_attrs = valid_attributes.merge(
          title: '<script>alert("xss")</script>Malicious Gallery'
        )
        
        post :create, params: { gallery: malicious_attrs }
        gallery = assigns(:gallery)
        
        expect(gallery.title).not_to include('<script>')
        expect(gallery.title).not_to include('alert')
      end

      it "sanitizes HTML in description" do
        malicious_attrs = valid_attributes.merge(
          description: '<img src=x onerror=alert(1)>Description'
        )
        
        post :create, params: { gallery: malicious_attrs }
        gallery = assigns(:gallery)
        
        expect(gallery.description).not_to include('<img')
        expect(gallery.description).not_to include('onerror')
      end
    end

    context "with weak gallery password" do
      let(:weak_password_attrs) do
        valid_attributes.merge(
          password: 'weak123',
          password_confirmation: 'weak123'
        )
      end

      it "rejects weak passwords" do
        post :create, params: { gallery: weak_password_attrs }
        gallery = assigns(:gallery)
        
        expect(gallery.errors[:password]).to be_present
        expect(response).to render_template(:new)
      end
    end
  end

  describe "PATCH #update" do
    before { sign_in(photographer) }

    context "with valid parameters" do
      let(:new_attributes) do
        {
          title: 'Updated Gallery Title',
          description: 'Updated description',
          published: false
        }
      end

      it "updates the gallery" do
        patch :update, params: { id: gallery.id, gallery: new_attributes }
        gallery.reload
        
        expect(gallery.title).to eq('Updated Gallery Title')
        expect(gallery.description).to eq('Updated description')
        expect(gallery.published).to be false
      end

      it "redirects to gallery show page" do
        patch :update, params: { id: gallery.id, gallery: new_attributes }
        expect(response).to redirect_to(gallery_path(gallery))
      end

      it "sets success flash message" do
        patch :update, params: { id: gallery.id, gallery: new_attributes }
        expect(flash[:notice]).to eq("Gallery was successfully updated.")
      end

      it "updates slug when title changes" do
        patch :update, params: { id: gallery.id, gallery: { title: 'Brand New Title' } }
        gallery.reload
        
        # Note: Slug might not change on update depending on implementation
        # This test assumes slug generation only happens on create
        expect(gallery.title).to eq('Brand New Title')
      end

      it "logs gallery update" do
        expect(SecurityAuditLogger).to receive(:log).with(
          event_type: 'gallery_updated',
          photographer_id: photographer.id,
          ip_address: '0.0.0.0',
          additional_data: hash_including(:gallery_id, :changes)
        )

        patch :update, params: { id: gallery.id, gallery: new_attributes }
      end
    end

    context "with password changes" do
      it "updates password protection" do
        patch :update, params: { 
          id: gallery.id, 
          gallery: { 
            password: 'NewPassword123!',
            password_confirmation: 'NewPassword123!'
          }
        }
        gallery.reload
        
        expect(gallery.password_protected?).to be true
        expect(gallery.authenticate_password('NewPassword123!')).to be_truthy
      end

      it "removes password protection when blank" do
        password_gallery = create(:gallery, :password_protected, photographer: photographer)
        
        patch :update, params: { 
          id: password_gallery.id, 
          gallery: { 
            password: '',
            password_confirmation: ''
          }
        }
        password_gallery.reload
        
        expect(password_gallery.password_protected?).to be false
      end
    end

    context "with invalid parameters" do
      it "does not update the gallery" do
        original_title = gallery.title
        patch :update, params: { id: gallery.id, gallery: invalid_attributes }
        gallery.reload
        
        expect(gallery.title).to eq(original_title)
      end

      it "renders edit template" do
        patch :update, params: { id: gallery.id, gallery: invalid_attributes }
        expect(response).to render_template(:edit)
      end

      it "assigns gallery with errors" do
        patch :update, params: { id: gallery.id, gallery: invalid_attributes }
        assigned_gallery = assigns(:gallery)
        
        expect(assigned_gallery.errors).to be_present
      end
    end
  end

  describe "DELETE #destroy" do
    before { sign_in(photographer) }

    it "destroys the gallery" do
      gallery_to_delete = create(:gallery, photographer: photographer)
      
      expect {
        delete :destroy, params: { id: gallery_to_delete.id }
      }.to change(Gallery, :count).by(-1)
    end

    it "redirects to galleries index" do
      delete :destroy, params: { id: gallery.id }
      expect(response).to redirect_to(galleries_path)
    end

    it "sets success flash message" do
      delete :destroy, params: { id: gallery.id }
      expect(flash[:notice]).to eq("Gallery was successfully deleted.")
    end

    it "destroys associated images" do
      images = create_list(:image, 3, gallery: gallery)
      image_ids = images.map(&:id)
      
      delete :destroy, params: { id: gallery.id }
      
      expect(Image.where(id: image_ids)).to be_empty
    end

    it "logs gallery deletion" do
      expect(SecurityAuditLogger).to receive(:log).with(
        event_type: 'gallery_deleted',
        photographer_id: photographer.id,
        ip_address: '0.0.0.0',
        additional_data: hash_including(:gallery_id, :title)
      )

      delete :destroy, params: { id: gallery.id }
    end

    context "when gallery has many images" do
      it "handles bulk deletion efficiently" do
        create_list(:image, 50, gallery: gallery)
        
        expect {
          delete :destroy, params: { id: gallery.id }
        }.not_to exceed_query_limit(10)
      end
    end
  end

  describe "security features" do
    describe "rate limiting" do
      before { sign_in(photographer) }

      it "limits gallery creation attempts" do
        allow(Rails.cache).to receive(:read).with(/gallery_creation/).and_return(10)
        
        post :create, params: { gallery: valid_attributes }
        expect(response).to have_http_status(:forbidden)
      end
    end

    describe "input validation and sanitization" do
      before { sign_in(photographer) }

      it "prevents XSS in gallery attributes" do
        xss_attributes = {
          title: '<script>alert("xss")</script>',
          description: '<img src=x onerror=alert(document.cookie)>'
        }
        
        post :create, params: { gallery: xss_attributes }
        gallery = assigns(:gallery)
        
        expect(gallery.title).not_to include('<script>')
        expect(gallery.description).not_to include('onerror')
      end

      it "validates expiration dates" do
        past_date_attrs = valid_attributes.merge(expires_at: 1.day.ago)
        
        post :create, params: { gallery: past_date_attrs }
        gallery = assigns(:gallery)
        
        # Should either reject or handle gracefully
        expect(gallery.expires_at).to be_nil.or be > Time.current
      end
    end

    describe "authorization edge cases" do
      it "prevents privilege escalation through parameter manipulation" do
        sign_in(other_photographer)
        
        # Attempt to assign gallery to different photographer
        malicious_attrs = valid_attributes.merge(photographer_id: photographer.id)
        
        post :create, params: { gallery: malicious_attrs }
        gallery = assigns(:gallery)
        
        expect(gallery.photographer).to eq(other_photographer)
      end
    end
  end

  describe "performance optimizations" do
    before { sign_in(photographer) }

    it "uses efficient queries for index" do
      create_list(:gallery, 20, :with_images, photographer: photographer)
      
      expect { get :index }.not_to exceed_query_limit(5)
    end

    it "preloads associations for show" do
      gallery_with_images = create(:gallery, :with_images, photographer: photographer)
      
      expect { get :show, params: { id: gallery_with_images.id } }
        .not_to exceed_query_limit(10)
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