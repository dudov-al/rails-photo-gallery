# Implementation Plan for Simple Web Gallery

## Overview
Create a Rails 7 application for photographer-to-client photo delivery with galleries, uploads, and downloads based on the technical specification.

## Technology Stack
- **Backend**: Ruby on Rails 7+ (monolithic)
- **Frontend**: Rails Views with Turbo + Stimulus
- **Styling**: Bootstrap 5
- **Database**: PostgreSQL
- **File Storage**: Active Storage with Vercel Blob/local storage
- **Image Processing**: Active Storage variants

## Phase 1: Project Setup & Foundation
### 1.1 Initial Rails Application
- [ ] Generate new Rails 7 application with PostgreSQL
- [ ] Configure `Gemfile` with required gems:
  - `bcrypt` for password hashing
  - `image_processing` for image variants
  - `@vercel/blob` for Vercel Blob storage
  - `rack-attack` for rate limiting
- [ ] Setup Active Storage configuration
- [ ] Configure Vercel Blob storage settings

### 1.2 Frontend Dependencies
- [ ] Install and configure Bootstrap 5
- [ ] Setup Stimulus controllers structure
- [ ] Create application layout with navigation

### 1.3 Database Schema
- [ ] Create migration for `photographers` table
- [ ] Create migration for `galleries` table
- [ ] Create migration for `images` table
- [ ] Add database indexes for performance
- [ ] Run migrations and verify schema

## Phase 2: Authentication System
### 2.1 Photographer Model & Authentication
- [ ] Generate Photographer model with validations
- [ ] Implement `has_secure_password` functionality
- [ ] Add email uniqueness and presence validations
- [ ] Create photographer factory/seeds for development

### 2.2 Session Management
- [ ] Generate SessionsController for login/logout
- [ ] Create login form view (`sessions/new.html.erb`)
- [ ] Implement authentication helpers in ApplicationController
- [ ] Add `current_photographer` and `authenticate_photographer!` methods
- [ ] Create logout functionality

### 2.3 Registration System
- [ ] Add registration routes
- [ ] Create photographer registration form
- [ ] Implement PhotographersController#create
- [ ] Add password confirmation validation

## Phase 3: Gallery Management System
### 3.1 Gallery Model & Business Logic
- [ ] Generate Gallery model with associations
- [ ] Implement slug generation (before_validation callback)
- [ ] Add password protection with `has_secure_password`
- [ ] Add expiration functionality with `expires_at`
- [ ] Create gallery validations and scopes

### 3.2 Gallery CRUD Operations
- [ ] Generate GalleriesController with authentication
- [ ] Implement index action (photographer dashboard)
- [ ] Create gallery creation form with drag-and-drop
- [ ] Add gallery editing functionality
- [ ] Implement gallery deletion with confirmation

### 3.3 Dashboard Interface
- [ ] Create photographer dashboard view (`galleries/index.html.erb`)
- [ ] Display gallery statistics (photo count, created date)
- [ ] Add "Create Gallery" button and modal
- [ ] Implement gallery settings and management links

## Phase 4: Image Upload & Management
### 4.1 Image Model & Active Storage
- [ ] Generate Image model with gallery association
- [ ] Configure Active Storage attachment (`has_one_attached :file`)
- [ ] Add image validations (file type, size limits)
- [ ] Create image ordering system with `position` field
- [ ] Define image variants (thumbnail, web_size)

### 4.2 Image Upload System
- [ ] Generate ImagesController for upload/delete operations
- [ ] Create Stimulus controller for drag-and-drop upload
- [ ] Implement multiple file upload with progress indicators
- [ ] Add image preview functionality
- [ ] Handle upload errors and validation feedback

### 4.3 Image Management Features
- [ ] Implement image deletion functionality
- [ ] Add image reordering with drag-and-drop
- [ ] Create image position management system
- [ ] Add bulk operations (select all, delete multiple)

## Phase 5: Public Gallery Access
### 5.1 Public Gallery Controller
- [ ] Generate PublicGalleriesController
- [ ] Implement gallery show action with slug routing
- [ ] Add password authentication for protected galleries
- [ ] Handle gallery expiration logic
- [ ] Create gallery not found and expired views

### 5.2 Client Gallery Interface
- [ ] Create public gallery view (`public_galleries/show.html.erb`)
- [ ] Implement responsive image grid layout
- [ ] Add image thumbnails with lazy loading
- [ ] Create download buttons for each image
- [ ] Handle password-protected gallery access

### 5.3 Image Viewing & Download
- [ ] Create Stimulus controller for full-screen image viewer
- [ ] Implement navigation between photos (prev/next)
- [ ] Add image zoom functionality
- [ ] Create secure download system with Vercel Blob signed URLs
- [ ] Add download progress indicators

### 5.4 Gallery Password Protection
- [ ] Create password form for protected galleries
- [ ] Implement session-based gallery authentication
- [ ] Add password verification system
- [ ] Handle failed authentication attempts
- [ ] Create Stimulus controller for password form handling

## Phase 6: Security & Performance
### 6.1 File Security
- [ ] Add comprehensive file type validation
- [ ] Implement file size restrictions
- [ ] Setup secure file serving with Vercel Blob signed URLs
- [ ] Add virus scanning (optional)
- [ ] Configure CORS for Vercel Blob if needed

### 6.2 Rate Limiting & Security Headers
- [ ] Configure rack-attack for rate limiting
- [ ] Add CSRF protection (Rails default)
- [ ] Implement security headers
- [ ] Add brute force protection for passwords
- [ ] Setup request logging and monitoring

### 6.3 Performance Optimization
- [ ] Optimize database queries with includes/joins
- [ ] Add database indexes for performance
- [ ] Implement image lazy loading
- [ ] Setup caching for gallery views
- [ ] Optimize image variants and compression

## Phase 7: UI/UX Polish
### 7.1 Responsive Design
- [ ] Ensure mobile-friendly gallery viewing
- [ ] Optimize image grid for different screen sizes
- [ ] Add touch gestures for mobile navigation
- [ ] Implement responsive navigation menu

### 7.2 User Experience Enhancements
- [ ] Add loading states and progress indicators
- [ ] Implement error handling with user-friendly messages
- [ ] Add confirmation dialogs for destructive actions
- [ ] Create helpful tooltips and guidance

### 7.3 Accessibility
- [ ] Add proper ARIA labels and roles
- [ ] Ensure keyboard navigation support
- [ ] Implement screen reader compatibility
- [ ] Add alt text support for images

## Phase 8: Deployment & Production
### 8.1 Production Configuration
- [ ] Setup environment variables for production
- [ ] Configure production database settings
- [ ] Setup Vercel Blob storage
- [ ] Add production-specific security settings

### 8.2 Deployment Setup
- [ ] Create Vercel project
- [ ] Configure Vercel Postgres
- [ ] Setup automatic deployments
- [ ] Add production monitoring and logging

### 8.3 Data Management
- [ ] Create database seeds for development
- [ ] Add data backup and recovery procedures
- [ ] Implement gallery cleanup for expired items
- [ ] Create admin tools for data management

## Phase 9: Testing & Quality Assurance
### 9.1 Test Suite
- [ ] Setup RSpec or Minitest framework
- [ ] Add model tests for all validations and methods
- [ ] Create controller tests for all endpoints
- [ ] Implement integration tests for user flows

### 9.2 Security Testing
- [ ] Test authentication and authorization
- [ ] Verify file upload security
- [ ] Test rate limiting effectiveness
- [ ] Perform basic penetration testing

## Phase 10: Vercel Deployment Specifics
### 10.1 Vercel Configuration
- [ ] Create `vercel.json` configuration file
- [ ] Setup build and start commands for Rails
- [ ] Configure environment variables in Vercel dashboard
- [ ] Setup Vercel Postgres database

### 10.2 Vercel Blob Integration
- [ ] Install and configure Vercel Blob SDK
- [ ] Update Active Storage to use Vercel Blob
- [ ] Test file upload and download functionality
- [ ] Configure signed URLs for secure access

## Key Routes Structure
```ruby
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
get '/g/:slug', to: 'public_galleries#show'
post '/g/:slug/auth', to: 'public_galleries#authenticate'
get '/g/:slug/download/:image_id', to: 'public_galleries#download'
```

## Development Priorities
1. **MVP Focus**: Start with core functionality (auth, galleries, upload, view)
2. **Security First**: Implement authentication and file security early
3. **User Experience**: Prioritize smooth upload and viewing experience
4. **Performance**: Optimize for image handling and large galleries
5. **Mobile Support**: Ensure mobile-friendly from the start
6. **Vercel Optimization**: Leverage Vercel's edge functions and CDN capabilities

## Success Metrics
- [ ] Photographer can create account and login
- [ ] Photographer can create galleries with photos
- [ ] Clients can view galleries and download photos
- [ ] Password protection works correctly
- [ ] File uploads handle various image formats via Vercel Blob
- [ ] Mobile experience is functional
- [ ] Application is secure and performant on Vercel
- [ ] Vercel Blob integration works seamlessly
- [ ] Deployment pipeline is automated