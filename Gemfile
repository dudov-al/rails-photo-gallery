source "https://rubygems.org"
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby "3.1.0"

# Core Rails gems
gem "rails", "~> 7.0.4"
gem "pg", "~> 1.1"
gem "puma", "~> 6.0"
gem "sass-rails", ">= 6"
gem "importmap-rails", "~> 1.0"
gem "turbo-rails", "~> 1.3"
gem "stimulus-rails", "~> 1.2"
gem "jbuilder", "~> 2.7"
gem "bootsnap", ">= 1.13.0", require: false

# Photo gallery specific gems
gem "bcrypt", "~> 3.1.7"
gem "image_processing", "~> 1.2"
gem "mini_magick", "~> 4.11"
gem "marcel", "~> 1.0" # MIME type detection

# Background processing
gem "sidekiq", "~> 7.0"

# Security and rate limiting
gem "rack-attack"
gem "redis", "~> 4.0"
gem "connection_pool", "~> 2.2"

# Bootstrap for styling
gem "bootstrap", "~> 5.3"
gem "sassc-rails"

# File storage and cloud services
gem "aws-sdk-s3", require: false

group :development, :test do
  gem "debug", platforms: %i[ mri mingw x64_mingw ]
  gem "rspec-rails"
  gem "factory_bot_rails"
end

group :development do
  gem "web-console"
  gem "listen", "~> 3.3"
  gem "spring"
end

group :production do
  # Heroku/Vercel deployment
  gem "rails_12factor"
end