#!/bin/bash
# Start Services Script for PXE Boot Server
# Initializes and starts all PXE-related services

set -e

# Configuration
LOG_DIR="/var/log/pxe"
SCRIPT_LOG="$LOG_DIR/startup.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Create log directory if it doesn't exist
mkdir -p "$LOG_DIR"

# Logging function
log() {
    echo "[$TIMESTAMP] $1" | tee -a "$SCRIPT_LOG"
}

# Error handling
error_exit() {
    log "ERROR: $1"
    exit 1
}

# Environment variable validation
validate_environment() {
    log "Validating environment variables..."

    # Required environment variables with defaults
    declare -A required_vars=(
        ["DHCP_SUBNET"]="192.168.1.0"
        ["DHCP_NETMASK"]="255.255.255.0"
        ["DHCP_RANGE_START"]="192.168.1.100"
        ["DHCP_RANGE_END"]="192.168.1.200"
        ["DHCP_ROUTER"]="192.168.1.1"
        ["DHCP_DNS"]="8.8.8.8"
        ["NGINX_PORT"]="8080"
    )

    for var in "${!required_vars[@]}"; do
        if [ -z "${!var:-}" ]; then
            export "$var=${required_vars[$var]}"
            log "Setting default value for $var: ${required_vars[$var]}"
        fi
    done

    # Get container IP for HTTP server
    if [ -z "$HTTP_SERVER_IP" ]; then
        HTTP_SERVER_IP=$(hostname -i | awk '{print $1}')
        export HTTP_SERVER_IP
        log "Detected HTTP server IP: $HTTP_SERVER_IP"
    fi

    log "Environment validation complete"
}

# Generate configuration files from templates
generate_configs() {
    log "Generating configuration files..."

    # Generate DHCP configuration
    envsubst < /etc/pxe/dhcpd.conf > /etc/dhcp/dhcpd.conf
    log "Generated DHCP configuration"



    # Generate Nginx configuration
    envsubst < /etc/pxe/nginx.conf > /etc/nginx/nginx.conf
    log "Generated Nginx configuration"

    # Generate PXE boot menu
    mkdir -p /var/www/html/pxelinux.cfg
    envsubst < /etc/pxe/pxelinux.cfg/default > /var/www/html/pxelinux.cfg/default
    log "Generated PXE boot menu"
}

# Validate critical files exist
validate_critical_files() {
    log "Validating critical PXE boot files..."

    local critical_files=(
        "/var/www/html/pxelinux.0"
        "/var/www/html/menu.c32"
        "/var/www/html/pxelinux.cfg/default"
    )

    local missing_files=()

    for file in "${critical_files[@]}"; do
        if [ ! -f "$file" ]; then
            missing_files+=("$file")
        fi
    done

    if [ ${#missing_files[@]} -gt 0 ]; then
        log "WARNING: Missing critical PXE files:"
        for file in "${missing_files[@]}"; do
            log "  - $file"
        done
        log "Some PXE boot functionality may not work correctly"
    else
        log "All critical PXE files are present"
    fi
}

# Setup directories and permissions
setup_directories() {
    log "Setting up directories and permissions..."

    # Create necessary directories
    mkdir -p /var/www/html/images
    mkdir -p /var/lib/dhcpd
    mkdir -p /run/nginx

    # Copy PXE boot files to web root if they exist
    if [ -d /tmp/pxe-boot-files ]; then
        log "Copying PXE boot files to web root..."
        cp -r /tmp/pxe-boot-files/* /var/www/html/ 2>/dev/null || true
        rm -rf /tmp/pxe-boot-files
    fi

    # Set proper permissions
    chown -R pxeuser:pxeuser /var/www/html /var/log/pxe /run/nginx
    chown pxeuser:pxeuser /var/lib/dhcpd
    chmod 644 /etc/dhcp/dhcpd.conf

    log "Directory setup complete"
}

# Start DHCP service
start_dhcp() {
    log "Starting DHCP service..."

    # Test configuration first
    if ! dhcpd -t -cf /etc/dhcp/dhcpd.conf; then
        error_exit "DHCP configuration test failed"
    fi

    # Start DHCP service
    dhcpd -cf /etc/dhcp/dhcpd.conf -pf /var/run/dhcpd.pid

    # Wait for service to start
    sleep 2

    if kill -0 "$(cat /var/run/dhcpd.pid 2>/dev/null)" 2>/dev/null; then
        log "DHCP service started successfully"
    else
        error_exit "Failed to start DHCP service"
    fi
}



# Start Nginx service
start_nginx() {
    log "Starting Nginx service..."

    # Test configuration first
    if ! nginx -t; then
        error_exit "Nginx configuration test failed"
    fi

    # Start Nginx
    nginx

    # Wait for service to start
    sleep 2

    if [ -f /run/nginx/nginx.pid ] && kill -0 "$(cat /run/nginx/nginx.pid)" 2>/dev/null; then
        log "Nginx service started successfully"
    else
        error_exit "Failed to start Nginx service"
    fi
}

# Health check after startup
perform_health_check() {
    log "Performing post-startup health check..."

    # Run health check script
    if /usr/local/bin/healthcheck.sh; then
        log "All services started successfully and are healthy"
    else
        error_exit "Health check failed after startup"
    fi
}

# Signal handler for graceful shutdown
shutdown_services() {
    log "Received shutdown signal, stopping services..."

    # Stop services in reverse order
    if [ -f /run/nginx/nginx.pid ]; then
        nginx -s stop
        log "Nginx stopped"
    fi



    if [ -f /var/run/dhcpd.pid ]; then
        kill "$(cat /var/run/dhcpd.pid)"
        log "DHCP stopped"
    fi

    log "All services stopped"
    exit 0
}

# Setup signal handlers
trap shutdown_services SIGTERM SIGINT

# Main startup sequence
main() {
    log "=== Starting PXE Boot Server Services ==="

    validate_environment
    setup_directories
    generate_configs
    validate_critical_files

    start_dhcp
    start_nginx

    perform_health_check

    log "=== PXE Boot Server Startup Complete ==="
    log "Services running:"
    log "  - DHCP on UDP port 67"
    log "  - HTTP on TCP port ${NGINX_PORT}"
    log "Ready to serve PXE boot requests"

    # Keep container running
    while true; do
        sleep 60
        # Periodic health check
        if ! /usr/local/bin/healthcheck.sh >/dev/null 2>&1; then
            log "WARNING: Health check failed, services may be unhealthy"
        fi
    done
}

# Run main function
main "$@"
