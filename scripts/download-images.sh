#!/bin/bash
# Download PXE Images Script for PXE Boot Server
# Downloads kernel and initrd images for supported distributions

set -e

# Configuration
LOG_DIR="/var/log/pxe"
SCRIPT_LOG="$LOG_DIR/download.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
HTTP_IMAGES_DIR="/var/www/html/images"

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

# Create directories for images
setup_directories() {
    log "Setting up image directories..."

    mkdir -p "$HTTP_IMAGES_DIR"

    # Create subdirectories for each distribution
    for dist in rhel9 rhel10 rocky8 rocky9 fedora41 fedora42; do
        mkdir -p "$HTTP_IMAGES_DIR/$dist"
    done

    log "Image directories setup complete"
}

# Download with retry logic
download_with_retry() {
    local url="$1"
    local output="$2"
    local max_retries=3
    local retry_count=0

    while [ $retry_count -lt $max_retries ]; do
        log "Downloading $url (attempt $((retry_count + 1))/$max_retries)..."

        if curl -L --fail --silent --show-error -o "$output" "$url"; then
            log "Successfully downloaded $url"
            return 0
        else
            retry_count=$((retry_count + 1))
            if [ $retry_count -lt $max_retries ]; then
                log "Download failed, retrying in 5 seconds..."
                sleep 5
            fi
        fi
    done

    error_exit "Failed to download $url after $max_retries attempts"
}

# Copy file to HTTP directory
copy_to_directories() {
    local source="$1"
    local filename="$2"
    local dist="$3"

    cp "$source" "$HTTP_IMAGES_DIR/$dist/$filename"
    log "Copied $filename to HTTP directory for $dist"
}

# Download Rocky Linux images
download_rocky() {
    local version="$1"
    local temp_dir=$(mktemp -d)

    log "Downloading Rocky Linux $version images..."

    # Rocky Linux base URL
    local base_url="https://download.rockylinux.org/pub/rocky/$version/images/x86_64"

    # Download kernel and initrd
    download_with_retry "$base_url/vmlinuz" "$temp_dir/vmlinuz"
    download_with_retry "$base_url/initrd.img" "$temp_dir/initrd.img"

    # Copy to final locations
    copy_to_directories "$temp_dir/vmlinuz" "vmlinuz" "rocky$version"
    copy_to_directories "$temp_dir/initrd.img" "initrd.img" "rocky$version"

    # Clean up
    rm -rf "$temp_dir"

    log "Rocky Linux $version images downloaded successfully"
}

# Download Fedora images
download_fedora() {
    local version="$1"
    local temp_dir=$(mktemp -d)

    log "Downloading Fedora $version images..."

    # Fedora base URL for netinstall images
    local base_url="https://download.fedoraproject.org/pub/fedora/linux/releases/$version/Everything/x86_64/os/images/pxeboot"

    # Download kernel and initrd
    download_with_retry "$base_url/vmlinuz" "$temp_dir/vmlinuz"
    download_with_retry "$base_url/initrd.img" "$temp_dir/initrd.img"

    # Copy to final locations
    copy_to_directories "$temp_dir/vmlinuz" "vmlinuz" "fedora$version"
    copy_to_directories "$temp_dir/initrd.img" "initrd.img" "fedora$version"

    # Clean up
    rm -rf "$temp_dir"

    log "Fedora $version images downloaded successfully"
}

# Download RHEL images (requires subscription or custom URL)
download_rhel() {
    local version="$1"

    log "Note: RHEL $version images require Red Hat subscription access"
    log "Please download RHEL $version kernel and initrd.img manually to:"
    log "  - HTTP: $HTTP_IMAGES_DIR/rhel$version/"
    log "Expected files: vmlinuz, initrd.img"
    log ""

    # Create placeholder files to indicate manual download needed
    echo "# Manual download required - RHEL $version requires Red Hat subscription" > "$HTTP_IMAGES_DIR/rhel$version/README.txt"

    log "Created placeholder files for RHEL $version - manual download required"
}

# Verify downloaded files
verify_downloads() {
    log "Verifying downloaded images..."

    local missing_files=()

    # Check Rocky Linux images
    for version in 8 9; do
        for file in vmlinuz initrd.img; do
            if [ ! -f "$HTTP_IMAGES_DIR/rocky$version/$file" ]; then
                missing_files+=("rocky$version/$file")
            fi
        done
    done

    # Check Fedora images
    for version in 41 42; do
        for file in vmlinuz initrd.img; do
            if [ ! -f "$HTTP_IMAGES_DIR/fedora$version/$file" ]; then
                missing_files+=("fedora$version/$file")
            fi
        done
    done

    # Check RHEL images (allow missing since they require manual download)
    for version in 9 10; do
        if [ ! -f "$HTTP_IMAGES_DIR/rhel$version/vmlinuz" ] && [ ! -f "$HTTP_IMAGES_DIR/rhel$version/README.txt" ]; then
            log "WARNING: RHEL $version images not found (expected for manual download)"
        fi
    done

    if [ ${#missing_files[@]} -gt 0 ]; then
        log "WARNING: Missing files detected:"
        for file in "${missing_files[@]}"; do
            log "  - $file"
        done
    else
        log "All expected files are present"
    fi
}

# Main download function
main() {
    log "=== Starting PXE Image Download ==="

    setup_directories

    # Download Rocky Linux images
    download_rocky "8"
    download_rocky "9"

    # Download Fedora images
    download_fedora "41"
    download_fedora "42"

    # Handle RHEL images (manual download required)
    download_rhel "9"
    download_rhel "10"

    # Verify downloads
    verify_downloads

    log "=== PXE Image Download Complete ==="
    log "Downloaded images for: Rocky Linux 8, 9; Fedora 41, 42"
    log "RHEL images require manual download due to subscription requirements"
    log "Images are available in:"
    log "  - HTTP: $HTTP_IMAGES_DIR"
}

# Run main function
main "$@"
