# PXE Boot Server - Production Dockerfile
# Multi-stage build for security and optimization

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
    dnf install -y --allowerasing \
        dhcp-server \
        syslinux-tftpboot \
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
        gettext \
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
    mkdir -p /var/www/html /var/log/pxe /run/nginx /tmp/pxe-boot-files

# Create non-root user for running services
RUN groupadd -r pxeuser && \
    useradd -r -g pxeuser -s /sbin/nologin pxeuser && \
    chown -R pxeuser:pxeuser /var/www/html /var/log/pxe /run/nginx && \
    chown -R pxeuser:pxeuser /var/lib/dhcpd && \
    touch /etc/dhcp/dhcpd.conf /etc/nginx/nginx.conf && \
    chown pxeuser:pxeuser /etc/dhcp/dhcpd.conf /etc/nginx/nginx.conf

# Copy syslinux files for HTTP boot
# These will be copied to a temporary location and moved during startup
RUN mkdir -p /tmp/pxe-boot-files && \
    cp /tftpboot/pxelinux.0 /tmp/pxe-boot-files/ && \
    cp /tftpboot/menu.c32 /tmp/pxe-boot-files/ && \
    cp /tftpboot/ldlinux.c32 /tmp/pxe-boot-files/ && \
    cp /tftpboot/libcom32.c32 /tmp/pxe-boot-files/ && \
    cp /tftpboot/libutil.c32 /tmp/pxe-boot-files/ && \
    chown -R pxeuser:pxeuser /tmp/pxe-boot-files

# Copy configuration templates and scripts
COPY configs/ /etc/pxe/
COPY scripts/ /usr/local/bin/
COPY healthcheck.sh /usr/local/bin/

# Make scripts executable before changing ownership
RUN chmod +x /usr/local/bin/*.sh && \
    chmod 644 /etc/pxe/*

# Change ownership of files that need to be owned by pxeuser
RUN chown pxeuser:pxeuser /usr/local/bin/healthcheck.sh

# Configure nginx for non-root operation
RUN sed -i 's/user nginx;/user pxeuser;/' /etc/nginx/nginx.conf && \
    sed -i 's/pid \/run\/nginx.pid;/pid \/run\/nginx\/nginx.pid;/' /etc/nginx/nginx.conf

# Ensure config files have correct ownership (after all package installations)
RUN touch /etc/dhcp/dhcpd.conf /etc/nginx/nginx.conf /var/lib/dhcpd/dhcpd.leases && \
    chown pxeuser:pxeuser /etc/dhcp/dhcpd.conf /etc/nginx/nginx.conf /var/lib/dhcpd/dhcpd.leases && \
    chmod 755 /etc/dhcp

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

# Final cleanup (exclude pxe-boot-files which are needed by the application)
RUN find /tmp -mindepth 1 -not -path '/tmp/pxe-boot-files*' -delete && \
    rm -rf /var/tmp/*
