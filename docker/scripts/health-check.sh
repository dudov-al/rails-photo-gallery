#!/bin/bash
# ===========================================
# Comprehensive Health Check Script
# ===========================================

set -e

# Configuration
HEALTH_ENDPOINT="http://localhost/health"
MAX_RETRIES=5
RETRY_DELAY=10
TIMEOUT=30

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to check service health
check_service_health() {
    local service_name=$1
    local health_command=$2
    
    print_status $BLUE "Checking ${service_name}..."
    
    if eval $health_command; then
        print_status $GREEN "✓ ${service_name} is healthy"
        return 0
    else
        print_status $RED "✗ ${service_name} is unhealthy"
        return 1
    fi
}

# Function to check container status
check_container_status() {
    local container_name=$1
    
    if docker ps --filter "name=${container_name}" --filter "status=running" --format "table {{.Names}}" | grep -q "${container_name}"; then
        print_status $GREEN "✓ Container ${container_name} is running"
        return 0
    else
        print_status $RED "✗ Container ${container_name} is not running"
        return 1
    fi
}

# Function to check application endpoint
check_application_endpoint() {
    local url=$1
    local retries=0
    
    while [ $retries -lt $MAX_RETRIES ]; do
        print_status $BLUE "Checking application endpoint (attempt $((retries + 1))/${MAX_RETRIES})..."
        
        if curl -f -s --connect-timeout $TIMEOUT "$url" > /dev/null; then
            print_status $GREEN "✓ Application endpoint is responding"
            return 0
        else
            print_status $YELLOW "⚠ Application not responding, retrying in ${RETRY_DELAY}s..."
            sleep $RETRY_DELAY
            retries=$((retries + 1))
        fi
    done
    
    print_status $RED "✗ Application endpoint failed after $MAX_RETRIES attempts"
    return 1
}

# Main health check function
main() {
    print_status $BLUE "=== Photography Gallery Health Check ==="
    echo
    
    local all_healthy=true
    
    # Check Docker containers
    print_status $BLUE "--- Container Status ---"
    check_container_status "photograph_db_prod" || all_healthy=false
    check_container_status "photograph_redis_prod" || all_healthy=false
    check_container_status "photograph_app_prod" || all_healthy=false
    check_container_status "photograph_sidekiq_prod" || all_healthy=false
    check_container_status "photograph_nginx_prod" || all_healthy=false
    echo
    
    # Check service health
    print_status $BLUE "--- Service Health ---"
    check_service_health "PostgreSQL" "docker exec photograph_db_prod pg_isready -U photograph -d photograph_production" || all_healthy=false
    check_service_health "Redis" "docker exec photograph_redis_prod redis-cli ping | grep -q PONG" || all_healthy=false
    check_service_health "Rails App" "docker exec photograph_app_prod curl -f http://localhost:3000/health" || all_healthy=false
    check_service_health "Sidekiq" "docker exec photograph_sidekiq_prod pgrep -f sidekiq" || all_healthy=false
    echo
    
    # Check application endpoint
    print_status $BLUE "--- Application Endpoint ---"
    check_application_endpoint "$HEALTH_ENDPOINT" || all_healthy=false
    echo
    
    # Check disk usage
    print_status $BLUE "--- System Resources ---"
    DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
    if [ "$DISK_USAGE" -gt 80 ]; then
        print_status $YELLOW "⚠ Disk usage is ${DISK_USAGE}% (consider cleanup)"
    else
        print_status $GREEN "✓ Disk usage is ${DISK_USAGE}%"
    fi
    
    # Check memory usage
    MEMORY_USAGE=$(free | grep Mem | awk '{printf("%.0f", $3/$2 * 100.0)}')
    if [ "$MEMORY_USAGE" -gt 90 ]; then
        print_status $RED "✗ Memory usage is ${MEMORY_USAGE}%"
        all_healthy=false
    elif [ "$MEMORY_USAGE" -gt 80 ]; then
        print_status $YELLOW "⚠ Memory usage is ${MEMORY_USAGE}%"
    else
        print_status $GREEN "✓ Memory usage is ${MEMORY_USAGE}%"
    fi
    echo
    
    # Final status
    print_status $BLUE "--- Final Status ---"
    if [ "$all_healthy" = true ]; then
        print_status $GREEN "✓ All systems are healthy!"
        exit 0
    else
        print_status $RED "✗ Some systems are unhealthy!"
        exit 1
    fi
}

# Run main function
main "$@"