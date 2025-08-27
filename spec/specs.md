# Technical Specification: Simple Web Gallery for Photographers

## 1. Product Overview

**Goal:** Create a maximally simple web service for transferring photos from photographer to client through online galleries.

**Key Features:**
- Create galleries with photos
- Upload and view images
- Download photos by clients
- Basic access management

## 2. System Architecture

### 2.1 Overall Architecture
```
[Frontend] ↔ [Rails API] ↔ [PostgreSQL]
                ↕
        [File Storage (Vercel Blob)]
```

### 2.2 Recommended Technology Stack

**Backend:**
- Ruby on Rails 7+ (monolithic application)
- Active Storage for files
- Stimulus for simple interactivity

**Frontend:**
- Rails Views with Turbo (no separate SPA)
- Bootstrap 5 for styling
- Stimulus for JavaScript interactions

**Database:**
- PostgreSQL (main DB)

**File Storage:**
- Vercel Blob Storage or local storage for development

## 3. Database Structure

### 3.1 Main Tables

**photographers**
- id (primary key)
- email (unique, not null)
- password_digest (not null)
- name (not null)
- created_at, updated_at

**galleries**
- id (primary key)
- photographer_id (foreign key, not null)
- title (not null)
- slug (unique, not null) - for public URLs
- password_digest (nullable) - for protected galleries
- expires_at (nullable) - auto-deletion
- created_at, updated_at

**images**
- id (primary key)
- gallery_id (foreign key, not null)
- filename (not null)
- position (integer, default: 0) - display order
- created_at, updated_at

### 3.2 Indexes
```sql
CREATE INDEX index_galleries_on_photographer_id ON galleries(photographer_id);
CREATE INDEX index_galleries_on_slug ON galleries(slug);
CREATE INDEX index_images_on_gallery_id ON images(gallery_id);
CREATE INDEX index_images_on_position ON images(gallery_id, position);
```

## 4. Backend Routes and Controllers

### 4.1 Photographer Routes (require authentication)
```ruby
# config/routes.rb
Rails.application.routes.draw do
  root 'home#index'
  
  # Authentication
  get '/login', to: 'sessions#new'
  post '/login', to: 'sessions#create'
  delete '/logout', to: 'sessions#destroy'
  get '/register', to: 'photographers#new'
  post '/register', to: 'photographers#create'
  
  # Photographer dashboard
  resources :galleries, except: [:show] do
    resources :images, only: [:create, :destroy]
    member do
      patch :reorder_images
    end
  end
  
  # Public galleries
  get '/g/:slug', to: 'public_galleries#show', as: :public_gallery
  post '/g/:slug/auth', to: 'public_galleries#authenticate'
  get '/g/:slug/download/:image_id', to: 'public_galleries#download'
end
```

### 4.2 Main Controllers

**ApplicationController**
- Basic authentication methods
- Photographer authorization checks

**GalleriesController**
- CRUD operations for photographer's galleries
- Access settings management

**ImagesController** 
- Upload images to gallery
- Delete images
- Change order

**PublicGalleriesController**
- Display public gallery
- Password authentication (if set)
- Download images

## 5. Data Models

### 5.1 Photographer Model
```ruby
class Photographer < ApplicationRecord
  has_secure_password
  has_many :galleries, dependent: :destroy
  
  validates :email, presence: true, uniqueness: true
  validates :name, presence: true
end
```

### 5.2 Gallery Model
```ruby
class Gallery < ApplicationRecord
  belongs_to :photographer
  has_many :images, dependent: :destroy
  has_many_attached :image_files
  
  validates :title, presence: true
  validates :slug, presence: true, uniqueness: true
  
  before_validation :generate_slug, on: :create
  
  def password_protected?
    password_digest.present?
  end
  
  def expired?
    expires_at.present? && expires_at < Time.current
  end
end
```

### 5.3 Image Model
```ruby
class Image < ApplicationRecord
  belongs_to :gallery
  has_one_attached :file
  
  validates :filename, presence: true
  validates :file, presence: true
  
  scope :ordered, -> { order(:position, :created_at) }
end
```

## 6. Frontend Pages and Components

### 6.1 Photographer Pages

**Home Page** (`home/index.html.erb`)
- Simple landing page with login/register buttons

**Dashboard** (`galleries/index.html.erb`)
- List of all photographer's galleries
- Create new gallery button
- Basic gallery statistics

**Gallery Creation/Editing** (`galleries/new.html.erb`, `galleries/edit.html.erb`)
- Form with title, password, expiration date
- Drag & drop image upload
- Preview of uploaded photos

### 6.2 Public Pages

**Client Gallery** (`public_galleries/show.html.erb`)
- Image grid with zoom capability
- Download buttons for each photo
- Password input form (if gallery is protected)

### 6.3 Stimulus Controllers

**image-upload-controller.js**
- Drag & drop functionality
- Upload progress display
- Image preview

**gallery-viewer-controller.js**
- Full-screen image viewing
- Navigation between photos
- Image downloading

**password-form-controller.js**
- Password form handling for protected galleries

## 7. Image Processing

### 7.1 Simple Processing via Active Storage

**Image Variants:**
```ruby
# In Image model
def thumbnail
  file.variant(resize_to_limit: [300, 300])
end

def web_size
  file.variant(resize_to_limit: [1200, 1200])
end
```

**Supported Formats:**
- JPEG, PNG (main formats)
- Automatic thumbnail generation

## 8. Security

### 8.1 Authentication
- Rails built-in `has_secure_password`
- Session-based authentication
- CSRF protection (Rails default)

### 8.2 Gallery Access
- Unique slug for each gallery
- Optional password protection
- Rate limiting via rack-attack gem

### 8.3 File Security
- File type validation via Active Storage
- File size limitations
- Signed URLs for downloads

## 9. User Interface

### 9.1 Photographer Dashboard
```
┌─────────────────────────────────────┐
│ My Galleries                   + Create │
├─────────────────────────────────────┤
│ □ Wedding John & Mary           ⚙️ 📊  │
│   25 photos • Created 2 days ago    │
│                                     │
│ □ Kids Photoshoot              ⚙️ 📊  │
│   15 photos • Created a week ago    │
└─────────────────────────────────────┘
```

### 9.2 Client Gallery
```
┌─────────────────────────────────────┐
│          Wedding John & Mary           │
├─────────────────────────────────────┤
│ [photo] [photo] [photo] [photo]     │
│   ⬇️       ⬇️       ⬇️       ⬇️       │
│                                     │
│ [photo] [photo] [photo] [photo]     │
│   ⬇️       ⬇️       ⬇️       ⬇️       │
└─────────────────────────────────────┘
```

## 10. Deployment

### 10.1 Simple Deployment
- **Vercel** for hosting
- Vercel Postgres for database
- Vercel Blob Storage for files

### 10.2 ENV Variables
```
DATABASE_URL=postgresql://...
BLOB_READ_WRITE_TOKEN=...
SECRET_KEY_BASE=...
RAILS_ENV=production
```

## 11. Core Functionality

**Essential Features:**
- Photographer registration/login
- Gallery creation
- Image upload
- Public gallery viewing
- Image downloading
- Password protection
