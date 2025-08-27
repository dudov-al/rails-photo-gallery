Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Root route
  root 'home#index'
  
  # Authentication routes
  get '/login', to: 'sessions#new'
  post '/login', to: 'sessions#create'
  delete '/logout', to: 'sessions#destroy'
  get '/register', to: 'photographers#new'
  post '/register', to: 'photographers#create'
  
  # Photographer profile routes (require authentication)
  resources :photographers, only: [:show, :edit, :update]
  
  # Photographer dashboard routes (require authentication)
  resources :galleries, except: [:show] do
    resources :images, only: [:create, :destroy] do
      collection do
        patch :reorder
      end
    end
    member do
      patch :reorder_images
      post :duplicate
    end
  end
  
  # Public gallery routes (no authentication required)
  get '/g/:slug', to: 'public_galleries#show', as: :public_gallery
  post '/g/:slug/auth', to: 'public_galleries#authenticate', as: :authenticate_gallery
  get '/g/:slug/download/:image_id', to: 'public_galleries#download', as: :download_image
  get '/g/:slug/download_all', to: 'public_galleries#download_all', as: :download_all_images
  
  # Health check for Vercel
  get '/health', to: proc { [200, {}, ['OK']] }
  
  # CSP violation reporting
  post '/csp_reports', to: 'csp_reports#create'
  
  # Sidekiq web interface (development only)
  if Rails.env.development?
    require 'sidekiq/web'
    mount Sidekiq::Web => '/sidekiq'
  end
end