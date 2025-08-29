# Docker Deployment Guide - Photography Gallery

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Prerequisites](#prerequisites)
4. [Environment Setup](#environment-setup)
5. [SSL/TLS Configuration](#ssltls-configuration)
6. [Deployment](#deployment)
7. [Monitoring and Maintenance](#monitoring-and-maintenance)
8. [Troubleshooting](#troubleshooting)
9. [Security Considerations](#security-considerations)
10. [Performance Optimization](#performance-optimization)

## Overview

This guide provides comprehensive instructions for deploying the Photography Gallery application using Docker in a production environment. The deployment is optimized for VPS servers with emphasis on security, performance, and maintainability.

### Key Features

- **Production-Ready**: Multi-stage Docker builds with security hardening
- **SSL/TLS Support**: Automated Let's Encrypt certificate management
- **High Availability**: Health checks, auto-restart, and monitoring
- **Security**: Network isolation, non-root containers, resource limits
- **Performance**: Optimized for Rails 7.1+ with advanced caching
- **Monitoring**: Comprehensive logging and system monitoring
- **Backup**: Automated database and storage backups

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Nginx Proxy   │    │  Rails App      │    │  Sidekiq Jobs   │
│  (Load Balancer)│ -> │  (Web Server)   │ -> │  (Background)   │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         |                       |                       |
         v                       v                       v
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   PostgreSQL    │    │     Redis       │    │   File Storage  │
│   (Database)    │    │    (Cache)      │    │   (Volumes)     │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

### Network Architecture

- **Frontend Network**: Nginx ↔ Rails App (public access)
- **Backend Network**: Rails App ↔ Database/Redis (private)
- **Monitoring Network**: Prometheus/metrics (isolated)

## Prerequisites

### System Requirements

**Minimum Requirements:**
- **CPU**: 2 cores
- **RAM**: 4GB
- **Storage**: 20GB SSD
- **OS**: Ubuntu 20.04+ / Debian 11+ / CentOS 8+

**Recommended for Production:**
- **CPU**: 4+ cores
- **RAM**: 8GB+
- **Storage**: 50GB+ SSD
- **OS**: Ubuntu 22.04 LTS

### Software Dependencies

```bash
# Install Docker and Docker Compose
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/download/v2.20.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
```

### Domain and DNS Setup

1. Point your domain to your server's IP address
2. Ensure ports 80 and 443 are open in your firewall
3. Wait for DNS propagation (use `dig your-domain.com` to verify)

## Environment Setup

### 1. Clone Repository

```bash
git clone https://github.com/your-username/photograph.git
cd photograph
```

### 2. Environment Configuration

```bash
# Copy environment template
cp .env.example .env

# Edit environment file
nano .env
```

### Required Environment Variables

```bash
# Application Settings
PHOTOGRAPH_HOST=your-domain.com
PHOTOGRAPH_PROTOCOL=https
ADMIN_EMAIL=admin@your-domain.com

# Security (Generate strong passwords!)
SECRET_KEY_BASE=$(openssl rand -hex 64)
DATABASE_PASSWORD=$(openssl rand -base64 32)
REDIS_PASSWORD=$(openssl rand -base64 32)
SIDEKIQ_PASSWORD=$(openssl rand -base64 32)

# Performance Tuning
RAILS_MAX_THREADS=10
WEB_CONCURRENCY=2
SIDEKIQ_CONCURRENCY=10

# Storage Paths
DATA_PATH=/var/lib/photograph
BACKUP_PATH=/var/backups/photograph
LOG_PATH=/var/log/photograph
```

### 3. Create Directory Structure

```bash
# Create data directories
sudo mkdir -p /var/lib/photograph/{postgres,redis,storage}
sudo mkdir -p /var/backups/photograph
sudo mkdir -p /var/log/photograph

# Set permissions
sudo chown -R 1001:1001 /var/lib/photograph
sudo chown -R 1001:1001 /var/log/photograph
sudo chmod 755 /var/backups/photograph
```

## SSL/TLS Configuration

### Automated SSL Setup (Recommended)

```bash
# Make SSL setup script executable
chmod +x docker/ssl-setup.sh

# Run SSL setup (requires sudo for Let's Encrypt)
sudo ./docker/ssl-setup.sh
```

### Manual SSL Setup

```bash
# For self-signed certificates (development only)
sudo ./docker/ssl-setup.sh --self-signed

# For existing certificates
sudo cp your-cert.pem docker/ssl/fullchain.pem
sudo cp your-key.pem docker/ssl/privkey.pem
sudo cp your-chain.pem docker/ssl/chain.pem
```

### SSL Security Configuration

The SSL setup includes:
- **Modern TLS**: TLS 1.2+ with secure cipher suites
- **HSTS**: HTTP Strict Transport Security
- **Perfect Forward Secrecy**: DHE/ECDHE key exchange
- **OCSP Stapling**: Certificate revocation checking
- **Security Headers**: XSS, CSRF, and clickjacking protection

## Deployment

### Development Deployment

```bash
# Start development environment
docker-compose up -d

# View logs
docker-compose logs -f app

# Access application
open http://localhost:3000
```

### Production Deployment

```bash
# Make deployment script executable
chmod +x docker/deploy.sh

# Run production deployment
./docker/deploy.sh

# Check deployment status
./docker/deploy.sh health-check
```

### Deployment Process

The deployment script performs:

1. **Prerequisites Check**: Docker, environment, resources
2. **Environment Validation**: Required variables, security
3. **Backup Creation**: Database and storage volumes
4. **Image Building**: Multi-stage optimized builds
5. **Service Deployment**: Database → Redis → App → Nginx
6. **Health Verification**: Comprehensive health checks
7. **Cleanup**: Remove old images and backups

### Rollback Procedure

```bash
# Automatic rollback (if deployment fails)
./docker/deploy.sh rollback

# Manual rollback to specific backup
# 1. List available backups
ls -la backups/

# 2. Restore specific backup
./docker/scripts/restore.sh backup_name_20231201_120000
```

## Monitoring and Maintenance

### Health Monitoring

```bash
# Run comprehensive health check
./docker/scripts/health-check.sh

# System monitoring
./docker/scripts/monitoring.sh

# View service status
docker-compose -f docker-compose.prod.yml ps
```

### Log Management

```bash
# Application logs
docker-compose -f docker-compose.prod.yml logs -f app

# Nginx access logs
docker-compose -f docker-compose.prod.yml logs -f nginx

# Database logs
docker-compose -f docker-compose.prod.yml logs -f db

# System logs
sudo journalctl -u docker.service -f
```

### Database Maintenance

```bash
# Manual database backup
./docker/scripts/backup.sh

# Database console access
docker exec -it photograph_db_prod psql -U photograph -d photograph_production

# View database statistics
docker exec photograph_db_prod psql -U photograph -d photograph_production -c "
  SELECT schemaname, tablename, n_tup_ins, n_tup_upd, n_tup_del 
  FROM pg_stat_user_tables 
  ORDER BY n_tup_ins + n_tup_upd + n_tup_del DESC;"
```

### SSL Certificate Renewal

```bash
# Check certificate status
./docker/ssl-setup.sh test

# Manual renewal
sudo certbot renew

# Automatic renewal is configured via cron job
sudo crontab -l | grep photograph
```

## Troubleshooting

### Common Issues

#### 1. Container Won't Start

```bash
# Check container logs
docker logs photograph_app_prod

# Check system resources
docker system df
free -h
df -h

# Restart specific service
docker-compose -f docker-compose.prod.yml restart app
```

#### 2. Database Connection Issues

```bash
# Test database connectivity
docker exec photograph_app_prod bundle exec rails runner "puts ActiveRecord::Base.connection.execute('SELECT 1').first"

# Check database status
docker exec photograph_db_prod pg_isready -U photograph

# View database connections
docker exec photograph_db_prod psql -U photograph -d photograph_production -c "SELECT * FROM pg_stat_activity;"
```

#### 3. SSL Certificate Problems

```bash
# Check certificate validity
openssl x509 -in docker/ssl/fullchain.pem -text -noout

# Test SSL configuration
curl -I https://your-domain.com

# Regenerate certificates
sudo ./docker/ssl-setup.sh
```

#### 4. Performance Issues

```bash
# Monitor resource usage
docker stats

# Check Rails performance
docker exec photograph_app_prod bundle exec rails runner "puts Rails.cache.stats"

# Database performance
docker exec photograph_db_prod psql -U photograph -d photograph_production -c "SELECT * FROM pg_stat_statements ORDER BY total_time DESC LIMIT 10;"
```

### Error Recovery

#### Service Recovery

```bash
# Restart all services
docker-compose -f docker-compose.prod.yml restart

# Rebuild and redeploy
docker-compose -f docker-compose.prod.yml down
./docker/deploy.sh

# Emergency rollback
./docker/deploy.sh rollback
```

#### Data Recovery

```bash
# Restore from backup
./docker/scripts/restore.sh backup_name

# Fix file permissions
sudo chown -R 1001:1001 /var/lib/photograph
sudo chmod -R 755 /var/lib/photograph
```

## Security Considerations

### Container Security

- **Non-root user**: All containers run as unprivileged users
- **Read-only filesystem**: Containers use read-only root filesystems
- **Resource limits**: CPU and memory constraints prevent DoS
- **Network isolation**: Services communicate through private networks
- **Security scanning**: Regular vulnerability assessments

### Application Security

- **HTTPS Only**: All traffic encrypted with TLS 1.2+
- **Security Headers**: HSTS, CSP, XSS protection
- **Rate Limiting**: API and authentication endpoint protection
- **Input Validation**: SQL injection and XSS prevention
- **Session Security**: Secure cookie configuration

### Infrastructure Security

```bash
# Firewall configuration
sudo ufw enable
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Fail2ban for intrusion prevention
sudo apt install fail2ban
sudo systemctl enable fail2ban

# Regular security updates
sudo apt update && sudo apt upgrade -y
```

### Secret Management

```bash
# Generate secure secrets
openssl rand -hex 32   # For passwords
openssl rand -hex 64   # For SECRET_KEY_BASE

# Store secrets securely
chmod 600 .env
# Never commit .env to version control
```

## Performance Optimization

### Database Optimization

```sql
-- Enable query statistics
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Optimize for gallery workload
ALTER SYSTEM SET shared_buffers = '256MB';
ALTER SYSTEM SET effective_cache_size = '1GB';
ALTER SYSTEM SET random_page_cost = '1.1';  -- For SSD
SELECT pg_reload_conf();
```

### Redis Configuration

```bash
# Optimize Redis for caching
docker exec photograph_redis_prod redis-cli CONFIG SET maxmemory-policy allkeys-lru
docker exec photograph_redis_prod redis-cli CONFIG SET save "900 1 300 10 60 10000"
```

### Application Tuning

```ruby
# config/environments/production.rb optimizations
config.cache_store = :redis_cache_store, {
  url: ENV['REDIS_URL'],
  expires_in: 1.hour,
  race_condition_ttl: 5.minutes,
  compress: true
}

# Sidekiq optimization
config.active_job.queue_adapter = :sidekiq
```

### Server Optimization

```bash
# Increase file descriptor limits
echo "* soft nofile 65536" >> /etc/security/limits.conf
echo "* hard nofile 65536" >> /etc/security/limits.conf

# TCP optimization
echo "net.core.somaxconn = 1024" >> /etc/sysctl.conf
echo "net.ipv4.tcp_max_syn_backlog = 2048" >> /etc/sysctl.conf
sysctl -p
```

## Advanced Configuration

### Custom Environment Variables

```bash
# Email configuration
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USERNAME=your-email@gmail.com
SMTP_PASSWORD=your-app-password

# Cloud storage
AWS_ACCESS_KEY_ID=your-key
AWS_SECRET_ACCESS_KEY=your-secret
AWS_REGION=us-east-1
S3_BUCKET=your-bucket

# Monitoring
NEW_RELIC_LICENSE_KEY=your-key
SENTRY_DSN=https://your-dsn
```

### Scaling Configuration

```yaml
# docker-compose.prod.yml scaling
services:
  app:
    deploy:
      replicas: 3
      resources:
        limits:
          memory: 1G
          cpus: '1.0'
      restart_policy:
        condition: on-failure
        max_attempts: 3
```

### Load Balancing

```nginx
# nginx/default.prod.conf
upstream photograph_app {
    server app1:3000;
    server app2:3000;
    server app3:3000;
    keepalive 32;
}
```

## Support and Maintenance

### Regular Maintenance Tasks

**Daily:**
- Monitor health checks and logs
- Verify SSL certificate status
- Check disk space and resources

**Weekly:**
- Review performance metrics
- Analyze security logs
- Update Docker images

**Monthly:**
- Security updates and patches
- Database maintenance and optimization
- Backup verification and testing

### Getting Help

1. **Check Logs**: Start with application and system logs
2. **Health Checks**: Run diagnostic scripts
3. **Documentation**: Review troubleshooting section
4. **Community**: Rails and Docker community forums
5. **Professional Support**: Contact deployment specialists

### Contributing

Improvements and bug fixes are welcome. Please follow:

1. **Security**: Report security issues privately
2. **Testing**: Test changes in development environment
3. **Documentation**: Update guides for any changes
4. **Code Review**: Submit pull requests for review

---

## Quick Reference

### Essential Commands

```bash
# Deploy application
./docker/deploy.sh

# Health check
./docker/scripts/health-check.sh

# View logs
docker-compose -f docker-compose.prod.yml logs -f app

# Backup database
./docker/scripts/backup.sh

# SSL setup
sudo ./docker/ssl-setup.sh

# Rollback deployment
./docker/deploy.sh rollback

# System monitoring
./docker/scripts/monitoring.sh
```

### File Locations

- **Configuration**: `docker-compose.prod.yml`, `.env`
- **SSL Certificates**: `docker/ssl/`
- **Logs**: `/var/log/photograph/`
- **Data**: `/var/lib/photograph/`
- **Backups**: `/var/backups/photograph/`
- **Scripts**: `docker/scripts/`

### Support Contacts

- **Documentation**: This README and inline comments
- **Issues**: GitHub Issues for bugs and feature requests
- **Security**: security@your-domain.com for security reports

---

*This deployment guide is continuously updated. Please check for the latest version before deploying.*