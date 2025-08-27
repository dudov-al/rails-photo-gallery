# Production Deployment Guide
Professional Photo Gallery Platform

## Quick Start Checklist

- [ ] Environment variables configured
- [ ] Database setup complete  
- [ ] Redis instance deployed
- [ ] Vercel Blob storage configured
- [ ] SSL certificates active
- [ ] Security headers verified
- [ ] Performance monitoring enabled
- [ ] Backup systems operational

## Pre-Deployment Requirements

### System Requirements
- **Ruby**: 3.1.0+ (specified in Gemfile)
- **Rails**: 7.0.4+
- **PostgreSQL**: 13+ for production database
- **Redis**: 6+ for distributed rate limiting
- **Node.js**: 16+ for asset compilation

### Required Services
- **Vercel Account**: For serverless deployment
- **Vercel Postgres**: Production database
- **Vercel Blob**: Encrypted file storage
- **Redis Provider**: RedisCloud, Upstash, or AWS ElastiCache
- **Domain**: Custom domain with SSL support

## Environment Configuration

### Core Environment Variables

```bash
# Rails Application
SECRET_KEY_BASE=<generate-with-rails-secret>
RAILS_MASTER_KEY=<from-config/master.key>
RAILS_ENV=production
RACK_ENV=production
RAILS_SERVE_STATIC_FILES=true
RAILS_LOG_TO_STDOUT=true

# Database Configuration
DATABASE_URL=postgres://user:password@host:5432/database
DATABASE_POOL=25

# Redis Configuration (Required for rate limiting)
REDIS_URL=redis://user:password@host:6379/0
REDISCLOUD_URL=redis://user:password@host:6379/0

# Vercel Blob Storage (Encrypted)
BLOB_READ_WRITE_TOKEN=<vercel-blob-token>
VERCEL_BLOB_ENDPOINT=https://blob.vercel-storage.com
VERCEL_BLOB_KMS_KEY_ID=<kms-key-for-encryption>

# Security Configuration
ENABLE_IP_BINDING=false
ENABLE_GALLERY_IP_BINDING=false
CSP_REPORT_URI=https://your-domain.com/csp-reports

# Background Jobs (Optional)
SIDEKIQ_USERNAME=admin
SIDEKIQ_PASSWORD=<secure-password>
SIDEKIQ_WEB_URL=/sidekiq

# Performance Optimization
RAILS_MAX_THREADS=10
RUBY_GC_HEAP_INIT_SLOTS=10000
RUBY_GC_HEAP_GROWTH_FACTOR=1.1

# Demo Data (Development only)
DEMO_PHOTOGRAPHER_PASSWORD=<strong-password>
DEMO_GALLERY_PASSWORD=<strong-password>
```

### Generate Required Secrets

```bash
# Generate Rails secret key
rails secret

# Generate Rails master key (if not exists)
rails credentials:edit

# Generate secure passwords
openssl rand -base64 32
```

## Step-by-Step Deployment

### 1. Repository Setup

```bash
# Clone the repository
git clone <your-repo-url>
cd photograph

# Install dependencies
bundle install
npm install -g vercel
```

### 2. Database Setup

**Option A: Vercel Postgres (Recommended)**
```bash
# Create database through Vercel dashboard
# Copy connection string to DATABASE_URL

# Run migrations
RAILS_ENV=production rails db:migrate

# Seed with demo data (optional)
RAILS_ENV=production rails db:seed
```

**Option B: External PostgreSQL**
```bash
# Create database
createdb photograph_production

# Set DATABASE_URL
export DATABASE_URL="postgres://user:password@host:5432/photograph_production"

# Run migrations
RAILS_ENV=production rails db:migrate
```

### 3. Redis Setup

**Option A: RedisCloud (Recommended)**
```bash
# Sign up at redislabs.com
# Get connection URL
# Set REDIS_URL environment variable
```

**Option B: Upstash Redis**
```bash
# Sign up at upstash.com
# Create Redis database
# Copy connection string
```

### 4. Vercel Blob Setup

```bash
# Create blob store in Vercel dashboard
# Enable server-side encryption
# Copy read/write token
# Set BLOB_READ_WRITE_TOKEN
```

### 5. Configure Environment Variables in Vercel

```bash
# Set all environment variables in Vercel dashboard
# Or use Vercel CLI
vercel env add SECRET_KEY_BASE
vercel env add DATABASE_URL
vercel env add REDIS_URL
vercel env add BLOB_READ_WRITE_TOKEN
# ... (add all required variables)
```

### 6. Deploy to Vercel

```bash
# Initial deployment
vercel --prod

# Subsequent deployments
git push origin main
# (Automatic deployment if connected to Git)
```

### 7. Post-Deployment Verification

```bash
# Test application endpoints
curl -I https://your-domain.com
curl -I https://your-domain.com/health

# Verify security headers
curl -I https://your-domain.com | grep -E '(Content-Security-Policy|X-Frame-Options|Strict-Transport-Security)'

# Test database connection
vercel logs --app=your-app

# Test file upload functionality
# Access /photographers/sign_in and create test gallery
```

## Domain and SSL Setup

### Custom Domain Configuration

```bash
# Add domain in Vercel dashboard
# Update DNS records:
# CNAME: www.yourdomain.com -> cname.vercel-dns.com
# A: yourdomain.com -> 76.76.19.61

# Verify SSL certificate
curl -I https://yourdomain.com | grep -i ssl
```

### SSL Best Practices

- **HSTS Enabled**: Strict-Transport-Security header active
- **Certificate Monitoring**: Set up alerts for expiration
- **Perfect Forward Secrecy**: Enabled by default on Vercel
- **TLS 1.3**: Supported for enhanced security

## Performance Configuration

### Vercel Function Optimization

**vercel.json configuration:**
```json
{
  "functions": {
    "config.ru": {
      "memory": 1024,
      "maxDuration": 30
    }
  },
  "env": {
    "RAILS_MAX_THREADS": "10",
    "RUBY_GC_HEAP_INIT_SLOTS": "10000"
  },
  "headers": [
    {
      "source": "/(.*)",
      "headers": [
        {
          "key": "X-Content-Type-Options",
          "value": "nosniff"
        }
      ]
    }
  ]
}
```

### Database Optimization

```bash
# Run performance optimization
RAILS_ENV=production rails performance:optimize_database

# Monitor slow queries
tail -f log/production.log | grep "SLOW QUERY"

# Database statistics
RAILS_ENV=production rails performance:database_stats
```

### Caching Strategy

```bash
# Warm up application cache
RAILS_ENV=production rails performance:warmup

# Monitor cache hit rates
redis-cli info stats | grep keyspace
```

## Security Hardening

### Security Headers Verification

Expected headers in production:
```
Content-Security-Policy: default-src 'self'; img-src 'self' data: https:; style-src 'self' 'unsafe-inline'
X-Frame-Options: DENY
X-Content-Type-Options: nosniff
Strict-Transport-Security: max-age=31536000; includeSubDomains
X-XSS-Protection: 1; mode=block
Permissions-Policy: camera=(), microphone=(), geolocation=()
```

### Rate Limiting Configuration

Configured limits:
- **Login attempts**: 5 per 20 seconds per IP
- **Registration**: 3 per 5 minutes per IP  
- **Gallery access**: 10 password attempts per hour per IP
- **API requests**: 300 per 5 minutes per IP

### File Upload Security

Active protections:
- **Magic number validation**: Verifies actual file type
- **Metadata stripping**: Removes EXIF data
- **Size limits**: 50MB maximum per file
- **Virus scanning**: Content pattern detection
- **Encryption at rest**: Server-side encryption enabled

## Monitoring Setup

### Application Monitoring

```bash
# Enable performance monitoring
export ENABLE_PERFORMANCE_MONITORING=true

# View real-time metrics
RAILS_ENV=production rails performance:monitor

# Generate performance report
RAILS_ENV=production rails performance:report
```

### Health Checks

**Basic health check endpoint:**
```bash
curl https://your-domain.com/health
# Expected: {"status":"ok","database":"connected","redis":"connected"}
```

**Detailed system check:**
```bash
curl https://your-domain.com/system-check
# Returns detailed system status
```

### Log Monitoring

**Key log files to monitor:**
- `vercel-function-logs`: Application logs
- `security_production.log`: Security events
- `performance.log`: Performance metrics

**Critical events to alert on:**
- `failed_login_attempt` with high frequency
- `account_locked` events
- `file_upload_blocked` with virus detection
- `slow_query` with > 1000ms execution time

### Alerting Setup

**Recommended alerts:**
```bash
# High error rate
Error rate > 1% for 5 minutes

# Database connection issues  
Database connection failures

# Memory usage
Memory usage > 80% for 10 minutes

# Response time degradation
95th percentile response time > 5 seconds
```

## Backup and Recovery

### Database Backups

```bash
# Daily automated backup (set up in cron)
pg_dump $DATABASE_URL | gzip > backup-$(date +%Y%m%d).sql.gz

# Upload to secure storage
aws s3 cp backup-$(date +%Y%m%d).sql.gz s3://your-backups/
```

### File Storage Backups

```bash
# Backup Vercel Blob storage
# (Automated through Vercel Blob built-in replication)

# Additional backup to S3 (optional)
vercel blob download --all | aws s3 sync - s3://your-file-backups/
```

### Recovery Procedures

**Database Recovery:**
```bash
# Restore from backup
gunzip < backup-20250827.sql.gz | psql $DATABASE_URL

# Run migrations if needed
RAILS_ENV=production rails db:migrate
```

**Application Recovery:**
```bash
# Rollback to previous deployment
vercel rollback

# Or redeploy from specific commit
vercel --prod --git-commit-sha=<commit-hash>
```

## Scaling Configuration

### Horizontal Scaling

Vercel automatically scales based on:
- **Concurrent requests**: Up to 1000 concurrent executions
- **Geographic distribution**: Edge caching enabled
- **Auto-scaling**: Based on demand patterns

### Database Scaling

```bash
# Monitor connection pool usage
rails db:pool_status

# Upgrade Vercel Postgres plan if needed
# Or migrate to dedicated PostgreSQL instance
```

### Redis Scaling

```bash
# Monitor Redis memory usage
redis-cli info memory

# Scale Redis instance based on:
# - Rate limiting cache size
# - Session storage usage
# - Background job queue size
```

## Maintenance Procedures

### Regular Maintenance Tasks

**Weekly:**
```bash
# Update dependencies
bundle update
npm audit fix

# Run security audit
bundle audit
```

**Monthly:**
```bash
# Performance optimization
RAILS_ENV=production rails performance:optimize

# Database maintenance
RAILS_ENV=production rails db:analyze

# Security log review
grep -E "failed_login|account_locked" log/security_production.log
```

### Update Procedures

**Application Updates:**
```bash
# Test in staging first
vercel --env=staging

# Deploy to production
git push origin main
# (Automatic deployment)

# Verify deployment
curl -I https://your-domain.com
```

**Security Updates:**
```bash
# Critical security patches (immediate)
bundle update --conservative
git commit -m "Security updates"
git push origin main

# Regular updates (scheduled)
bundle update
npm update
```

## Troubleshooting

### Common Issues

**1. Cold Start Timeout**
```bash
# Symptoms: 500 errors on first request
# Solution: Increase memory in vercel.json
{
  "functions": {
    "config.ru": {
      "memory": 1024,
      "maxDuration": 30
    }
  }
}
```

**2. Database Connection Pool Exhaustion**
```bash
# Symptoms: "could not obtain a connection from the pool"
# Solution: Increase DATABASE_POOL or optimize queries
export DATABASE_POOL=50
```

**3. Redis Connection Issues**
```bash
# Symptoms: Rate limiting not working
# Solution: Verify REDIS_URL and connection
redis-cli -u $REDIS_URL ping
```

**4. File Upload Failures**
```bash
# Symptoms: Images not uploading
# Solution: Check Vercel Blob configuration
echo $BLOB_READ_WRITE_TOKEN | head -c 10
```

### Emergency Procedures

**Complete System Failure:**
```bash
# 1. Enable maintenance mode
export MAINTENANCE_MODE=true

# 2. Investigate logs
vercel logs --app=your-app

# 3. Rollback if needed
vercel rollback

# 4. Test critical functionality
curl https://your-domain.com/health
```

## Security Incident Response

### Immediate Response (0-1 hour)

```bash
# 1. Identify affected systems
grep "security_event" log/security_production.log

# 2. Block malicious IPs (if needed)
# Add to rate limiting rules

# 3. Reset compromised sessions
rails db:exec "DELETE FROM sessions WHERE updated_at < NOW() - INTERVAL '1 hour'"

# 4. Enable enhanced monitoring
export LOG_LEVEL=debug
```

### Investigation Phase (1-4 hours)

```bash
# Analyze security logs
grep -E "failed_login|file_upload_blocked|session_hijack" log/security_production.log

# Check for data exfiltration
grep "download" log/production.log | grep -v "200"

# Verify system integrity
RAILS_ENV=production rails security:audit
```

### Recovery Phase (4-24 hours)

```bash
# Update affected passwords
# Force password reset for compromised accounts

# Apply security patches
bundle update --conservative

# Enhance security measures based on incident
```

## Support and Maintenance

### Documentation Updates
- Update this guide with new procedures
- Document any configuration changes
- Maintain runbook for common issues

### Team Access
```bash
# Production access (minimal team)
# - Database: Read-only for developers
# - Vercel: Deploy access for DevOps
# - Monitoring: View access for support

# Emergency access
# - Full admin access for on-call engineer
# - Escalation procedures documented
```

### Contact Information
```bash
# Emergency Contacts
# - Primary: [DevOps Lead]
# - Secondary: [Technical Lead] 
# - Escalation: [CTO/Technical Director]

# Service Providers
# - Vercel Support: [support ticket system]
# - Database Provider: [support contact]
# - Domain/SSL: [registrar support]
```

## Success Criteria

### Deployment Success Indicators

- [ ] Application loads in < 3 seconds
- [ ] All security headers present
- [ ] File uploads working correctly  
- [ ] Database queries executing efficiently
- [ ] Rate limiting active and effective
- [ ] SSL certificate valid and properly configured
- [ ] Monitoring and alerting operational
- [ ] Backup systems verified

### Performance Targets

- **Page Load Time**: < 2 seconds on 3G
- **Database Queries**: < 100ms average
- **Image Upload**: < 30 seconds for 10MB
- **Availability**: 99.9% uptime
- **Error Rate**: < 0.1%

The platform is now production-ready with enterprise-grade deployment, security, and monitoring capabilities.