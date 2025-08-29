#!/bin/bash
# ===========================================
# Production Deployment Script
# Photography Gallery - Docker Deployment
# ===========================================

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_FILE="$PROJECT_ROOT/deployment.log"
BACKUP_DIR="$PROJECT_ROOT/backups"
COMPOSE_FILE="docker-compose.prod.yml"

# Environment
ENVIRONMENT="${ENVIRONMENT:-production}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
DEPLOY_TIMEOUT="${DEPLOY_TIMEOUT:-600}"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging function
log() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local color=""
    
    case $level in
        "ERROR") color=$RED ;;
        "SUCCESS") color=$GREEN ;;
        "WARNING") color=$YELLOW ;;
        "INFO") color=$BLUE ;;
    esac
    
    echo -e "${color}[$timestamp] [$level] $message${NC}"
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Error handling
error_exit() {
    log "ERROR" "$1"
    log "ERROR" "Deployment failed. Check logs for details."
    
    if [ "$2" = "rollback" ]; then
        log "WARNING" "Starting automatic rollback..."
        rollback_deployment
    fi
    
    exit 1
}

# Trap errors
trap 'error_exit "An error occurred during deployment" "rollback"' ERR

# Pre-deployment checks
check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    # Check if Docker is installed and running
    if ! command -v docker &> /dev/null; then
        error_exit "Docker is not installed"
    fi
    
    if ! docker info &> /dev/null; then
        error_exit "Docker daemon is not running"
    fi
    
    # Check if Docker Compose is installed (plugin or standalone)
    if ! docker compose version &> /dev/null && ! command -v docker-compose &> /dev/null; then
        error_exit "Docker Compose is not installed"
    fi
    
    # Check if running as non-root (security best practice)
    if [ "$EUID" -eq 0 ]; then
        log "WARNING" "Running as root is not recommended for security reasons"
    fi
    
    # Check available disk space (minimum 5GB)
    local available_space=$(df / | awk 'NR==2 {print $4}')
    local required_space=5000000  # 5GB in KB
    
    if [ "$available_space" -lt "$required_space" ]; then
        error_exit "Insufficient disk space. Required: 5GB, Available: $(($available_space / 1000000))GB"
    fi
    
    log "SUCCESS" "Prerequisites check passed"
}

# Environment validation
validate_environment() {
    log "INFO" "Validating environment configuration..."
    
    # Check if .env file exists
    if [ ! -f "$PROJECT_ROOT/.env" ]; then
        if [ -f "$PROJECT_ROOT/.env.example" ]; then
            log "WARNING" ".env file not found. Creating from .env.example"
            cp "$PROJECT_ROOT/.env.example" "$PROJECT_ROOT/.env"
            log "WARNING" "Please edit .env file with your configuration and run again"
            exit 1
        else
            error_exit ".env file not found and no .env.example available"
        fi
    fi
    
    # Load environment variables
    source "$PROJECT_ROOT/.env"
    
    # Validate critical environment variables
    local required_vars=("DATABASE_PASSWORD" "REDIS_PASSWORD" "SECRET_KEY_BASE" "PHOTOGRAPH_HOST")
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            error_exit "Environment variable $var is not set"
        fi
    done
    
    # Check for default/weak passwords
    local weak_passwords=("password" "123456" "admin" "secret" "changeme")
    for password in "${weak_passwords[@]}"; do
        if [ "$DATABASE_PASSWORD" = "$password" ] || [ "$REDIS_PASSWORD" = "$password" ]; then
            error_exit "Weak password detected. Please use a strong password."
        fi
    done
    
    log "SUCCESS" "Environment validation passed"
}

# Backup current deployment
backup_deployment() {
    log "INFO" "Creating deployment backup..."
    
    mkdir -p "$BACKUP_DIR"
    local backup_timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup_name="deployment_backup_${backup_timestamp}"
    
    # Create database backup if database is running
    if docker ps --filter "name=photograph_db_prod" --filter "status=running" --format "{{.Names}}" | grep -q "photograph_db_prod"; then
        log "INFO" "Backing up database..."
        docker exec photograph_db_prod pg_dump -U photograph -d photograph_production | gzip > "$BACKUP_DIR/${backup_name}_database.sql.gz"
        
        # Backup storage volumes
        log "INFO" "Backing up storage volumes..."
        docker run --rm -v photograph_app_storage:/data -v "$BACKUP_DIR":/backup alpine tar czf "/backup/${backup_name}_storage.tar.gz" -C /data .
    fi
    
    # Save current docker-compose file
    if [ -f "$PROJECT_ROOT/docker-compose.yml" ]; then
        cp "$PROJECT_ROOT/docker-compose.yml" "$BACKUP_DIR/${backup_name}_docker-compose.yml"
    fi
    
    # Store backup name for potential rollback
    echo "$backup_name" > "$BACKUP_DIR/.last_backup"
    
    log "SUCCESS" "Backup created: $backup_name"
}

# Build and deploy
deploy() {
    log "INFO" "Starting deployment process..."
    
    cd "$PROJECT_ROOT"
    
    # Pull latest changes (if this is a git repository)
    if [ -d ".git" ]; then
        log "INFO" "Pulling latest changes from git..."
        git pull origin main || log "WARNING" "Failed to pull from git (continuing anyway)"
    fi
    
    # Build Docker images
    log "INFO" "Building Docker images..."
    docker compose -f "$COMPOSE_FILE" build --no-cache --pull
    
    # Tag images
    docker tag photograph:latest "photograph:$IMAGE_TAG"
    
    # Start infrastructure services first
    log "INFO" "Starting infrastructure services..."
    docker compose -f "$COMPOSE_FILE" up -d db redis
    
    # Wait for infrastructure to be ready
    log "INFO" "Waiting for database to be ready..."
    local retry_count=0
    while [ $retry_count -lt 30 ]; do
        if docker compose -f "$COMPOSE_FILE" exec -T db pg_isready -U photograph -d photograph_production; then
            break
        fi
        log "INFO" "Database not ready yet, waiting 5s... (attempt $((retry_count + 1))/30)"
        sleep 5
        retry_count=$((retry_count + 1))
    done
    
    if [ $retry_count -eq 30 ]; then
        error_exit "Database failed to start after 150 seconds"
    fi
    
    log "INFO" "Waiting for Redis to be ready..."
    retry_count=0
    while [ $retry_count -lt 30 ]; do
        if docker compose -f "$COMPOSE_FILE" exec -T redis redis-cli -a "$REDIS_PASSWORD" ping 2>/dev/null | grep -q PONG; then
            break
        fi
        log "INFO" "Redis not ready yet, waiting 5s... (attempt $((retry_count + 1))/30)"
        sleep 5
        retry_count=$((retry_count + 1))
    done
    
    if [ $retry_count -eq 30 ]; then
        error_exit "Redis failed to start after 150 seconds"
    fi
    
    # Run database migrations
    log "INFO" "Running database migrations..."
    docker compose -f "$COMPOSE_FILE" run --rm app bundle exec rails db:create db:migrate
    
    # Start application services
    log "INFO" "Starting application services..."
    docker compose -f "$COMPOSE_FILE" up -d app sidekiq
    
    # Start nginx (reverse proxy)
    log "INFO" "Starting reverse proxy..."
    docker compose -f "$COMPOSE_FILE" up -d nginx
    
    log "SUCCESS" "All services started"
}

# Health check
verify_deployment() {
    log "INFO" "Verifying deployment..."
    
    # Run comprehensive health check
    if [ -f "$SCRIPT_DIR/scripts/health-check.sh" ]; then
        chmod +x "$SCRIPT_DIR/scripts/health-check.sh"
        if ! "$SCRIPT_DIR/scripts/health-check.sh"; then
            error_exit "Health check failed"
        fi
    else
        # Basic health check
        local retry_count=0
        while [ $retry_count -lt 20 ]; do
            if curl -f -s --connect-timeout 10 "http://localhost/health" > /dev/null; then
                log "SUCCESS" "Application is responding"
                break
            fi
            log "INFO" "Application not ready yet, waiting 15s... (attempt $((retry_count + 1))/20)"
            sleep 15
            retry_count=$((retry_count + 1))
        done
        
        if [ $retry_count -eq 20 ]; then
            error_exit "Application failed to respond after 300 seconds"
        fi
    fi
    
    log "SUCCESS" "Deployment verification passed"
}

# Rollback function
rollback_deployment() {
    log "WARNING" "Starting rollback process..."
    
    if [ ! -f "$BACKUP_DIR/.last_backup" ]; then
        log "ERROR" "No backup found for rollback"
        return 1
    fi
    
    local backup_name=$(cat "$BACKUP_DIR/.last_backup")
    
    # Stop current services
    log "INFO" "Stopping current services..."
    docker compose -f "$COMPOSE_FILE" down
    
    # Restore database if backup exists
    if [ -f "$BACKUP_DIR/${backup_name}_database.sql.gz" ]; then
        log "INFO" "Restoring database..."
        docker compose -f "$COMPOSE_FILE" up -d db
        sleep 10
        zcat "$BACKUP_DIR/${backup_name}_database.sql.gz" | docker exec -i photograph_db_prod psql -U photograph
    fi
    
    # Restore storage volumes if backup exists
    if [ -f "$BACKUP_DIR/${backup_name}_storage.tar.gz" ]; then
        log "INFO" "Restoring storage volumes..."
        docker run --rm -v photograph_app_storage:/data -v "$BACKUP_DIR":/backup alpine tar xzf "/backup/${backup_name}_storage.tar.gz" -C /data
    fi
    
    # Restore previous docker-compose file
    if [ -f "$BACKUP_DIR/${backup_name}_docker-compose.yml" ]; then
        cp "$BACKUP_DIR/${backup_name}_docker-compose.yml" "$PROJECT_ROOT/docker-compose.yml"
    fi
    
    log "SUCCESS" "Rollback completed"
}

# Cleanup old backups and images
cleanup() {
    log "INFO" "Cleaning up old backups and images..."
    
    # Remove backups older than 30 days
    find "$BACKUP_DIR" -name "deployment_backup_*" -type f -mtime +30 -delete
    
    # Remove unused Docker images
    docker image prune -f
    
    # Remove dangling volumes
    docker volume prune -f
    
    log "SUCCESS" "Cleanup completed"
}

# Main deployment function
main() {
    log "INFO" "=== Photography Gallery Production Deployment ==="
    log "INFO" "Environment: $ENVIRONMENT"
    log "INFO" "Image Tag: $IMAGE_TAG"
    
    # Create log and backup directories
    mkdir -p "$(dirname "$LOG_FILE")" "$BACKUP_DIR"
    
    # Run deployment steps
    check_prerequisites
    validate_environment
    backup_deployment
    deploy
    verify_deployment
    cleanup
    
    log "SUCCESS" "=== Deployment completed successfully ==="
    log "INFO" ""
    log "INFO" "📱 Access your application at:"
    log "INFO" "   Main site: https://$PHOTOGRAPH_HOST"
    log "INFO" "   Admin dashboard: https://$PHOTOGRAPH_HOST/sidekiq"
    log "INFO" ""
    log "INFO" "🔍 Useful commands:"
    log "INFO" "   View logs: docker compose -f $COMPOSE_FILE logs -f"
    log "INFO" "   Check status: docker compose -f $COMPOSE_FILE ps"
    log "INFO" "   Health check: $SCRIPT_DIR/scripts/health-check.sh"
    log "INFO" "   Monitoring: $SCRIPT_DIR/scripts/monitoring.sh"
    log "INFO" ""
    log "INFO" "📁 Logs and backups:"
    log "INFO" "   Deployment log: $LOG_FILE"
    log "INFO" "   Backup directory: $BACKUP_DIR"
}

# Script options
case "${1:-deploy}" in
    "deploy")
        main
        ;;
    "rollback")
        rollback_deployment
        ;;
    "backup")
        backup_deployment
        ;;
    "health-check")
        verify_deployment
        ;;
    "cleanup")
        cleanup
        ;;
    *)
        echo "Usage: $0 {deploy|rollback|backup|health-check|cleanup}"
        echo ""
        echo "Commands:"
        echo "  deploy      - Full deployment (default)"
        echo "  rollback    - Rollback to previous deployment"
        echo "  backup      - Create backup only"
        echo "  health-check - Verify current deployment"
        echo "  cleanup     - Clean up old backups and images"
        exit 1
        ;;
esac