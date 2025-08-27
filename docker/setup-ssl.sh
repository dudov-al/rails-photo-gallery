#!/bin/bash

# SSL Certificate Setup for Photo Gallery
# Usage: ./docker/setup-ssl.sh your-domain.com

set -e

DOMAIN=$1

if [ -z "$DOMAIN" ]; then
    echo "❌ Usage: ./docker/setup-ssl.sh your-domain.com"
    exit 1
fi

echo "🔒 Setting up SSL certificate for $DOMAIN..."

# Check if certbot is installed
if ! command -v certbot &> /dev/null; then
    echo "📦 Installing certbot..."
    if command -v apt-get &> /dev/null; then
        sudo apt-get update
        sudo apt-get install -y certbot
    elif command -v yum &> /dev/null; then
        sudo yum install -y certbot
    else
        echo "❌ Please install certbot manually for your system"
        exit 1
    fi
fi

# Stop nginx temporarily to get certificate
echo "🛑 Stopping nginx to obtain certificate..."
docker-compose stop nginx

# Get certificate
echo "📜 Obtaining SSL certificate..."
sudo certbot certonly \
    --standalone \
    --agree-tos \
    --no-eff-email \
    --email webmaster@$DOMAIN \
    -d $DOMAIN

# Create SSL directory
echo "📁 Creating SSL directory..."
mkdir -p docker/ssl

# Copy certificates
echo "📋 Copying certificates..."
sudo cp /etc/letsencrypt/live/$DOMAIN/fullchain.pem docker/ssl/
sudo cp /etc/letsencrypt/live/$DOMAIN/privkey.pem docker/ssl/
sudo chmod 644 docker/ssl/*.pem

# Update environment for HTTPS
echo "⚙️  Updating environment configuration..."
if [ -f .env ]; then
    # Update domain and protocol
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        sed -i '' "s/PHOTOGRAPH_HOST=.*/PHOTOGRAPH_HOST=$DOMAIN/" .env
        sed -i '' "s/PHOTOGRAPH_PROTOCOL=.*/PHOTOGRAPH_PROTOCOL=https/" .env
        sed -i '' "s/FORCE_SSL=.*/FORCE_SSL=true/" .env
    else
        # Linux
        sed -i "s/PHOTOGRAPH_HOST=.*/PHOTOGRAPH_HOST=$DOMAIN/" .env
        sed -i "s/PHOTOGRAPH_PROTOCOL=.*/PHOTOGRAPH_PROTOCOL=https/" .env
        sed -i "s/FORCE_SSL=.*/FORCE_SSL=true/" .env
    fi
    echo "✅ Environment updated for HTTPS"
else
    echo "❌ .env file not found. Please create it first."
    exit 1
fi

# Update nginx configuration
echo "🔧 Enabling HTTPS in nginx configuration..."
NGINX_CONFIG="docker/nginx/default.conf"

# Uncomment HTTPS redirect in HTTP server
if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' 's/# return 301 https/return 301 https/' "$NGINX_CONFIG"
    sed -i '' 's/# location \/ {/location \/ {/' "$NGINX_CONFIG" || true
fi

echo "📝 Please manually enable the HTTPS server block in docker/nginx/default.conf"
echo "   Uncomment the 'server { listen 443...' section at the end of the file"

# Restart services
echo "🔄 Restarting services..."
docker-compose up -d

echo ""
echo "🎉 SSL setup complete!"
echo ""
echo "🌐 Your site is now available at:"
echo "   https://$DOMAIN"
echo ""
echo "📋 Next steps:"
echo "1. Manually uncomment the HTTPS server block in docker/nginx/default.conf"
echo "2. Run: docker-compose restart nginx"
echo "3. Set up certificate renewal:"
echo "   Add to crontab: 0 12 * * * /usr/bin/certbot renew --quiet"
echo ""
echo "🔄 To renew certificates automatically, add this to your crontab:"
echo '   0 12 * * * /usr/bin/certbot renew --quiet && docker-compose restart nginx'