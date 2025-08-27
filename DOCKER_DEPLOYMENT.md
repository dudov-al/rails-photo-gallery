# Docker Deployment Guide - Photo Gallery

Complete Docker deployment setup for the Rails Photo Gallery application that works "out of the box" on any VDS server.

## What You Get

A complete, production-ready Rails 7 photo gallery platform with:
- 🔐 Photographer authentication and gallery management
- 📸 Image upload with automatic processing
- 🔗 Password-protected public galleries  
- 🛡️ Enterprise-grade security and performance
- 🐳 Containerized deployment with Docker
- 🔄 Background job processing
- 📊 Admin monitoring dashboard

## Quick Start (5 minutes)

### Prerequisites
- VDS server with Docker and Docker Compose installed
- 2GB+ RAM, 20GB+ disk space
- Basic terminal access

### 1. Download and Setup
```bash
# Clone or download the application files to your server
# Navigate to the application directory
cd photograph

# Copy environment template and configure
cp .env.example .env
```

### 2. Generate Secrets
```bash
# Generate a secure secret key (run this command)
openssl rand -hex 64

# Copy the output and paste it in your .env file as SECRET_KEY_BASE
```

### 3. Configure Environment
Edit the `.env` file with your preferences:
```bash
# Required: Update these passwords
DATABASE_PASSWORD=your_secure_database_password
REDIS_PASSWORD=your_secure_redis_password  
SECRET_KEY_BASE=your_generated_secret_from_step_2

# Optional: For custom domain
PHOTOGRAPH_HOST=your-domain.com
PHOTOGRAPH_PROTOCOL=https
FORCE_SSL=true

# Admin access for monitoring
SIDEKIQ_USERNAME=admin
SIDEKIQ_PASSWORD=your_admin_password
```

### 4. Launch Application
```bash
# Start all services
docker-compose up -d

# Check status
docker-compose ps

# View logs
docker-compose logs -f app
```

### 5. Access Your Gallery
- **Main Application**: http://your-server-ip
- **Admin Dashboard**: http://your-server-ip/sidekiq (use SIDEKIQ credentials)

That's it! Your photo gallery is running.

## Services Included

| Service | Purpose | Port | Health Check |
|---------|---------|------|--------------|
| **app** | Rails application | 3000 | /health |
| **sidekiq** | Background jobs | - | process check |
| **db** | PostgreSQL database | 5432 | pg_isready |
| **redis** | Cache & job queue | 6379 | ping |
| **nginx** | Reverse proxy | 80, 443 | /health |

## Data Storage

All data is persisted in Docker volumes:
- `postgres_data` - Database files
- `redis_data` - Redis cache
- `app_storage` - Uploaded photos
- `app_logs` - Application logs
- `nginx_logs` - Web server logs

## File Upload Configuration

The application is configured for local disk storage in production:
- **Storage Location**: `/app/storage` (inside container)
- **Persistent Volume**: `app_storage` (on host)
- **Max Upload Size**: 100MB per file
- **Supported Formats**: JPEG, PNG, GIF, WebP
- **Image Processing**: Automatic thumbnails and variants

## SSL/HTTPS Setup

### For Development/Testing
Application runs on HTTP by default (port 80).

### For Production with Domain
1. **Get SSL Certificate**:
   ```bash
   # Install Certbot
   sudo apt update && sudo apt install -y certbot
   
   # Get certificate
   sudo certbot certonly --standalone -d your-domain.com
   ```

2. **Copy Certificates**:
   ```bash
   # Create SSL directory
   mkdir -p docker/ssl
   
   # Copy certificates
   sudo cp /etc/letsencrypt/live/your-domain.com/fullchain.pem docker/ssl/
   sudo cp /etc/letsencrypt/live/your-domain.com/privkey.pem docker/ssl/
   sudo chmod 644 docker/ssl/*.pem
   ```

3. **Enable HTTPS**:
   Edit `.env`:
   ```
   PHOTOGRAPH_HOST=your-domain.com
   PHOTOGRAPH_PROTOCOL=https
   FORCE_SSL=true
   ```

4. **Update Nginx Config**:
   Uncomment the HTTPS server block in `docker/nginx/default.conf`

5. **Restart**:
   ```bash
   docker-compose down && docker-compose up -d
   ```

## Monitoring & Maintenance

### View Application Logs
```bash
# All services
docker-compose logs -f

# Specific service
docker-compose logs -f app
docker-compose logs -f sidekiq
```

### Access Sidekiq Dashboard
Visit `http://your-domain.com/sidekiq` and login with your `SIDEKIQ_USERNAME` and `SIDEKIQ_PASSWORD`.

Monitor:
- Background job queues
- Failed jobs and retries
- System performance
- Redis statistics

### Database Management
```bash
# Rails console
docker-compose exec app bundle exec rails console

# Database console
docker-compose exec app bundle exec rails db

# Run migrations
docker-compose exec app bundle exec rails db:migrate
```

### Backup Data
```bash
# Database backup
docker-compose exec db pg_dump -U photograph photograph_production > backup_$(date +%Y%m%d).sql

# File storage backup
docker run --rm -v photograph_app_storage:/source -v $(pwd)/backups:/dest busybox tar czf /dest/storage_backup_$(date +%Y%m%d).tar.gz -C /source .
```

### Update Application
```bash
# Pull latest code
git pull

# Rebuild and restart
docker-compose down
docker-compose build --no-cache
docker-compose up -d
```

## Performance Optimization

The application is pre-configured with:
- **Asset Compression**: Gzip enabled for all static files
- **Image Optimization**: VIPS image processor for fast thumbnails
- **Caching**: Redis-backed Rails cache store
- **CDN Ready**: Static files served with far-future expires headers
- **Database Indexing**: Optimized queries with performance indexes

### Scaling for High Traffic
```bash
# Increase Sidekiq workers
docker-compose up -d --scale sidekiq=3

# Increase Rails app instances
docker-compose up -d --scale app=2
```

## Security Features

- 🔒 HTTPS/TLS support with HSTS
- 🛡️ Content Security Policy headers
- 🚫 Rate limiting on authentication endpoints  
- 🔐 Secure password storage with bcrypt
- 📝 Security audit logging
- 🚪 Input sanitization and XSS protection
- 🔑 Session security with secure cookies

## Troubleshooting

### Application Won't Start
```bash
# Check service status
docker-compose ps

# Check specific service logs
docker-compose logs app
docker-compose logs db
```

### Database Connection Issues
```bash
# Verify database is running
docker-compose exec db pg_isready -U photograph

# Check database logs
docker-compose logs db
```

### Image Upload Issues
```bash
# Check storage volume
docker volume inspect photograph_app_storage

# Verify permissions
docker-compose exec app ls -la /app/storage
```

### Performance Issues
```bash
# Check resource usage
docker stats

# Monitor Rails performance
docker-compose logs app | grep "Slow request"
```

## Server Requirements

### Minimum Configuration
- **CPU**: 2 cores
- **RAM**: 2GB
- **Disk**: 20GB SSD
- **Network**: 100 Mbps

### Recommended Configuration
- **CPU**: 4+ cores  
- **RAM**: 4GB+
- **Disk**: 50GB+ SSD
- **Network**: 1 Gbps

## Support

### Common Commands
```bash
# Restart all services
docker-compose restart

# View resource usage
docker system df
docker stats

# Clean up unused resources  
docker system prune

# Reset everything (destructive!)
docker-compose down -v
```

### Environment Variables Reference
See `.env.example` for all available configuration options.

### File Locations
- **Application Code**: `/app`
- **Database Data**: `/var/lib/postgresql/data`
- **Uploaded Images**: `/app/storage`
- **Logs**: `/app/log`, `/var/log/nginx`

This deployment is production-ready and includes all necessary components for a professional photo gallery platform. All data is properly persisted, services are monitored, and the application is secure by default.