#!/bin/bash
# PXE Server Backup Script
# Creates comprehensive backups of configurations and data

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BACKUP_ROOT="${BACKUP_ROOT:-/opt/pxe-backups}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="pxe-server-backup-${TIMESTAMP}"
BACKUP_DIR="${BACKUP_ROOT}/${BACKUP_NAME}"

# Logging
LOG_FILE="${BACKUP_ROOT}/backup.log"
TIMESTAMP_FMT=$(date '+%Y-%m-%d %H:%M:%S')

log() {
    echo "[$TIMESTAMP_FMT] $1" | tee -a "$LOG_FILE"
}

error_exit() {
    log "ERROR: $1"
    exit 1
}

# Create backup directory structure
create_backup_structure() {
    log "Creating backup directory structure..."
    mkdir -p "$BACKUP_DIR"
    mkdir -p "$BACKUP_DIR/configs"
    mkdir -p "$BACKUP_DIR/scripts"
    mkdir -p "$BACKUP_DIR/data"
    mkdir -p "$BACKUP_DIR/logs"
    log "Backup structure created at $BACKUP_DIR"
}

# Backup configurations
backup_configs() {
    log "Backing up configuration files..."

    # Core configuration files
    local config_files=(
        "docker-compose.yml"
        "Dockerfile"
        ".env"
        ".env.example"
    )

    for file in "${config_files[@]}"; do
        if [ -f "$PROJECT_ROOT/$file" ]; then
            cp "$PROJECT_ROOT/$file" "$BACKUP_DIR/configs/"
            log "Backed up: $file"
        else
            log "Warning: $file not found, skipping"
        fi
    done

    # Configuration directories
    if [ -d "$PROJECT_ROOT/configs" ]; then
        cp -r "$PROJECT_ROOT/configs" "$BACKUP_DIR/"
        log "Backed up: configs directory"
    fi

    if [ -d "$PROJECT_ROOT/scripts" ]; then
        cp -r "$PROJECT_ROOT/scripts" "$BACKUP_DIR/"
        log "Backed up: scripts directory"
    fi
}

# Backup PXE boot data (optional, can be large)
backup_pxe_data() {
    log "Backing up PXE boot data..."

    # PXE boot menu configurations (from host-mounted directory)
    if [ -d "$PROJECT_ROOT/nginx-root/pxelinux.cfg" ]; then
        cp -r "$PROJECT_ROOT/nginx-root/pxelinux.cfg" "$BACKUP_DIR/data/"
        log "Backed up: PXE boot menus"
    fi

    # Kickstart and preseed files
    if [ -d "$PROJECT_ROOT/nginx-root/kickstart" ]; then
        cp -r "$PROJECT_ROOT/nginx-root/kickstart" "$BACKUP_DIR/data/"
        log "Backed up: kickstart files"
    fi

    if [ -d "$PROJECT_ROOT/nginx-root/preseed" ]; then
        cp -r "$PROJECT_ROOT/nginx-root/preseed" "$BACKUP_DIR/data/"
        log "Backed up: preseed files"
    fi

    # Note: OS images are not backed up by default due to size
    # Uncomment the following lines to include OS images in backup
    # if [ -d "$PROJECT_ROOT/nginx-root/images" ]; then
    #     log "Backing up OS images (this may take a while)..."
    #     cp -r "$PROJECT_ROOT/nginx-root/images" "$BACKUP_DIR/data/"
    #     log "Backed up: OS images"
    # fi
}

# Backup logs (optional)
backup_logs() {
    if [ "$BACKUP_LOGS" = "true" ]; then
        log "Backing up log files..."
        if [ -d "$PROJECT_ROOT/logs" ]; then
            cp -r "$PROJECT_ROOT/logs" "$BACKUP_DIR/"
            log "Backed up: log files"
        fi
    fi
}

# Create backup manifest
create_manifest() {
    log "Creating backup manifest..."
    local manifest="$BACKUP_DIR/manifest.txt"

    cat > "$manifest" << EOF
PXE Server Backup Manifest
Created: $TIMESTAMP_FMT
Backup Version: 1.0
Project Root: $PROJECT_ROOT
Backup Location: $BACKUP_DIR

Included Components:
$(find "$BACKUP_DIR" -type f | wc -l) files
$(du -sh "$BACKUP_DIR" | cut -f1) total size

Contents:
$(find "$BACKUP_DIR" -type f | sort)

System Information:
$(uname -a)
$(docker --version 2>/dev/null || echo "Docker not available")
$(docker-compose --version 2>/dev/null || echo "Docker Compose not available")

Backup created by: $(whoami)@$(hostname)
EOF

    log "Manifest created: $manifest"
}

# Compress backup
compress_backup() {
    log "Compressing backup..."
    local archive="${BACKUP_ROOT}/${BACKUP_NAME}.tar.gz"

    cd "$BACKUP_ROOT"
    tar -czf "$archive" "$BACKUP_NAME"

    # Remove uncompressed backup if compression successful
    if [ -f "$archive" ] && [ -s "$archive" ]; then
        rm -rf "$BACKUP_DIR"
        log "Backup compressed: $archive"
        log "Compressed size: $(du -sh "$archive" | cut -f1)"
    else
        error_exit "Backup compression failed"
    fi
}

# Cleanup old backups
cleanup_old_backups() {
    local max_backups=${MAX_BACKUPS:-10}

    log "Cleaning up old backups (keeping last $max_backups)..."

    # List backups by modification time, keep newest max_backups
    local old_backups
    old_backups=$(ls -t "${BACKUP_ROOT}"/*.tar.gz 2>/dev/null | tail -n +$((max_backups + 1)))

    if [ -n "$old_backups" ]; then
        echo "$old_backups" | while read -r backup; do
            rm -f "$backup"
            log "Removed old backup: $backup"
        done
    else
        log "No old backups to clean up"
    fi
}

# Validate backup
validate_backup() {
    log "Validating backup integrity..."

    local archive="${BACKUP_ROOT}/${BACKUP_NAME}.tar.gz"

    if [ ! -f "$archive" ]; then
        error_exit "Backup archive not found: $archive"
    fi

    # Test archive integrity
    if ! tar -tzf "$archive" >/dev/null 2>&1; then
        error_exit "Backup archive is corrupted"
    fi

    log "Backup validation successful"
}

# Main backup function
main() {
    log "=== Starting PXE Server Backup ==="
    log "Project root: $PROJECT_ROOT"
    log "Backup root: $BACKUP_ROOT"

    # Check if running as root (recommended for full backup)
    if [ "$EUID" -eq 0 ]; then
        log "Running as root - full backup capabilities enabled"
    else
        log "Warning: Not running as root - some files may not be accessible"
    fi

    create_backup_structure
    backup_configs
    backup_pxe_data
    backup_logs
    create_manifest
    compress_backup
    cleanup_old_backups
    validate_backup

    log "=== PXE Server Backup Complete ==="
    log "Backup location: ${BACKUP_ROOT}/${BACKUP_NAME}.tar.gz"
    log "Total backup size: $(du -sh "${BACKUP_ROOT}/${BACKUP_NAME}.tar.gz" | cut -f1)"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --backup-root)
            BACKUP_ROOT="$2"
            shift 2
            ;;
        --include-logs)
            BACKUP_LOGS=true
            shift
            ;;
        --max-backups)
            MAX_BACKUPS="$2"
            shift 2
            ;;
        --help)
            cat << EOF
PXE Server Backup Script

Usage: $0 [OPTIONS]

Options:
    --backup-root DIR     Backup root directory (default: /opt/pxe-backups)
    --include-logs        Include log files in backup
    --max-backups NUM     Maximum number of backups to keep (default: 10)
    --help               Show this help message

Environment Variables:
    BACKUP_ROOT          Same as --backup-root
    BACKUP_LOGS          Same as --include-logs
    MAX_BACKUPS          Same as --max-backups

Examples:
    $0
    $0 --backup-root /mnt/backups --include-logs
    BACKUP_ROOT=/tmp/backups $0
EOF
            exit 0
            ;;
        *)
            error_exit "Unknown option: $1"
            ;;
    esac
done

# Run main function
main "$@"
