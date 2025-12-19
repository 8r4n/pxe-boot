# Security Guide

This guide covers security considerations, best practices, and hardening procedures for the PXE Boot Server.

## Security Architecture

The PXE Boot Server implements multiple layers of security:

```
┌─────────────────┐
│  Network Access │ ← Firewall rules, VLAN isolation
├─────────────────┤
│ Service Security│ ← Non-root execution, minimal attack surface
├─────────────────┤
│  Data Security  │ ← File permissions, access controls
├─────────────────┤
│ Audit & Logging │ ← Comprehensive logging, monitoring
└─────────────────┘
```

## Network Security

### DHCP Security

**Risk:** Rogue DHCP servers can provide malicious configurations

**Mitigations:**

1. **Network Segmentation:**
   ```bash
   # Use dedicated VLAN for PXE booting
   # Configure switch port security
   # Enable DHCP snooping on switches
   ```

2. **DHCP Configuration Hardening:**
   ```bash
   # Limit DHCP to specific MAC addresses
   host allowed-client {
       hardware ethernet 00:11:22:33:44:55;
       fixed-address 192.168.1.50;
   }

   # Deny unknown clients
   deny unknown-clients;
   ```

3. **DHCP Lease Limits:**
   ```bash
   # Set reasonable lease times
   default-lease-time 3600;  # 1 hour
   max-lease-time 7200;     # 2 hours
   ```

### HTTP Security

**Risk:** Unauthorized access to boot images and configurations

**Mitigations:**

1. **Access Control:**
   ```nginx
   # Restrict access to sensitive areas
   location /kickstart/ {
       allow 192.168.1.0/24;
       deny all;
   }

   # Rate limiting
   limit_req_zone $binary_remote_addr zone=downloads:10m rate=1r/s;
   location /images/ {
       limit_req zone=downloads burst=5 nodelay;
   }
   ```

2. **HTTPS Configuration:**
   ```nginx
   # Enable HTTPS for production
   server {
       listen 8443 ssl http2;
       ssl_certificate /etc/ssl/certs/pxe-server.crt;
       ssl_certificate_key /etc/ssl/private/pxe-server.key;

       # SSL hardening
       ssl_protocols TLSv1.2 TLSv1.3;
       ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512;
       ssl_prefer_server_ciphers off;
   }
   ```

## Container Security

### Docker Security

**Current Security Features:**

- **Non-root user execution:** Services run as `pxeuser`
- **Minimal attack surface:** Only essential packages installed
- **Security options:** `no-new-privileges`, dropped capabilities
- **Read-only mounts:** Configuration files mounted read-only

**Additional Hardening:**

1. **Security Options:**
   ```yaml
   services:
     pxe-server:
       security_opt:
         - no-new-privileges:true
       cap_drop:
         - ALL
       cap_add:
         - NET_BIND_SERVICE
         - NET_RAW
       read_only: true
       tmpfs:
         - /tmp
         - /run
         - /var/log/pxe
   ```

2. **Image Scanning:**
   ```bash
   # Scan for vulnerabilities
   docker run --rm -v /var/run/docker.sock:/var/run/docker.sock
     aquasecurity/trivy image pxe-server:latest

   # Security audit
   docker run --rm -v /var/run/docker.sock:/var/run/docker.sock
     docker/docker-bench-security
   ```

### Secrets Management

**Environment Variables:**
- Store sensitive configuration in Docker secrets
- Use external secret management (HashiCorp Vault, AWS Secrets Manager)
- Rotate credentials regularly

**Secret Configuration:**
```yaml
services:
  pxe-server:
    secrets:
      - dhcp_keys
      - ssl_certs

secrets:
  dhcp_keys:
    file: ./secrets/dhcp-keys.env
  ssl_certs:
    file: ./secrets/ssl-certs.tar.gz
```

## File System Security

### Permission Model

```
/
├── var/www/html/        # 755 pxeuser:pxeuser (web root)
│   ├── pxelinux.0       # 644 pxeuser:pxeuser (boot loader)
│   ├── pxelinux.cfg/    # 755 pxeuser:pxeuser (config dir)
│   └── images/          # 755 pxeuser:pxeuser (OS images)
├── var/lib/dhcpd/       # 700 pxeuser:pxeuser (DHCP data)
├── var/log/pxe/         # 755 pxeuser:pxeuser (logs)
└── etc/pxe/             # 644 root:root (read-only configs)
```

### File Integrity

**Monitoring File Changes:**
```bash
# Monitor critical files
docker-compose exec pxe-server find /var/www/html -type f -exec sha256sum {} \; > baseline.txt

# Check for changes
docker-compose exec pxe-server find /var/www/html -type f -exec sha256sum {} \; | diff baseline.txt -
```

## Authentication & Authorization

### Client Authentication

**MAC Address Whitelisting:**
```bash
# Only allow specific clients
host workstation01 {
    hardware ethernet 00:11:22:33:44:55;
    fixed-address 192.168.1.100;
    option host-name "workstation01";
}
```

**IP-based Access Control:**
```nginx
# Allow only specific networks
location / {
    allow 192.168.1.0/24;
    allow 10.0.0.0/8;
    deny all;
}
```

### Administrative Access

**Secure Remote Access:**
```bash
# Use SSH bastion host for administration
# Disable direct container access
# Implement role-based access control
```

## Logging & Monitoring

### Security Event Logging

**DHCP Security Events:**
```bash
# Log DHCP events
log-facility local7;

on commit {
    log(info, concat("DHCPACK: ", binary-to-ascii(10, 8, ".", leased-address),
                     " to ", binary-to-ascii(16, 8, ":", substring(hardware, 1, 6))));
}
```

**HTTP Security Events:**
```nginx
log_format security '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for" '
                    'rt=$request_time ua="$upstream_addr" '
                    'host="$host" sn="$server_name" '
                    'uri="$uri" method="$request_method"';

access_log /var/log/nginx/security.log security;
```

### Intrusion Detection

**Monitor for Suspicious Activity:**
```bash
# Check for unusual DHCP requests
docker-compose logs pxe-server | grep "DHCPDISCOVER" | awk '{print $1}' | sort | uniq -c | sort -nr

# Monitor failed HTTP requests
docker-compose logs pxe-server | grep '" 404 ' | tail -20

# Alert on high error rates
ERROR_RATE=$(docker-compose logs pxe-server --since 1h | grep -c ERROR)
if [ "$ERROR_RATE" -gt 100 ]; then
    echo "High error rate detected: $ERROR_RATE errors/hour"
fi
```

## Incident Response

### Security Incident Procedure

1. **Detection:**
   - Monitor logs for suspicious activity
   - Set up alerts for security events
   - Regular security scans

2. **Containment:**
   ```bash
   # Isolate affected systems
   docker-compose stop

   # Block malicious IPs
   iptables -A INPUT -s MALICIOUS_IP -j DROP
   ```

3. **Investigation:**
   ```bash
   # Collect evidence
   docker-compose logs > incident_logs.txt
   cp -r logs/ incident_logs/

   # Analyze DHCP leases
   cat /var/lib/dhcpd/dhcpd.leases | grep -A 5 -B 5 MALICIOUS_MAC
   ```

4. **Recovery:**
   ```bash
   # Restore from backup
   ./scripts/restore.sh backup.tar.gz

   # Update security configurations
   # Patch vulnerabilities
   ```

5. **Lessons Learned:**
   - Document incident
   - Update security procedures
   - Implement preventive measures

## Compliance Considerations

### Security Standards

**Applicable Standards:**
- **NIST SP 800-53:** Security controls for information systems
- **ISO 27001:** Information security management
- **PCI DSS:** If handling payment data (unlikely for PXE)

**Implementation Checklist:**
- [ ] Network segmentation implemented
- [ ] Access controls configured
- [ ] Encryption enabled for sensitive data
- [ ] Audit logging enabled
- [ ] Regular security assessments
- [ ] Incident response plan documented

### Audit Requirements

**Logging Requirements:**
```bash
# Ensure all security events are logged
# Retain logs for minimum 90 days
# Implement log rotation and archival

logrotate_conf = """
/var/log/pxe/*.log {
    daily
    rotate 90
    compress
    missingok
    notifempty
}
"""
```

## Best Practices

### Operational Security

1. **Regular Updates:**
   ```bash
   # Update container images
   docker-compose pull
   docker-compose up -d

   # Update base OS packages
   docker-compose exec pxe-server dnf update -y --security
   ```

2. **Configuration Management:**
   - Use version control for all configurations
   - Test changes in staging environment
   - Document all security-related changes

3. **Backup Security:**
   ```bash
   # Encrypt backups
   ./scripts/backup.sh | gpg -c > backup.tar.gz.gpg

   # Store backups securely
   # Implement backup integrity checks
   ```

### Performance vs Security

**Security Impact Assessment:**
- Rate limiting may impact legitimate users during large deployments
- Strict access controls may complicate administration
- Encryption adds computational overhead

**Balance Considerations:**
```nginx
# Graduated rate limiting
limit_req_zone $binary_remote_addr zone=slow:10m rate=10r/s;
limit_req_zone $binary_remote_addr zone=fast:10m rate=100r/s;

location /health { limit_req zone=fast; }
location /images { limit_req zone=slow burst=20; }
```

## Security Testing

### Vulnerability Assessment

**Regular Testing:**
```bash
# Container vulnerability scanning
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock
  aquasecurity/trivy image pxe-server:latest

# Network vulnerability scanning
nmap -sV -p 67,8080 <target-ip>

# Web application scanning
nikto -h http://localhost:8080
```

### Penetration Testing

**Safe Testing Boundaries:**
- Test only in isolated environments
- Obtain explicit permission
- Document all testing activities
- Restore systems after testing

**Testing Checklist:**
- [ ] DHCP server vulnerability assessment
- [ ] HTTP server security testing
- [ ] Container escape attempts
- [ ] Network segmentation verification
- [ ] Access control validation
