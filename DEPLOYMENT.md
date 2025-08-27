# Deployment Guide - Photograph Gallery Platform

## Quick Start

1. **Install dependencies**:
   ```bash
   bundle install
   ```

2. **Setup database**:
   ```bash
   rails db:create db:migrate db:seed
   ```

3. **Start the application**:
   ```bash
   # Terminal 1: Rails server
   rails server
   
   # Terminal 2: Sidekiq (for background jobs)
   bundle exec sidekiq
   ```

4. **Access the app**: http://localhost:3000

## Vercel Deployment

### Step 1: Environment Variables

Set these in your Vercel project dashboard:

```bash
# Database (use Vercel Postgres)
DATABASE_URL=postgres://default:password@host:5432/verceldb

# Rails Configuration
SECRET_KEY_BASE=your_generated_secret_key_here
RAILS_ENV=production
RACK_ENV=production
RAILS_SERVE_STATIC_FILES=true
RAILS_LOG_TO_STDOUT=true

# Vercel Blob Storage
BLOB_READ_WRITE_TOKEN=vercel_blob_rw_token_here

# Redis (optional - for Sidekiq)
REDIS_URL=redis://your-redis-provider:6379/0

# Sidekiq Web UI (production)
SIDEKIQ_USERNAME=admin
SIDEKIQ_PASSWORD=secure_password_here
```

### Step 2: Generate Secret Key

```bash
rails secret
```

### Step 3: Deploy to Vercel

```bash
# Install Vercel CLI
npm install -g vercel

# Deploy
vercel --prod
```

### Step 4: Run Database Migrations

After first deployment:

```bash
vercel env pull .env.production
RAILS_ENV=production rails db:migrate
```

## Environment-Specific Notes

### Development
- Uses local PostgreSQL
- Active Storage uses local disk storage
- Sidekiq uses local Redis

### Production (Vercel)
- Uses Vercel Postgres
- Active Storage uses Vercel Blob
- Sidekiq uses external Redis provider

## Troubleshooting

### Common Issues

1. **Database connection errors**:
   - Verify DATABASE_URL format
   - Check PostgreSQL service status

2. **Image upload failures**:
   - Verify Vercel Blob token
   - Check file size limits (50MB max)

3. **Background job issues**:
   - Verify Redis connection
   - Check Sidekiq process status

4. **Asset compilation errors**:
   - Run `rails assets:precompile`
   - Check for missing dependencies

### Vercel-Specific Issues

1. **Cold starts**:
   - Function timeout is 30 seconds
   - Consider warming functions

2. **File storage**:
   - Static files served by Vercel CDN
   - User uploads go to Vercel Blob

3. **Background jobs**:
   - Sidekiq requires external Redis
   - Consider Vercel Edge Functions for simple jobs

## Performance Monitoring

- Monitor cold start times
- Track image processing duration
- Monitor database query performance
- Watch Redis memory usage

## Security Checklist

- [ ] Set strong SECRET_KEY_BASE
- [ ] Enable SSL in production
- [ ] Configure CSP headers
- [ ] Set up rate limiting
- [ ] Secure Sidekiq web interface
- [ ] Validate file uploads
- [ ] Set secure session cookies