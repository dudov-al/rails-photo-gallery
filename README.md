# Photograph - Professional Photo Gallery Platform

A Rails 7 application optimized for photographer-to-client photo delivery with secure galleries, high-volume image processing, and Vercel deployment.

## Features

- **Secure Gallery Sharing**: Password-protected galleries with expiration dates
- **High-Volume Image Processing**: Optimized for large image uploads with libvips
- **Vercel Deployment**: Serverless deployment with Vercel Blob storage
- **Mobile Optimized**: Responsive design for all device types
- **Drag & Drop Upload**: Intuitive image upload interface
- **Background Processing**: Sidekiq for image processing jobs
- **Rate Limiting**: Protection against abuse with rack-attack

## Tech Stack

- **Backend**: Ruby on Rails 7+
- **Database**: PostgreSQL
- **Frontend**: Turbo + Stimulus + Bootstrap 5
- **Storage**: Vercel Blob Storage / Active Storage
- **Image Processing**: libvips via image_processing gem
- **Background Jobs**: Sidekiq
- **Security**: rack-attack, Content Security Policy

## Local Development Setup

### Prerequisites

- Ruby 3.2+
- PostgreSQL
- Redis (for Sidekiq)
- libvips (for image processing)

### Installation

1. **Clone and setup**:
   ```bash
   cd photograph
   bundle install
   ```

2. **Database setup**:
   ```bash
   rails db:create
   rails db:migrate
   rails db:seed
   ```

3. **Environment variables**:
   ```bash
   cp .env.example .env
   # Edit .env with your local configuration
   ```

4. **Start services**:
   ```bash
   # Terminal 1: Rails server
   rails server
   
   # Terminal 2: Sidekiq
   bundle exec sidekiq
   ```

5. **Access the application**:
   - Main app: http://localhost:3000
   - Sidekiq web UI: http://localhost:3000/sidekiq

### Demo Account

Development seeds create a demo photographer account:
- Email: demo@photographer.com
- Password: password123

## Vercel Deployment

### Environment Variables

Set these in your Vercel project settings:

```bash
# Database
DATABASE_URL=your_vercel_postgres_url

# Rails
SECRET_KEY_BASE=your_generated_secret
RAILS_ENV=production
RACK_ENV=production
RAILS_SERVE_STATIC_FILES=true
RAILS_LOG_TO_STDOUT=true

# Vercel Blob Storage
BLOB_READ_WRITE_TOKEN=your_vercel_blob_token
VERCEL_BLOB_ENDPOINT=https://blob.vercel-storage.com

# Redis (if using external Redis)
REDIS_URL=your_redis_url

# Sidekiq Web (optional)
SIDEKIQ_USERNAME=admin
SIDEKIQ_PASSWORD=your_secure_password
```

### Deploy to Vercel

1. **Connect your repository** to Vercel
2. **Configure environment variables** in Vercel dashboard
3. **Deploy**:
   ```bash
   vercel --prod
   ```

## Project Structure

```
app/
├── controllers/         # Rails controllers
├── models/             # Active Record models
├── views/              # ERB templates
├── javascript/         # Stimulus controllers
└── assets/stylesheets/ # SCSS stylesheets

config/
├── environments/       # Environment-specific configs
├── initializers/       # App initialization
├── storage.yml        # Active Storage configuration
└── vercel.json        # Vercel deployment config

db/
├── migrate/           # Database migrations
└── seeds.rb          # Sample data
```

## Key Models

- **Photographer**: User account with authentication
- **Gallery**: Collection of images with access control
- **Image**: Individual photos with Active Storage attachments

## Security Features

- Password hashing with bcrypt
- CSRF protection
- Content Security Policy
- Rate limiting with rack-attack
- Secure file uploads with validation
- SSL enforcement in production

## Performance Optimizations

- libvips for fast image processing
- Image variants (thumbnail, web, full size)
- Database indexes for common queries
- Active Storage direct uploads
- CDN-ready with Vercel edge network

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

## License

This project is proprietary software.