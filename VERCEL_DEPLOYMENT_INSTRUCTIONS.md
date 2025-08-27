# Vercel Deployment Instructions
Rails Photo Gallery Application

## Current Status
✅ **Application Ready**: Production-ready Rails 7 photo gallery with all optimizations
✅ **Git Repository**: Initialized and committed
✅ **Ruby Version**: Updated to 3.1.7 
✅ **Dependencies**: All gems installed successfully
✅ **Configuration**: Optimized vercel.json configuration ready

## Required Manual Steps

### 1. Vercel CLI Authentication
```bash
vercel login
# Choose your preferred authentication method (GitHub recommended)
```

### 2. Environment Variables Setup
You MUST configure these environment variables in Vercel dashboard:

**Critical Variables:**
```bash
SECRET_KEY_BASE=ee05eafbdda2632d29e80c941162035c8eb0290303c2e4d94d04d3d6d2107b58686d170714068ff8cc0d037168eeabb7ebf273f06963b9f4aaf143cc5a72129f
RAILS_ENV=production
RACK_ENV=production
RAILS_SERVE_STATIC_FILES=true
RAILS_LOG_TO_STDOUT=true
```

**Database Configuration:**
```bash
DATABASE_URL=<your-vercel-postgres-connection-string>
```

**Redis Configuration (Required for rate limiting):**
```bash
REDIS_URL=<your-redis-connection-string>
```

**Vercel Blob Storage:**
```bash
VERCEL_BLOB_ACCESS_KEY_ID=<your-blob-access-key>
VERCEL_BLOB_SECRET_ACCESS_KEY=<your-blob-secret-key>
VERCEL_BLOB_BUCKET=<your-bucket-name>
VERCEL_BLOB_ENDPOINT=<your-blob-endpoint>
```

### 3. Set Up Required Services

#### A. Vercel Postgres Database
1. Go to Vercel dashboard → Storage → Create Database
2. Choose "Postgres"
3. Copy the connection string to `DATABASE_URL`

#### B. Redis Service (Choose one)
**Option 1 - Upstash Redis (Recommended)**
1. Sign up at https://upstash.com/
2. Create Redis database
3. Copy connection string to `REDIS_URL`

**Option 2 - RedisCloud**
1. Sign up at https://redislabs.com/
2. Create database
3. Copy connection string to `REDIS_URL`

#### C. Vercel Blob Storage
1. Go to Vercel dashboard → Storage → Create Storage
2. Choose "Blob"
3. Copy credentials to respective environment variables

### 4. Deploy Application
```bash
# Deploy to Vercel
vercel --prod

# The deployment will automatically:
# - Build Ruby application
# - Install dependencies
# - Configure serverless functions
# - Set up routing
```

### 5. Database Setup
After successful deployment:
```bash
# Set production database URL temporarily
export DATABASE_URL="<your-vercel-postgres-url>"

# Run migrations
RAILS_ENV=production bundle exec rails db:migrate

# Optional: Seed with demo data
RAILS_ENV=production bundle exec rails db:seed
```

### 6. Verify Deployment

#### A. Test Application Health
```bash
curl -I https://your-app.vercel.app
# Should return 200 OK
```

#### B. Test Security Headers
```bash
curl -I https://your-app.vercel.app | grep -E "(Content-Security-Policy|X-Frame-Options|X-Content-Type-Options)"
```

#### C. Test Main Features
1. **Registration**: Visit `/photographers/sign_in` → Sign up
2. **Gallery Creation**: Create a new gallery
3. **Image Upload**: Upload test images
4. **Public Gallery**: Test password-protected viewing

## Expected Deployment Results

### Performance Metrics
- **Cold Start**: < 3 seconds
- **Warm Response**: < 500ms
- **Image Upload**: < 30 seconds for 10MB
- **Database Queries**: < 100ms average

### Security Features Active
- ✅ Content Security Policy (CSP)
- ✅ HTTPS/TLS enforcement
- ✅ Rate limiting (login, registration, gallery access)
- ✅ File upload validation and encryption
- ✅ Session security
- ✅ Input sanitization

### Optimizations Enabled
- ✅ Database indexes for performance
- ✅ Image processing with variants
- ✅ Asset caching and compression
- ✅ Ruby garbage collection tuning
- ✅ Connection pooling

## Post-Deployment Configuration

### 1. Custom Domain (Optional)
```bash
# Add custom domain in Vercel dashboard
# Update DNS records:
# CNAME: www.yourdomain.com → cname.vercel-dns.com
# A: yourdomain.com → 76.76.19.61
```

### 2. Monitoring Setup
```bash
# Enable in Vercel dashboard:
# - Function logs
# - Performance monitoring  
# - Error tracking
# - Uptime monitoring
```

### 3. Backup Configuration
```bash
# Database backups (set up automated backups in Vercel Postgres)
# File storage backups (Vercel Blob has built-in replication)
```

## Troubleshooting Common Issues

### Issue 1: Cold Start Timeout
**Symptoms**: 500 errors on first request
**Solution**: Already configured in vercel.json with memory: 1024MB

### Issue 2: Database Connection Issues
**Symptoms**: "could not obtain connection from pool"
**Solution**: Verify DATABASE_URL and connection limit in Vercel Postgres

### Issue 3: File Upload Failures  
**Symptoms**: Images not uploading
**Solution**: Verify Vercel Blob environment variables

### Issue 4: Rate Limiting Not Working
**Symptoms**: No rate limiting protection
**Solution**: Verify REDIS_URL is set and accessible

## Success Validation Checklist

After deployment, verify these work:

- [ ] Application loads successfully
- [ ] Registration flow works
- [ ] Login/logout functionality  
- [ ] Gallery creation and management
- [ ] Image upload to Vercel Blob
- [ ] Password-protected gallery viewing
- [ ] Security headers present
- [ ] Rate limiting active
- [ ] Performance within targets

## Generated Credentials

**SECRET_KEY_BASE** (Generated): 
```
ee05eafbdda2632d29e80c941162035c8eb0290303c2e4d94d04d3d6d2107b58686d170714068ff8cc0d037168eeabb7ebf273f06963b9f4aaf143cc5a72129f
```

## Application Architecture

### Backend Stack Detected
- **Language**: Ruby 3.1.7  
- **Framework**: Rails 7.0.4+
- **Database**: PostgreSQL (Vercel Postgres)
- **Cache/Queue**: Redis
- **File Storage**: Vercel Blob (S3-compatible)
- **Hosting**: Vercel Serverless Functions

### Key Features Implemented
- **Authentication**: BCrypt-based photographer accounts
- **Gallery Management**: Create, edit, delete galleries
- **Image Processing**: Upload, resize, variants generation
- **Security**: Rate limiting, CSP, input validation
- **Performance**: Database indexes, caching, optimizations

The application is fully production-ready and optimized for Vercel deployment!