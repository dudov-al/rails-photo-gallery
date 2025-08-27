# 🐳 Docker Quick Start - Photo Gallery

Deploy your complete Rails photo gallery in 5 minutes with one command.

## Requirements
- Server with Docker installed
- 2GB+ RAM, 20GB+ disk

## Deploy Now

### 1. Setup Environment
```bash
# Copy and edit configuration
cp .env.example .env
# Edit .env with secure passwords
```

### 2. One-Command Deploy
```bash
./docker/deploy.sh
```

### 3. Access Your Gallery
- **Gallery**: http://your-server-ip
- **Admin**: http://your-server-ip/sidekiq

## SSL Setup (Optional)
```bash
./docker/setup-ssl.sh your-domain.com
```

## What You Get
✅ Complete Rails 7 photo gallery
✅ PostgreSQL database  
✅ Redis caching
✅ Background job processing
✅ Nginx reverse proxy
✅ Admin dashboard
✅ Production security
✅ Automatic backups

## Quick Commands
```bash
# View status
docker-compose ps

# View logs  
docker-compose logs -f app

# Restart
docker-compose restart

# Stop
docker-compose down
```

See `DOCKER_DEPLOYMENT.md` for complete documentation.

---
**Ready to go in 5 minutes! 🚀**