#!/bin/bash
# PXE Server Restore Script
# Restores configurations and data from backup

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BACKUP_ROOT="${BACKUP_ROOT:-/opt/pxe-backups}"

# Logging
LOG_FILE="${BACKUP_ROOT}/restore.log"
TIMESTAMP_FMT=$(date '+%Y-%m-%d %H:%M:%S')

log() {
    echo "[$TIMESTAMP_FMT] $1" | tee -a "$LOG_FILE"
}

error_exit() {
    log "ERROR: $1"
    exit 1
}

# Validate backup archive
validate_backup() {
    local backup_file="$1"

    if [ ! -f "$backup_file" ]; then
        error_exit "Backup file not found: $backup_file"
    fi

    log "Validating backup archive: $backup_file"

    # Test archive integrity
    if ! tar -tzf "$backup_file" >/dev/null 2>&1; then
        error_exit "Backup archive is corrupted or invalid"
    fi

    # Check for manifest
    if ! tar -tf "$backup_file" | grep -q "manifest.txt"; then
        log "Warning: No manifest found in backup"
    else
        log "Manifest found, extracting for verification..."
        local temp_dir
        temp_dir=$(mktemp -d)
        tar -xzf "$backup_file" -C "$temp_dir" "*/manifest.txt" 2>/dev/null || true
        if [ -f "$temp_dir"/*/manifest.txt ]; then
            log "Backup manifest:"
            cat "$temp_dir"/*/manifest.txt | head -20
        fi
        rm -rf "$temp_dir"
    fi

    log "Backup validation successful"
}

# Create restore point (backup current state)
create_restore_point() {
    log "Creating restore point of current state..."

    local restore_point="${PROJECT_ROOT}/.restore-point-$(date +%Y%m%d_%H%M%S)"

    # Backup critical files
    mkdir -p "$restore_point"

    local critical_files=(
        "docker-compose.yml"
        "Dockerfile"
        ".env"
    )

    for file in "${critical_files[@]}"; do
        if [ -f "$PROJECT_ROOT/$file" ]; then
            cp "$PROJECT_ROOT/$file" "$restore_point/"
            log "Saved restore point for: $file"
        fi
    done

    # Backup configuration directories
    if [ -d "$PROJECT_ROOT/configs" ]; then
        cp -r "$PROJECT_ROOT/configs" "$restore_point/"
        log "Saved restore point for: configs/"
    fi

    if [ -d "$PROJECT_ROOT/scripts" ]; then
        cp -r "$PROJECT_ROOT/scripts" "$restore_point/"
        log "Saved restore point for: scripts/"
    fi

    log "Restore point created: $restore_point"

    # Store restore point location for potential rollback
    echo "$restore_point" > "${PROJECT_ROOT}/.last-restore-point"
}

# Extract backup
extract_backup() {
    local backup_file="$1"
    local extract_dir

    extract_dir=$(mktemp -d)
    log "Extracting backup to temporary directory: $extract_dir"

    if ! tar -xzf "$backup_file" -C "$extract_dir"; then
        rm -rf "$extract_dir"
        error_exit "Failed to extract backup archive"
    fi

    # Find the actual backup directory (should be the only subdirectory)
    local backup_content
    backup_content=$(find "$extract_dir" -mindepth 1 -maxdepth 1 -type d | head -1)

    if [ -z "$backup_content" ]; then
        rm -rf "$extract_dir"
        error_exit "No backup content found in archive"
    fi

    log "Backup extracted successfully"
    echo "$backup_content"
}

# Restore configurations
restore_configs() {
    local backup_dir="$1"

    log "Restoring configuration files..."

    # Stop services before restore
    if [ "$STOP_SERVICES" = "true" ]; then
        log "Stopping PXE services..."
        cd "$PROJECT_ROOT"
        docker-compose down 2>/dev/null || true
    fi

    # Restore core configuration files
    local config_files=(
        "docker-compose.yml"
        "Dockerfile"
        ".env"
        ".env.example"
    )

    for file in "${config_files[@]}"; do
        if [ -f "$backup_dir/configs/$file" ]; then
            cp "$backup_dir/configs/$file" "$PROJECT_ROOT/$file"
            log "Restored: $file"
        elif [ -f "$backup_dir/$file" ]; then
            cp "$backup_dir/$file" "$PROJECT_ROOT/$file"
            log "Restored: $file"
        else
            log "Warning: $file not found in backup, skipping"
        fi
    done

    # Restore configuration directories
    if [ -d "$backup_dir/configs" ]; then
        if [ -d "$PROJECT_ROOT/configs" ]; then
            cp -r "$backup_dir/configs"/* "$PROJECT_ROOT/configs/" 2>/dev/null || true
        else
            cp -r "$backup_dir/configs" "$PROJECT_ROOT/"
        fi
        log "Restored: configs directory"
    fi

    if [ -d "$backup_dir/scripts" ]; then
        if [ -d "$PROJECT_ROOT/scripts" ]; then
            cp -r "$backup_dir/scripts"/* "$PROJECT_ROOT/scripts/" 2>/dev/null || true
        else
            cp -r "$backup_dir/scripts" "$PROJECT_ROOT/"
        fi
        log "Restored: scripts directory"
    fi
}

# Restore PXE data (optional)
restore_pxe_data() {
    local backup_dir="$1"

    if [ "$RESTORE_DATA" = "true" ]; then
        log "Restoring PXE boot data..."

        # Restore kickstart files
        if [ -d "$backup_dir/data/kickstart" ]; then
            mkdir -p "$PROJECT_ROOT/nginx-root"
            cp -r "$backup_dir/data/kickstart" "$PROJECT_ROOT/nginx-root/"
            log "Restored: kickstart files"
        fi

        # Restore preseed files
        if [ -d "$backup_dir/data/preseed" ]; then
            mkdir -p "$PROJECT_ROOT/nginx-root"
            cp -r "$backup_dir/data/preseed" "$PROJECT_ROOT/nginx-root/"
            log "Restored: preseed files"
        fi

        # Note: OS images are not restored by default
        # Uncomment to restore OS images
        # if [ -d "$backup_dir/data/images" ]; then
        #     log "Restoring OS images (this may take a while)..."
        #     mkdir -p "$PROJECT_ROOT/nginx-root"
        #     cp -r "$backup_dir/data/images" "$PROJECT_ROOT/nginx-root/"
        #     log "Restored: OS images"
        # fi
    else
        log "Skipping PXE data restore (--restore-data not specified)"
    fi
}

# Restore logs (optional)
restore_logs() {
    local backup_dir="$1"

    if [ "$RESTORE_LOGS" = "true" ] && [ -d "$backup_dir/logs" ]; then
        log "Restoring log files..."
        cp -r "$backup_dir/logs" "$PROJECT_ROOT/"
        log "Restored: log files"
    fi
}

# Validate restore
validate_restore() {
    log "Validating restore..."

    # Check for critical files
    local critical_files=(
        "docker-compose.yml"
        "Dockerfile"
    )

    for file in "${critical_files[@]}"; do
        if [ ! -f "$PROJECT_ROOT/$file" ]; then
            error_exit "Critical file missing after restore: $file"
        fi
    done

    # Validate configurations
    log "Validating configurations..."
    cd "$PROJECT_ROOT"

    # Test docker-compose configuration
    if ! docker-compose config >/dev/null 2>&1; then
        log "Warning: docker-compose configuration may be invalid"
    fi

    log "Restore validation complete"
}

# Restart services
restart_services() {
    if [ "$RESTART_SERVICES" = "true" ]; then
        log "Restarting PXE services..."
        cd "$PROJECT_ROOT"

        # Rebuild if requested
        if [ "$REBUILD_CONTAINER" = "true" ]; then
            log "Rebuilding container..."
            docker-compose build --no-cache
        fi

        # Start services
        if docker-compose up -d; then
            log "Services restarted successfully"
        else
            error_exit "Failed to restart services"
        fi
    fi
}

# Cleanup temporary files
cleanup() {
    local temp_dir="$1"

    if [ -d "$temp_dir" ]; then
        rm -rf "$temp_dir"
        log "Cleaned up temporary files"
    fi
}

# Rollback function
rollback() {
    local restore_point="$1"

    if [ -f "${PROJECT_ROOT}/.last-restore-point" ]; then
        restore_point=$(cat "${PROJECT_ROOT}/.last-restore-point")
    fi

    if [ -d "$restore_point" ]; then
        log "Rolling back to restore point: $restore_point"

        # Restore from restore point
        local critical_files=(
            "docker-compose.yml"
            "Dockerfile"
            ".env"
        )

        for file in "${critical_files[@]}"; do
            if [ -f "$restore_point/$file" ]; then
                cp "$restore_point/$file" "$PROJECT_ROOT/$file"
                log "Rolled back: $file"
            fi
        done

        # Restore directories
        if [ -d "$restore_point/configs" ]; then
            cp -r "$restore_point/configs" "$PROJECT_ROOT/"
            log "Rolled back: configs/"
        fi

        if [ -d "$restore_point/scripts" ]; then
            cp -r "$restore_point/scripts" "$PROJECT_ROOT/"
            log "Rolled back: scripts/"
        fi

        log "Rollback complete"
    else
        error_exit "No restore point available for rollback"
    fi
}

# Main restore function
main() {
    local backup_file="$1"

    if [ -z "$backup_file" ]; then
        error_exit "Backup file not specified. Usage: $0 <backup-file.tar.gz>"
    fi

    log "=== Starting PXE Server Restore ==="
    log "Project root: $PROJECT_ROOT"
    log "Backup file: $backup_file"

    # Validate backup
    validate_backup "$backup_file"

    # Create restore point
    create_restore_point

    # Extract backup
    local backup_dir
    backup_dir=$(extract_backup "$backup_file")

    # Perform restore
    restore_configs "$backup_dir"
    restore_pxe_data "$backup_dir"
    restore_logs "$backup_dir"

    # Validate and restart
    validate_restore
    restart_services

    # Cleanup
    cleanup "$(dirname "$backup_dir")"

    log "=== PXE Server Restore Complete ==="

    if [ "$RESTART_SERVICES" = "true" ]; then
        log "Services should now be running. Check with: docker-compose ps"
    else
        log "Services not restarted. Run 'docker-compose up -d' to start them."
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --backup-root)
            BACKUP_ROOT="$2"
            shift 2
            ;;
        --restore-data)
            RESTORE_DATA=true
            shift
            ;;
        --restore-logs)
            RESTORE_LOGS=true
            shift
            ;;
        --stop-services)
            STOP_SERVICES=true
            shift
            ;;
        --restart-services)
            RESTART_SERVICES=true
            shift
            ;;
        --rebuild)
            REBUILD_CONTAINER=true
            shift
            ;;
        --rollback)
            log "Performing rollback..."
            rollback
            exit 0
            ;;
        --help)
            cat << EOF
PXE Server Restore Script

Usage: $0 <backup-file.tar.gz> [OPTIONS]

Options:
    --restore-data       Restore PXE boot data (kickstart, preseed, menus)
    --restore-logs       Restore log files
    --stop-services      Stop services before restore (default: false)
    --restart-services   Restart services after restore (default: false)
    --rebuild           Rebuild container during restart
    --rollback          Rollback to last restore point
    --help              Show this help message

Environment Variables:
    BACKUP_ROOT         Backup root directory (default: /opt/pxe-backups)
    RESTORE_DATA        Same as --restore-data
    RESTORE_LOGS        Same as --restore-logs
    STOP_SERVICES       Same as --stop-services
    RESTART_SERVICES    Same as --restart-services
    REBUILD_CONTAINER   Same as --rebuild

Examples:
    $0 pxe-server-backup-20231219.tar.gz --restore-data --restart-services
    $0 latest-backup.tar.gz --stop-services --rebuild
    $0 --rollback
EOF
            exit 0
            ;;
        *)
            # If it looks like a backup file, use it
            if [[ "$1" == *.tar.gz ]]; then
                break
            else
                error_exit "Unknown option: $1"
            fi
            ;;
    esac
done

# Get backup file
BACKUP_FILE="$1"

if [ -z "$BACKUP_FILE" ]; then
    error_exit "Backup file not specified"
fi

# Convert relative path to absolute if needed
if [[ "$BACKUP_FILE" != /* ]]; then
    BACKUP_FILE="${BACKUP_ROOT}/${BACKUP_FILE}"
fi

# Run main function
main "$BACKUP_FILE"
