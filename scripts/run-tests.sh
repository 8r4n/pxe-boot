#!/bin/bash
# PXE Server Test Runner
# Runs comprehensive test suite

set -e

# Configuration
# Use test-results in current directory if running locally, or /test-results if in container
if [ -d "/test-results" ]; then
    TEST_RESULTS_DIR="/test-results"
else
    TEST_RESULTS_DIR="./test-results"
fi
TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')
TEST_LOG="${TEST_RESULTS_DIR}/test-run-${TIMESTAMP}.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$TEST_LOG"
}

log_success() {
    echo -e "${GREEN}✓ $1${NC}" | tee -a "$TEST_LOG"
}

log_error() {
    echo -e "${RED}✗ $1${NC}" | tee -a "$TEST_LOG"
}

log_warning() {
    echo -e "${YELLOW}⚠ $1${NC}" | tee -a "$TEST_LOG"
}

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Test runner function
run_test() {
    local test_name="$1"
    local test_command="$2"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    log "Running test: $test_name"

    if eval "$test_command" >> "$TEST_LOG" 2>&1; then
        log_success "$test_name passed"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        log_error "$test_name failed"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
}

# Unit Tests

test_shell_syntax() {
    local failed_scripts=()

    log "Checking shell script syntax..."

    for script in scripts/*.sh; do
        if [ -f "$script" ]; then
            if ! bash -n "$script"; then
                failed_scripts+=("$script")
            fi
        fi
    done

    if [ ${#failed_scripts[@]} -eq 0 ]; then
        return 0
    else
        log_error "Scripts with syntax errors: ${failed_scripts[*]}"
        return 1
    fi
}

test_docker_config() {
    log "Testing Docker configuration..."

    # Test docker-compose config
    if ! docker-compose config --quiet; then
        log_error "docker-compose.yml configuration is invalid"
        return 1
    fi

    # Test Dockerfile build (dry run)
    if ! docker build --dry-run -f Dockerfile . >/dev/null 2>&1; then
        log_error "Dockerfile has build errors"
        return 1
    fi

    return 0
}

test_environment_variables() {
    log "Testing environment variable validation..."

    # Source the start-services script functions
    source scripts/start-services.sh

    # Test environment validation with missing vars
    unset DHCP_SUBNET
    if validate_environment >/dev/null 2>&1; then
        log_error "Environment validation should fail with missing variables"
        return 1
    fi

    return 0
}

test_file_permissions() {
    log "Testing file permissions..."

    # Check script executability
    for script in scripts/*.sh; do
        if [ ! -x "$script" ]; then
            log_error "Script $script is not executable"
            return 1
        fi
    done

    return 0
}

test_configuration_files() {
    log "Testing configuration file syntax..."

    # Test DHCP config syntax
    if ! dhcpd -t -cf configs/dhcpd.conf >/dev/null 2>&1; then
        log_error "DHCP configuration syntax is invalid"
        return 1
    fi

    # Test nginx config syntax
    if ! nginx -t -c configs/nginx.conf >/dev/null 2>&1; then
        log_error "Nginx configuration syntax is invalid"
        return 1
    fi

    return 0
}

test_backup_restore() {
    log "Testing backup and restore functionality..."

    local test_backup_dir="/tmp/test-backup"
    local test_restore_dir="/tmp/test-restore"

    # Create test data
    mkdir -p "$test_backup_dir/configs"
    echo "test config" > "$test_backup_dir/configs/test.conf"

    # Test backup script (basic functionality)
    if ! timeout 30 bash scripts/backup.sh --backup-root /tmp --help >/dev/null 2>&1; then
        log_error "Backup script help functionality failed"
        return 1
    fi

    # Clean up
    rm -rf "$test_backup_dir"

    return 0
}

test_health_check() {
    log "Testing health check script..."

    # Health check should fail when services aren't running
    if ./healthcheck.sh >/dev/null 2>&1; then
        log_error "Health check should fail when services aren't running"
        return 1
    fi

    return 0
}

# Integration Tests

test_service_startup() {
    log "Testing service startup..."

    # This would run in the container environment
    # Check if critical files exist
    local critical_files=(
        "/var/www/html/pxelinux.0"
        "/var/www/html/menu.c32"
        "/etc/dhcp/dhcpd.conf"
        "/etc/nginx/nginx.conf"
    )

    for file in "${critical_files[@]}"; do
        if [ ! -f "$file" ]; then
            log_error "Critical file missing: $file"
            return 1
        fi
    done

    return 0
}

test_http_endpoints() {
    log "Testing HTTP endpoints..."

    # Test health endpoint
    if ! curl -f -s --max-time 10 "http://127.0.0.1:8080/health" >/dev/null; then
        log_error "Health endpoint is not responding"
        return 1
    fi

    # Test PXE files are accessible
    if ! curl -f -s --max-time 10 "http://127.0.0.1:8080/pxelinux.0" >/dev/null; then
        log_error "PXE boot file is not accessible"
        return 1
    fi

    return 0
}

test_dhcp_service() {
    log "Testing DHCP service..."

    # Check if DHCP service is listening on port 67
    if ! timeout 5 bash -c "</dev/udp/127.0.0.1/67" >/dev/null 2>&1; then
        log_error "DHCP service is not listening on port 67"
        return 1
    fi

    return 0
}

# Performance Tests

test_performance() {
    log "Running performance tests..."

    # Test HTTP response time
    local start_time=$(date +%s%N)
    curl -s "http://127.0.0.1:8080/health" >/dev/null
    local end_time=$(date +%s%N)
    local response_time=$(( (end_time - start_time) / 1000000 )) # Convert to milliseconds

    if [ "$response_time" -gt 1000 ]; then # More than 1 second
        log_warning "HTTP response time is slow: ${response_time}ms"
    else
        log_success "HTTP response time acceptable: ${response_time}ms"
    fi

    return 0
}

# Code Coverage (basic)

generate_coverage_report() {
    log "Generating code coverage report..."

    local coverage_file="${TEST_RESULTS_DIR}/coverage-${TIMESTAMP}.txt"

    {
        echo "Code Coverage Report"
        echo "Generated: $(date)"
        echo "===================="
        echo ""
        echo "Scripts tested:"
        ls -1 scripts/*.sh | wc -l
        echo ""
        echo "Functions tested: Manual assessment required"
        echo "Lines tested: Manual assessment required"
        echo ""
        echo "Coverage areas:"
        echo "- Shell script syntax validation"
        echo "- Docker configuration validation"
        echo "- Service startup validation"
        echo "- HTTP endpoint validation"
        echo "- DHCP service validation"
    } > "$coverage_file"

    log_success "Coverage report generated: $coverage_file"
}

# Main test execution

main() {
    log "=== Starting PXE Server Test Suite ==="
    log "Test run timestamp: $TIMESTAMP"

    # Create test results directory
    mkdir -p "$TEST_RESULTS_DIR"

    # Unit Tests
    log "Running Unit Tests..."
    run_test "Shell Syntax Check" "test_shell_syntax"
    run_test "Docker Configuration" "test_docker_config"
    run_test "File Permissions" "test_file_permissions"
    run_test "Configuration Files" "test_configuration_files"
    run_test "Backup/Restore Basic" "test_backup_restore"
    run_test "Health Check Logic" "test_health_check"

    # Integration Tests (only run if in container)
    if [ -f "/.dockerenv" ] || [ -n "$DOCKER_CONTAINER" ]; then
        log "Running Integration Tests..."
        run_test "Service Startup" "test_service_startup"
        run_test "HTTP Endpoints" "test_http_endpoints"
        run_test "DHCP Service" "test_dhcp_service"
        run_test "Performance" "test_performance"
    else
        log "Skipping integration tests (not running in container)"
    fi

    # Generate coverage report
    generate_coverage_report

    # Test Summary
    log ""
    log "=== Test Summary ==="
    log "Total tests: $TOTAL_TESTS"
    log "Passed: $PASSED_TESTS"
    log "Failed: $FAILED_TESTS"
    log "Success rate: $((PASSED_TESTS * 100 / TOTAL_TESTS))%"

    if [ "$FAILED_TESTS" -eq 0 ]; then
        log_success "All tests passed!"
        exit 0
    else
        log_error "$FAILED_TESTS test(s) failed"
        exit 1
    fi
}

# Run main function
main "$@"
