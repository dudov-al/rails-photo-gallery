#!/bin/bash
# ===========================================
# System Monitoring Script
# ===========================================

set -e

# Configuration
LOG_DIR="/var/log/photograph"
ALERT_EMAIL="${ADMIN_EMAIL:-admin@localhost}"
MEMORY_THRESHOLD=85
DISK_THRESHOLD=85
CPU_THRESHOLD=80

# Create log directory
mkdir -p "$LOG_DIR"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    local color=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${color}[${timestamp}] ${message}${NC}"
    echo "[${timestamp}] ${message}" >> "$LOG_DIR/monitoring.log"
}

# Function to send alert (customize based on your notification system)
send_alert() {
    local subject=$1
    local message=$2
    
    print_status $RED "ALERT: $subject"
    echo "$message" >> "$LOG_DIR/alerts.log"
    
    # Uncomment and configure for email alerts
    # echo "$message" | mail -s "$subject" "$ALERT_EMAIL"
    
    # Uncomment and configure for Slack alerts
    # curl -X POST -H 'Content-type: application/json' \
    #     --data "{\"text\":\"$subject: $message\"}" \
    #     "$SLACK_WEBHOOK_URL"
}

# Monitor container health
monitor_containers() {
    print_status $BLUE "Monitoring container health..."
    
    local containers=("photograph_db_prod" "photograph_redis_prod" "photograph_app_prod" "photograph_sidekiq_prod" "photograph_nginx_prod")
    
    for container in "${containers[@]}"; do
        if ! docker ps --filter "name=$container" --filter "status=running" --format "{{.Names}}" | grep -q "$container"; then
            send_alert "Container Down" "$container is not running"
            
            # Attempt to restart container
            print_status $YELLOW "Attempting to restart $container..."
            if docker restart "$container"; then
                print_status $GREEN "Successfully restarted $container"
            else
                send_alert "Container Restart Failed" "Failed to restart $container"
            fi
        else
            print_status $GREEN "✓ $container is running"
        fi
    done
}

# Monitor system resources
monitor_resources() {
    print_status $BLUE "Monitoring system resources..."
    
    # Memory usage
    local memory_usage=$(free | grep Mem | awk '{printf("%.0f", $3/$2 * 100.0)}')
    if [ "$memory_usage" -gt "$MEMORY_THRESHOLD" ]; then
        send_alert "High Memory Usage" "Memory usage is ${memory_usage}%"
    else
        print_status $GREEN "✓ Memory usage: ${memory_usage}%"
    fi
    
    # Disk usage
    local disk_usage=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
    if [ "$disk_usage" -gt "$DISK_THRESHOLD" ]; then
        send_alert "High Disk Usage" "Disk usage is ${disk_usage}%"
    else
        print_status $GREEN "✓ Disk usage: ${disk_usage}%"
    fi
    
    # CPU usage (5-minute average)
    local cpu_usage=$(uptime | awk -F'load average:' '{ print $2 }' | cut -d, -f2 | xargs)
    local cpu_cores=$(nproc)
    local cpu_percent=$(awk "BEGIN {printf \"%.0f\", ($cpu_usage / $cpu_cores) * 100}")
    
    if [ "$cpu_percent" -gt "$CPU_THRESHOLD" ]; then
        send_alert "High CPU Usage" "CPU usage is ${cpu_percent}% (load: $cpu_usage)"
    else
        print_status $GREEN "✓ CPU usage: ${cpu_percent}% (load: $cpu_usage)"
    fi
}

# Monitor application health
monitor_application() {
    print_status $BLUE "Monitoring application health..."
    
    # Check main application
    if ! curl -f -s --connect-timeout 10 http://localhost/health > /dev/null; then
        send_alert "Application Health Check Failed" "Main application is not responding"
    else
        print_status $GREEN "✓ Application is responding"
    fi
    
    # Check database connections
    local db_connections=$(docker exec photograph_db_prod psql -U photograph -d photograph_production -t -c "SELECT count(*) FROM pg_stat_activity WHERE state = 'active';" | xargs)
    if [ "$db_connections" -gt 50 ]; then
        send_alert "High Database Connections" "Active database connections: $db_connections"
    else
        print_status $GREEN "✓ Database connections: $db_connections"
    fi
    
    # Check Redis memory usage
    local redis_memory=$(docker exec photograph_redis_prod redis-cli info memory | grep used_memory_human | cut -d: -f2 | tr -d '\r')
    print_status $GREEN "✓ Redis memory usage: $redis_memory"
}

# Monitor logs for errors
monitor_logs() {
    print_status $BLUE "Monitoring application logs..."
    
    # Check for recent errors in application logs
    local error_count=$(docker logs --since="5m" photograph_app_prod 2>&1 | grep -i "error\|exception\|fatal" | wc -l)
    if [ "$error_count" -gt 10 ]; then
        send_alert "High Error Rate" "Found $error_count errors in the last 5 minutes"
    else
        print_status $GREEN "✓ Error count in last 5 minutes: $error_count"
    fi
    
    # Check Nginx access logs for high error rates
    local nginx_errors=$(docker logs --since="5m" photograph_nginx_prod 2>&1 | grep " 5[0-9][0-9] " | wc -l)
    if [ "$nginx_errors" -gt 20 ]; then
        send_alert "High HTTP Error Rate" "Found $nginx_errors 5xx errors in the last 5 minutes"
    else
        print_status $GREEN "✓ HTTP 5xx errors in last 5 minutes: $nginx_errors"
    fi
}

# Generate system report
generate_report() {
    local report_file="$LOG_DIR/system-report-$(date +%Y%m%d).log"
    
    {
        echo "=== System Report - $(date) ==="
        echo
        echo "=== Docker Containers ==="
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
        echo
        echo "=== System Resources ==="
        echo "Memory Usage:"
        free -h
        echo
        echo "Disk Usage:"
        df -h
        echo
        echo "CPU Load:"
        uptime
        echo
        echo "=== Database Statistics ==="
        docker exec photograph_db_prod psql -U photograph -d photograph_production -c "
        SELECT 
            schemaname,
            tablename,
            n_tup_ins as inserts,
            n_tup_upd as updates,
            n_tup_del as deletes
        FROM pg_stat_user_tables 
        ORDER BY n_tup_ins + n_tup_upd + n_tup_del DESC 
        LIMIT 10;"
        echo
    } > "$report_file"
    
    print_status $GREEN "System report generated: $report_file"
}

# Main monitoring function
main() {
    print_status $BLUE "=== Starting System Monitoring ==="
    
    monitor_containers
    monitor_resources
    monitor_application
    monitor_logs
    generate_report
    
    print_status $BLUE "=== Monitoring Complete ==="
}

# Run main function
main "$@"