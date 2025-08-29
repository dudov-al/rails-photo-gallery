#!/bin/bash
# ===========================================
# SSL Certificate Setup Script
# Let's Encrypt + Nginx Configuration
# ===========================================

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SSL_DIR="$SCRIPT_DIR/ssl"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    local level=$1
    local message=$2
    local color=""
    
    case $level in
        "ERROR") color=$RED ;;
        "SUCCESS") color=$GREEN ;;
        "WARNING") color=$YELLOW ;;
        "INFO") color=$BLUE ;;
    esac
    
    echo -e "${color}[$level] $message${NC}"
}

# Check prerequisites
check_prerequisites() {
    log "INFO" "Checking SSL setup prerequisites..."
    
    # Check if running as root or with sudo
    if [ "$EUID" -ne 0 ]; then
        log "ERROR" "This script must be run as root or with sudo for SSL certificate management"
        exit 1
    fi
    
    # Check if domain is provided
    if [ -z "$DOMAIN" ]; then
        log "ERROR" "DOMAIN environment variable is not set"
        exit 1
    fi
    
    # Check if email is provided
    if [ -z "$ADMIN_EMAIL" ]; then
        log "ERROR" "ADMIN_EMAIL environment variable is not set"
        exit 1
    fi
    
    # Check if certbot is available
    if ! command -v certbot &> /dev/null; then
        log "INFO" "Installing certbot..."
        if command -v apt-get &> /dev/null; then
            apt-get update && apt-get install -y certbot python3-certbot-nginx
        elif command -v yum &> /dev/null; then
            yum install -y certbot python3-certbot-nginx
        else
            log "ERROR" "Cannot install certbot. Please install manually."
            exit 1
        fi
    fi
    
    log "SUCCESS" "Prerequisites check passed"
}

# Create SSL directory and files
setup_ssl_directory() {
    log "INFO" "Setting up SSL directory structure..."
    
    mkdir -p "$SSL_DIR"
    chmod 700 "$SSL_DIR"
    
    # Create DH parameters for enhanced security (this may take a while)
    if [ ! -f "$SSL_DIR/dhparam.pem" ]; then
        log "INFO" "Generating DH parameters (this may take several minutes)..."
        openssl dhparam -out "$SSL_DIR/dhparam.pem" 2048
        chmod 600 "$SSL_DIR/dhparam.pem"
        log "SUCCESS" "DH parameters generated"
    else
        log "INFO" "DH parameters already exist"
    fi
    
    log "SUCCESS" "SSL directory setup complete"
}

# Generate self-signed certificate for initial setup
generate_self_signed_cert() {
    log "INFO" "Generating self-signed certificate for initial setup..."
    
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$SSL_DIR/privkey.pem" \
        -out "$SSL_DIR/fullchain.pem" \
        -subj "/C=US/ST=State/L=City/O=Organization/OU=OrgUnit/CN=$DOMAIN"
    
    # Create chain file (same as fullchain for self-signed)
    cp "$SSL_DIR/fullchain.pem" "$SSL_DIR/chain.pem"
    
    chmod 600 "$SSL_DIR/privkey.pem"
    chmod 644 "$SSL_DIR/fullchain.pem" "$SSL_DIR/chain.pem"
    
    log "SUCCESS" "Self-signed certificate generated"
}

# Obtain Let's Encrypt certificate
obtain_letsencrypt_cert() {
    log "INFO" "Obtaining Let's Encrypt certificate for $DOMAIN..."
    
    # Create webroot directory for ACME challenge
    mkdir -p /var/www/certbot
    
    # Stop nginx if running to avoid conflicts
    if docker ps --filter "name=photograph_nginx_prod" --filter "status=running" --format "{{.Names}}" | grep -q "photograph_nginx_prod"; then
        log "INFO" "Stopping nginx for certificate generation..."
        docker stop photograph_nginx_prod || true
    fi
    
    # Obtain certificate using standalone method
    certbot certonly \
        --standalone \
        --email "$ADMIN_EMAIL" \
        --agree-tos \
        --no-eff-email \
        --domains "$DOMAIN" \
        --non-interactive
    
    if [ $? -eq 0 ]; then
        log "SUCCESS" "Let's Encrypt certificate obtained successfully"
        
        # Copy certificates to our SSL directory
        cp "/etc/letsencrypt/live/$DOMAIN/privkey.pem" "$SSL_DIR/"
        cp "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" "$SSL_DIR/"
        cp "/etc/letsencrypt/live/$DOMAIN/chain.pem" "$SSL_DIR/"
        
        chmod 600 "$SSL_DIR/privkey.pem"
        chmod 644 "$SSL_DIR/fullchain.pem" "$SSL_DIR/chain.pem"
        
        log "SUCCESS" "Certificates copied to project SSL directory"
    else
        log "WARNING" "Let's Encrypt certificate generation failed, using self-signed certificate"
        generate_self_signed_cert
    fi
}

# Setup certificate renewal
setup_cert_renewal() {
    log "INFO" "Setting up automatic certificate renewal..."
    
    # Create renewal script
    cat > /usr/local/bin/renew-photograph-ssl.sh << EOF
#!/bin/bash
# Automatic SSL certificate renewal for Photography Gallery

# Renew certificate
certbot renew --quiet --no-self-upgrade

# Copy renewed certificates
if [ -f "/etc/letsencrypt/live/$DOMAIN/privkey.pem" ]; then
    cp "/etc/letsencrypt/live/$DOMAIN/privkey.pem" "$SSL_DIR/"
    cp "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" "$SSL_DIR/"
    cp "/etc/letsencrypt/live/$DOMAIN/chain.pem" "$SSL_DIR/"
    
    chmod 600 "$SSL_DIR/privkey.pem"
    chmod 644 "$SSL_DIR/fullchain.pem" "$SSL_DIR/chain.pem"
    
    # Reload nginx
    docker exec photograph_nginx_prod nginx -s reload 2>/dev/null || true
fi
EOF
    
    chmod +x /usr/local/bin/renew-photograph-ssl.sh
    
    # Add cron job for automatic renewal (runs twice daily)
    cat > /etc/cron.d/photograph-ssl-renewal << EOF
# Photography Gallery SSL Certificate Renewal
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# Run twice daily at random times to avoid rate limiting
15 2,14 * * * root /usr/local/bin/renew-photograph-ssl.sh >/dev/null 2>&1
EOF
    
    log "SUCCESS" "Automatic certificate renewal configured"
}

# Test SSL configuration
test_ssl_config() {
    log "INFO" "Testing SSL configuration..."
    
    # Check if certificates exist and are readable
    if [ ! -f "$SSL_DIR/privkey.pem" ] || [ ! -f "$SSL_DIR/fullchain.pem" ] || [ ! -f "$SSL_DIR/chain.pem" ]; then
        log "ERROR" "SSL certificates are missing"
        return 1
    fi
    
    # Test certificate validity
    if ! openssl x509 -in "$SSL_DIR/fullchain.pem" -text -noout > /dev/null 2>&1; then
        log "ERROR" "SSL certificate is invalid"
        return 1
    fi
    
    # Check certificate expiration
    local expiry_date=$(openssl x509 -in "$SSL_DIR/fullchain.pem" -noout -enddate | cut -d= -f2)
    local expiry_epoch=$(date -d "$expiry_date" +%s)
    local current_epoch=$(date +%s)
    local days_until_expiry=$(((expiry_epoch - current_epoch) / 86400))
    
    if [ $days_until_expiry -lt 30 ]; then
        log "WARNING" "SSL certificate expires in $days_until_expiry days"
    else
        log "SUCCESS" "SSL certificate is valid for $days_until_expiry days"
    fi
    
    log "SUCCESS" "SSL configuration test passed"
}

# Create nginx SSL configuration snippet
create_ssl_snippet() {
    log "INFO" "Creating nginx SSL configuration snippet..."
    
    cat > "$SCRIPT_DIR/nginx/ssl-params.conf" << 'EOF'
# SSL Configuration Parameters
# Modern SSL configuration for maximum security

# SSL protocols and ciphers
ssl_protocols TLSv1.2 TLSv1.3;
ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
ssl_prefer_server_ciphers off;

# SSL session configuration
ssl_session_timeout 1d;
ssl_session_cache shared:MozTLS:10m;
ssl_session_tickets off;

# OCSP stapling
ssl_stapling on;
ssl_stapling_verify on;
resolver 1.1.1.1 1.0.0.1 8.8.8.8 8.8.4.4 valid=300s;
resolver_timeout 5s;

# Security headers
add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
add_header X-Content-Type-Options "nosniff" always;
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-XSS-Protection "1; mode=block" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
EOF
    
    log "SUCCESS" "SSL configuration snippet created"
}

# Main SSL setup function
main() {
    log "INFO" "=== Photography Gallery SSL Setup ==="
    
    # Load environment variables
    if [ -f "$PROJECT_ROOT/.env" ]; then
        source "$PROJECT_ROOT/.env"
    else
        log "ERROR" ".env file not found. Please create it first."
        exit 1
    fi
    
    check_prerequisites
    setup_ssl_directory
    
    if [ "$1" = "--self-signed" ]; then
        log "INFO" "Using self-signed certificate as requested"
        generate_self_signed_cert
    else
        obtain_letsencrypt_cert
        setup_cert_renewal
    fi
    
    test_ssl_config
    create_ssl_snippet
    
    log "SUCCESS" "=== SSL setup completed successfully ==="
    log "INFO" ""
    log "INFO" "SSL certificates are located in: $SSL_DIR"
    log "INFO" "Certificate files:"
    log "INFO" "  - Private key: $SSL_DIR/privkey.pem"
    log "INFO" "  - Certificate: $SSL_DIR/fullchain.pem"
    log "INFO" "  - Certificate chain: $SSL_DIR/chain.pem"
    log "INFO" "  - DH parameters: $SSL_DIR/dhparam.pem"
    log "INFO" ""
    log "INFO" "Next steps:"
    log "INFO" "1. Update your DNS to point $DOMAIN to this server"
    log "INFO" "2. Run the deployment script: ./docker/deploy.sh"
    log "INFO" "3. Your site will be available at: https://$DOMAIN"
}

# Handle script arguments
case "${1:-setup}" in
    "setup"|"")
        main
        ;;
    "--self-signed")
        main --self-signed
        ;;
    "renew")
        setup_cert_renewal
        ;;
    "test")
        source "$PROJECT_ROOT/.env" 2>/dev/null || true
        test_ssl_config
        ;;
    *)
        echo "Usage: $0 [setup|--self-signed|renew|test]"
        echo ""
        echo "Commands:"
        echo "  setup          - Setup Let's Encrypt SSL (default)"
        echo "  --self-signed  - Generate self-signed certificate"
        echo "  renew          - Setup automatic renewal only"
        echo "  test           - Test current SSL configuration"
        exit 1
        ;;
esac