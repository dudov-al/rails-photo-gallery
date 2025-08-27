#!/bin/bash

# Quick deployment script for Photo Gallery
# Usage: ./docker/deploy.sh

set -e

echo "🚀 Starting Photo Gallery Deployment..."

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "❌ Docker not found. Please install Docker first."
    exit 1
fi

# Check if Docker Compose is installed
if ! command -v docker-compose &> /dev/null; then
    echo "❌ Docker Compose not found. Please install Docker Compose first."
    exit 1
fi

# Check if .env file exists
if [ ! -f .env ]; then
    echo "📝 Creating .env file from template..."
    cp .env.example .env
    
    echo "⚠️  IMPORTANT: Please edit the .env file with your secure passwords before continuing!"
    echo "   Especially update these variables:"
    echo "   - DATABASE_PASSWORD"
    echo "   - REDIS_PASSWORD" 
    echo "   - SECRET_KEY_BASE"
    echo "   - SIDEKIQ_PASSWORD"
    echo ""
    
    # Generate a secret key base
    echo "🔑 Generating SECRET_KEY_BASE..."
    if command -v openssl &> /dev/null; then
        SECRET_KEY=$(openssl rand -hex 64)
        # Update the .env file with the generated secret
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS
            sed -i '' "s/SECRET_KEY_BASE=generate_with_rails_secret_or_openssl_rand_hex_64/SECRET_KEY_BASE=$SECRET_KEY/" .env
        else
            # Linux
            sed -i "s/SECRET_KEY_BASE=generate_with_rails_secret_or_openssl_rand_hex_64/SECRET_KEY_BASE=$SECRET_KEY/" .env
        fi
        echo "✅ SECRET_KEY_BASE generated and updated in .env"
    else
        echo "❌ OpenSSL not found. Please manually generate SECRET_KEY_BASE."
    fi
    
    echo ""
    echo "Please review and update .env file, then run this script again."
    exit 0
fi

# Check if critical environment variables are set
if grep -q "secure_database_password_change_me" .env || grep -q "generate_with_rails_secret_or_openssl_rand_hex_64" .env; then
    echo "❌ Please update the default passwords in .env file before deploying!"
    echo "   Check these variables:"
    echo "   - DATABASE_PASSWORD"
    echo "   - SECRET_KEY_BASE"
    exit 1
fi

echo "🔧 Building Docker images..."
docker-compose build

echo "🗄️  Starting database and Redis..."
docker-compose up -d db redis

echo "⏳ Waiting for database to be ready..."
sleep 10

# Check database health
echo "🔍 Checking database connection..."
docker-compose exec -T db pg_isready -U photograph -d photograph_production

echo "🚀 Starting all services..."
docker-compose up -d

echo "⏳ Waiting for application to start..."
sleep 30

# Check application health
echo "🔍 Checking application health..."
if curl -f http://localhost/health > /dev/null 2>&1; then
    echo "✅ Application is healthy!"
else
    echo "⚠️  Application might still be starting up. Check logs with: docker-compose logs -f app"
fi

echo ""
echo "🎉 Deployment complete!"
echo ""
echo "📱 Access your application at:"
echo "   Main site: http://localhost"
echo "   Admin dashboard: http://localhost/sidekiq"
echo ""
echo "🔍 Useful commands:"
echo "   View logs: docker-compose logs -f"
echo "   Check status: docker-compose ps" 
echo "   Stop services: docker-compose down"
echo "   Restart: docker-compose restart"
echo ""
echo "📖 For detailed documentation, see DOCKER_DEPLOYMENT.md"