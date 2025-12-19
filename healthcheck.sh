#!/bin/bash
# Health Check Script for PXE Boot Server
# Comprehensive health monitoring for all services

set -e

# Configuration
TIMEOUT=10
LOG_FILE="/var/log/pxe/healthcheck.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Logging function
log() {
    echo "[$TIMESTAMP] $1" >> "$LOG_FILE"
    echo "$1"
}

# Check if service is running
check_service() {
    local service=$1
    local pid_file=$2
    local port=$3
    local protocol=${4:-tcp}

    log "Checking $service..."

    # Check if process is running
    if [ -f "$pid_file" ] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
        log "✓ $service process is running"
    else
        log "✗ $service process is not running"
        return 1
    fi

    # Check if port is listening
    if [ -n "$port" ]; then
        if timeout "$TIMEOUT" bash -c "</dev/$protocol/$port" 2>/dev/null; then
            log "✓ $service port $port is listening"
        else
            log "✗ $service port $port is not responding"
            return 1
        fi
    fi

    return 0
}

# Check DHCP service
check_dhcp() {
    local dhcp_pid="/var/run/dhcpd.pid"

    if check_service "DHCP" "$dhcp_pid" "67" "udp"; then
        # Test DHCP by checking if dhcpd is responding to status queries
        if dhcpd -t -cf /etc/dhcp/dhcpd.conf >/dev/null 2>&1; then
            log "✓ DHCP configuration is valid"
            return 0
        else
            log "✗ DHCP configuration is invalid"
            return 1
        fi
    fi
    return 1
}

# Check HTTP PXE files availability
check_pxe_files() {
    log "Checking PXE boot files availability..."

    # Check if required PXE files exist in HTTP root
    local required_files=(
        "/var/www/html/pxelinux.0"
        "/var/www/html/menu.c32"
        "/var/www/html/pxelinux.cfg/default"
    )

    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            log "✗ Required PXE file missing: $file"
            return 1
        fi
    done

    # Test HTTP access to PXE files
    if curl -f -s --max-time "$TIMEOUT" "http://127.0.0.1:${NGINX_PORT:-8080}/pxelinux.0" >/dev/null; then
        log "✓ PXE boot files are accessible via HTTP"
        return 0
    else
        log "✗ PXE boot files are not accessible via HTTP"
        return 1
    fi
}

# Check Nginx service
check_nginx() {
    local nginx_pid="/run/nginx/nginx.pid"

    if check_service "Nginx" "$nginx_pid" "${NGINX_PORT:-8080}"; then
        # Test HTTP endpoint
        if curl -f -s --max-time "$TIMEOUT" "http://127.0.0.1:${NGINX_PORT:-8080}/health" >/dev/null; then
            log "✓ Nginx health endpoint is responding"
            return 0
        else
            log "✗ Nginx health endpoint is not responding"
            return 1
        fi
    fi
    return 1
}

# Check disk space
check_disk_space() {
    local threshold=90
    local usage

    usage=$(df /var/www/html | awk 'NR==2 {print $5}' | sed 's/%//')

    if [ "$usage" -lt "$threshold" ]; then
        log "✓ Disk space usage: ${usage}% (threshold: ${threshold}%)"
        return 0
    else
        log "✗ Disk space usage: ${usage}% exceeds threshold ${threshold}%"
        return 1
    fi
}

# Check network connectivity
check_network() {
    # Check if we can reach external DNS
    if timeout 5 ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        log "✓ Network connectivity is working"
        return 0
    else
        log "✗ Network connectivity is failing"
        return 1
    fi
}

# Check configuration files
check_configs() {
    local configs_ok=true

    # Check DHCP config syntax
    if ! dhcpd -t -cf /etc/dhcp/dhcpd.conf >/dev/null 2>&1; then
        log "✗ DHCP configuration syntax error"
        configs_ok=false
    fi

    # Check Nginx config syntax
    if ! nginx -t >/dev/null 2>&1; then
        log "✗ Nginx configuration syntax error"
        configs_ok=false
    fi

    # Check if required files exist
    local required_files=(
        "/var/www/html/pxelinux.0"
        "/var/www/html/menu.c32"
        "/var/www/html/pxelinux.cfg/default"
    )

    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            log "✗ Required file missing: $file"
            configs_ok=false
        fi
    done

    if [ "$configs_ok" = true ]; then
        log "✓ All configuration checks passed"
        return 0
    else
        log "✗ Configuration checks failed"
        return 1
    fi
}

# Main health check
main() {
    local failed_checks=0
    local total_checks=0

    log "=== Starting PXE Server Health Check ==="

    # Run all checks
    checks=(
        "check_configs"
        "check_dhcp"
        "check_pxe_files"
        "check_nginx"
        "check_disk_space"
        "check_network"
    )

    for check in "${checks[@]}"; do
        total_checks=$((total_checks + 1))
        if ! $check; then
            failed_checks=$((failed_checks + 1))
        fi
    done

    log "=== Health Check Complete: $((total_checks - failed_checks))/$total_checks checks passed ==="

    # Exit with appropriate code
    if [ "$failed_checks" -eq 0 ]; then
        log "✓ All health checks passed"
        exit 0
    else
        log "✗ $failed_checks health check(s) failed"
        exit 1
    fi
}

# Run main function
main "$@"
