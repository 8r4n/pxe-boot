# PXE Boot Server - Production Dockerfile
# Multi-stage build for security and optimization

# Build stage for custom binaries and preparation
FROM rockylinux:9 AS builder

# Install build dependencies
RUN dnf update -y && \
    dnf install -y \
        gcc \
        make \
        wget \
        tar \
        gzip \
        xz \
        && \
    dnf clean all && \
    rm -rf /var/cache/dnf/*

# Download and prepare syslinux for PXE boot
RUN mkdir -p /build && \
    cd /build && \
    wget https://mirrors.edge.kernel.org/pub/linux/utils/boot/syslinux/syslinux-6.04-pre1.tar.xz && \
    tar -xf syslinux-6.04-pre1.tar.xz && \
    cd syslinux-6.04-pre1 && \
    make bios && \
    make install

# Runtime stage - minimal, secure image
FROM rockylinux:9

# Labels for metadata and security scanning
LABEL maintainer="PXE Boot Server Team" \
      description="Production PXE boot server container" \
      version="1.0.0" \
      org.opencontainers.image.source="https://github.com/yourorg/pxe-boot" \
      org.opencontainers.image.licenses="MIT"

# Install runtime dependencies with minimal footprint
RUN dnf update -y --security && \
    dnf install -y \
        dhcp-server \

        nginx \
        iproute \
        net-tools \
        bind-utils \
        procps-ng \
        psmisc \
        curl \
        wget \
        vim-minimal \
        less \
        && \
    dnf clean all && \
    rm -rf /var/cache/dnf/* && \
    # Remove unnecessary systemd services and files
    rm -rf /etc/systemd/system/*.wants/* && \
    rm -rf /lib/systemd/system/sysinit.target.wants/* && \
    rm -rf /lib/systemd/system/multi-user.target.wants/* && \
    rm -rf /lib/systemd/system/graphical.target.wants/* && \
    # Clean up package manager cache
    rm -rf /var/lib/dnf/history* /var/lib/dnf/yumdb/* /var/log/dnf* && \
    # Create necessary directories
    mkdir -p /var/www/html /var/log/pxe /run/nginx

# Copy syslinux files from builder stage for HTTP boot
# These will be copied to a temporary location and moved during startup
COPY --from=builder /usr/share/syslinux/pxelinux.0 /tmp/pxe-boot-files/
COPY --from=builder /usr/share/syslinux/menu.c32 /tmp/pxe-boot-files/
COPY --from=builder /usr/share/syslinux/ldlinux.c32 /tmp/pxe-boot-files/
COPY --from=builder /usr/share/syslinux/libcom32.c32 /tmp/pxe-boot-files/
COPY --from=builder /usr/share/syslinux/libutil.c32 /tmp/pxe-boot-files/

# Create non-root user for running services
RUN groupadd -r pxeuser && \
    useradd -r -g pxeuser -s /sbin/nologin pxeuser && \
    chown -R pxeuser:pxeuser /var/www/html /var/log/pxe /run/nginx && \
    chown pxeuser:pxeuser /var/lib/dhcpd /etc/dhcp/dhcpd.conf

# Copy configuration templates and scripts
COPY configs/ /etc/pxe/
COPY scripts/ /usr/local/bin/

# Make scripts executable
RUN chmod +x /usr/local/bin/*.sh && \
    chmod 644 /etc/pxe/*

# Copy health check script
COPY --chown=pxeuser:pxeuser healthcheck.sh /usr/local/bin/healthcheck.sh
RUN chmod +x /usr/local/bin/healthcheck.sh

# Configure nginx for non-root operation
RUN sed -i 's/user nginx;/user pxeuser;/' /etc/nginx/nginx.conf && \
    sed -i 's/pid \/run\/nginx.pid;/pid \/run\/nginx\/nginx.pid;/' /etc/nginx/nginx.conf

# Expose ports
EXPOSE 67/udp 8080/tcp

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD /usr/local/bin/healthcheck.sh

# Set working directory
WORKDIR /var/www/html

# Switch to non-root user
USER pxeuser

# Default command - start all services
CMD ["/usr/local/bin/start-services.sh"]

# Security hardening
RUN chmod 755 /usr/local/bin/* && \
    # Remove potentially dangerous files
    rm -f /bin/sh /bin/bash /usr/bin/python* /usr/bin/perl || true

# Final cleanup
RUN rm -rf /tmp/* /var/tmp/*
