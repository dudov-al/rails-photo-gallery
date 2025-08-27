class HomeController < ApplicationController
  def index
    if photographer_signed_in?
      redirect_to galleries_path
    else
      # Show landing page for non-authenticated users
      @featured_galleries = Gallery.published.featured.limit(6)
    end
  end
end