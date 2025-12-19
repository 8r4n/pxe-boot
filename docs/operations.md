# Operations Manual

This manual provides operational procedures for running and maintaining the PXE Boot Server in production environments.

## Daily Operations

### Monitoring

**Health Checks:**
```bash
# Quick status check
docker-compose ps

# Health check script
docker exec pxe-boot-server /usr/local/bin/healthcheck.sh

# Resource usage
docker stats pxe-boot-server
```

**Log Monitoring:**
```bash
# View recent logs
docker-compose logs -f --tail=50

# Monitor specific services
docker-compose logs | grep dhcpd
docker-compose logs | grep nginx
```

**Key Metrics to Monitor:**
- DHCP lease utilization
- HTTP request rates
- Error rates
- Disk space usage
- Network connectivity

### Backup Verification

```bash
# Test backup integrity
./scripts/backup.sh
ls -la /opt/pxe-backups/
tar -tzf /opt/pxe-backups/pxe-server-backup-*.tar.gz | head -20
```

## Weekly Maintenance

### Log Rotation

```bash
# Rotate application logs
docker-compose exec pxe-server logrotate /etc/logrotate.conf

# Archive old logs
find logs/ -name "*.log.*" -mtime +30 -delete
```

### Security Updates

```bash
# Update container image
docker-compose pull
docker-compose up -d

# Check for security updates
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasecurity/trivy image pxe-server:latest --exit-code 1
```

### Performance Tuning

```bash
# Check Nginx worker utilization
docker-compose exec pxe-server ps aux | grep nginx

# Monitor DHCP lease database
docker-compose exec pxe-server wc -l /var/lib/dhcpd/dhcpd.leases
```

## Monthly Procedures

### Capacity Planning

**DHCP Capacity:**
```bash
# Check lease utilization
TOTAL_IPS=200
USED_LEASES=$(docker-compose exec pxe-server wc -l < /var/lib/dhcpd/dhcpd.leases)
UTILIZATION=$((USED_LEASES * 100 / TOTAL_IPS))

echo "DHCP utilization: ${UTILIZATION}%"
if [ "$UTILIZATION" -gt 80 ]; then
    echo "WARNING: High DHCP utilization"
fi
```

**Storage Capacity:**
```bash
# Check disk usage
docker-compose exec pxe-server df -h /var/www/html

# Monitor image sizes
du -sh nginx-root/images/*
```

### Configuration Review

```bash
# Validate all configurations
docker-compose exec pxe-server dhcpd -t -cf /etc/dhcp/dhcpd.conf
docker-compose exec pxe-server nginx -t

# Check environment variables
docker-compose exec pxe-server env | grep -E '(DHCP|NGINX|PXE)_'
```

## Incident Response

### Service Failure

1. **Assess Impact:**
   ```bash
   # Check which services are down
   docker-compose ps
   curl -f http://localhost:8080/health || echo "HTTP down"
   ```

2. **Attempt Recovery:**
   ```bash
   # Restart services
   docker-compose restart

   # If that fails, rebuild
   docker-compose up -d --build
   ```

3. **Failover (if configured):**
   ```bash
   # Switch to backup PXE server
   # Update DHCP helper addresses on routers
   ```

### Security Incident

See [Security Guide](security.md) for detailed incident response procedures.

## Disaster Recovery

### Complete System Recovery

1. **Prepare Recovery Environment:**
   ```bash
   # Set up recovery server
   git clone <repository>
   cd pxe-boot
   cp .env.example .env
   # Edit .env with recovery settings
   ```

2. **Restore from Backup:**
   ```bash
   # Download latest backup
   scp backup-server:/opt/pxe-backups/latest.tar.gz .

   # Restore configuration
   ./scripts/restore.sh latest.tar.gz --restore-data
   ```

3. **Validate Recovery:**
   ```bash
   docker-compose up -d
   docker-compose ps
   curl http://localhost:8080/health
   ```

### Data Recovery Priority

1. **Critical (restore immediately):**
   - DHCP configuration
   - PXE boot files
   - Security certificates

2. **Important (restore within hours):**
   - Kickstart/preseed files
   - Custom configurations

3. **Optional (restore as needed):**
   - OS images (can be re-downloaded)
   - Log archives

## Performance Optimization

### DHCP Optimization

```bash
# Optimize lease times based on usage patterns
# Short leases for lab environments
default-lease-time 1800;  # 30 minutes

# Longer leases for production
default-lease-time 86400; # 24 hours
```

### HTTP Optimization

```nginx
# Enable gzip compression
gzip on;
gzip_types text/plain application/xml application/json;

# Optimize worker processes
worker_processes auto;
worker_connections 2048;

# Cache static files
location ~* \.(iso|img)$ {
    expires 30d;
    add_header Cache-Control "public, immutable";
}
```

### Container Optimization

```yaml
# Resource limits
deploy:
  resources:
    limits:
      cpus: '2.0'
      memory: 2G
    reservations:
      cpus: '0.5'
      memory: 512M
```

## Scaling Procedures

### Horizontal Scaling

```yaml
# Multiple PXE servers
services:
  pxe-server-1:
    # ... configuration
  pxe-server-2:
    # ... configuration

# Load balancer configuration
# Round-robin DNS or hardware load balancer
```

### Vertical Scaling

```yaml
# Increase resources for high load
deploy:
  resources:
    limits:
      cpus: '4.0'
      memory: 8G
```

## Compliance Monitoring

### Audit Logging

```bash
# Enable detailed audit logs
log_format audit '$remote_addr - $remote_user [$time_local] "$request" '
                 '$status $body_bytes_sent "$http_referer" '
                 '"$http_user_agent" "$http_x_forwarded_for"';

access_log /var/log/nginx/audit.log audit;
```

### Regular Audits

```bash
# Monthly security audit
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  docker/docker-bench-security

# Configuration compliance check
# Compare current config against security baseline
```

## Maintenance Windows

### Planned Maintenance

1. **Schedule Maintenance:**
   - Notify users 48 hours in advance
   - Schedule during low-usage periods

2. **Pre-Maintenance:**
   ```bash
   # Create backup
   ./scripts/backup.sh

   # Notify monitoring systems
   # Set maintenance mode
   ```

3. **During Maintenance:**
   ```bash
   # Stop services
   docker-compose down

   # Perform maintenance
   docker-compose pull
   docker-compose build --no-cache

   # Start services
   docker-compose up -d
   ```

4. **Post-Maintenance:**
   ```bash
   # Validate functionality
   ./scripts/healthcheck.sh

   # Clear maintenance mode
   # Notify users
   ```

### Emergency Maintenance

1. **Immediate Action:**
   ```bash
   # Assess situation
   docker-compose logs --tail=100

   # Quick fix if possible
   docker-compose restart
   ```

2. **Escalation:**
   - If service unavailable > 15 minutes, page on-call engineer
   - If data loss suspected, initiate disaster recovery

## Documentation Updates

### Change Management

```bash
# Document all changes
echo "$(date): Updated DHCP range to 192.168.1.200-250" >> CHANGELOG.md

# Update runbooks
# Update monitoring dashboards
# Update capacity planning documents
```

### Knowledge Base

- Maintain troubleshooting runbooks
- Document known issues and workarounds
- Keep contact information current
- Update emergency procedures regularly
