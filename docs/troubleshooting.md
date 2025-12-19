# Troubleshooting Guide

This guide provides solutions to common issues encountered when deploying and operating the PXE Boot Server.

## Quick Diagnosis

Run these commands to quickly diagnose issues:

```bash
# Check container status
docker-compose ps

# View recent logs
docker-compose logs -f --tail=100

# Run health check
docker exec pxe-boot-server /usr/local/bin/healthcheck.sh

# Test HTTP connectivity
curl -I http://localhost:8080/health
```

## Common Issues and Solutions

### DHCP Issues

#### Problem: DHCP server not assigning IPs

**Symptoms:**
- Clients don't get IP addresses
- DHCP logs show no activity

**Solutions:**

1. **Check network interface permissions:**
   ```bash
   # Ensure container has host network access
   docker-compose exec pxe-server ip link show
   ```

2. **Verify no other DHCP servers:**
   ```bash
   # Check for conflicting DHCP servers
   sudo nmap -sU -p 67 --script=dhcp-discover 192.168.1.0/24
   ```

3. **Check DHCP configuration:**
   ```bash
   docker-compose exec pxe-server dhcpd -t -cf /etc/dhcp/dhcpd.conf
   ```

4. **Review DHCP logs:**
   ```bash
   docker-compose logs pxe-server | grep dhcpd
   ```

#### Problem: DHCP offers wrong boot file

**Symptoms:**
- Clients boot but get wrong PXE file

**Solutions:**

1. **Verify HTTP server IP:**
   ```bash
   docker-compose exec pxe-server env | grep HTTP_SERVER_IP
   ```

2. **Check PXE files exist:**
   ```bash
   docker-compose exec pxe-server ls -la /var/www/html/pxelinux.0
   ```

3. **Test HTTP access:**
   ```bash
   curl -I http://localhost:8080/pxelinux.0
   ```

### HTTP/Nginx Issues

#### Problem: HTTP server not responding

**Symptoms:**
- Port 8080 not accessible
- Nginx logs show errors

**Solutions:**

1. **Check Nginx status:**
   ```bash
   docker-compose exec pxe-server nginx -t
   docker-compose exec pxe-server systemctl status nginx
   ```

2. **Review Nginx logs:**
   ```bash
   docker-compose logs pxe-server | grep nginx
   ```

3. **Verify port binding:**
   ```bash
   docker-compose exec pxe-server netstat -tlnp | grep 8080
   ```

4. **Test internal connectivity:**
   ```bash
   docker-compose exec pxe-server curl -f http://127.0.0.1:8080/health
   ```

#### Problem: OS images not downloading

**Symptoms:**
- PXE boot menu loads but image downloads fail

**Solutions:**

1. **Check image file permissions:**
   ```bash
   docker-compose exec pxe-server ls -la /var/www/html/images/
   ```

2. **Verify HTTP access to images:**
   ```bash
   curl -I http://localhost:8080/images/rocky9/vmlinuz
   ```

3. **Check disk space:**
   ```bash
   docker-compose exec pxe-server df -h /var/www/html
   ```

4. **Review download script logs:**
   ```bash
   docker-compose exec pxe-server cat /var/log/pxe/download.log
   ```

### PXE Boot Issues

#### Problem: Client doesn't enter PXE boot

**Symptoms:**
- Client boots normally instead of PXE

**Solutions:**

1. **Check BIOS boot order:**
   - Enter BIOS setup (usually F2, F10, or Del)
   - Ensure network boot is enabled and first in boot order

2. **Verify PXE-capable NIC:**
   ```bash
   # Check if NIC supports PXE
   ipmitool chassis bootdev pxe
   ```

3. **Test DHCP connectivity:**
   ```bash
   # From client network, test DHCP
   sudo nmap -sU -p 67 --script=dhcp-discover <server-ip>
   ```

#### Problem: PXE menu not showing

**Symptoms:**
- Client gets IP but no boot menu appears

**Solutions:**

1. **Check PXE boot files:**
   ```bash
   docker-compose exec pxe-server ls -la /var/www/html/pxelinux.cfg/default
   ```

2. **Verify DHCP next-server and filename:**
   ```bash
   docker-compose exec pxe-server grep filename /etc/dhcp/dhcpd.conf
   ```

3. **Test PXE file access:**
   ```bash
   curl -I http://localhost:8080/pxelinux.0
   ```

4. **Check client PXE logs:**
   - Review client BIOS logs or network captures

### Container Issues

#### Problem: Container fails to start

**Symptoms:**
- `docker-compose up` fails
- Container exits immediately

**Solutions:**

1. **Check container logs:**
   ```bash
   docker-compose logs pxe-server
   ```

2. **Verify environment variables:**
   ```bash
   docker-compose config
   ```

3. **Test configuration files:**
   ```bash
   docker run --rm -v $(pwd)/configs:/etc/pxe pxe-server dhcpd -t -cf /etc/pxe/dhcpd.conf
   ```

4. **Check resource limits:**
   ```bash
   docker system df
   docker stats
   ```

#### Problem: High resource usage

**Symptoms:**
- Container using excessive CPU/memory

**Solutions:**

1. **Check active connections:**
   ```bash
   docker-compose exec pxe-server netstat -tunp
   ```

2. **Review access logs:**
   ```bash
   docker-compose logs pxe-server | grep nginx | tail -50
   ```

3. **Monitor processes:**
   ```bash
   docker-compose exec pxe-server ps aux
   ```

4. **Adjust resource limits in docker-compose.yml:**
   ```yaml
   deploy:
     resources:
       limits:
         cpus: '1.0'
         memory: 512M
   ```

### Network Issues

#### Problem: Client can't reach PXE server

**Symptoms:**
- Network connectivity issues
- Firewall blocking traffic

**Solutions:**

1. **Check firewall rules:**
   ```bash
   # On host system
   sudo iptables -L -n | grep 67
   sudo iptables -L -n | grep 8080
   ```

2. **Verify network routing:**
   ```bash
   # Check if client network can reach server
   traceroute <server-ip>
   ```

3. **Test port accessibility:**
   ```bash
   # From client network
   telnet <server-ip> 8080
   nmap -p 67,8080 <server-ip>
   ```

4. **Check VLAN configuration:**
   - Ensure PXE server and clients are on same VLAN/broadcast domain

## Advanced Troubleshooting

### Packet Capture Analysis

```bash
# Capture DHCP traffic
tcpdump -i eth0 -n port 67 or port 68 -w dhcp.pcap

# Capture HTTP traffic
tcpdump -i eth0 -n port 8080 -w http.pcap

# Analyze captures
wireshark dhcp.pcap
```

### Log Analysis

```bash
# Extract DHCP leases
docker-compose exec pxe-server cat /var/lib/dhcpd/dhcpd.leases

# Parse access logs
docker-compose logs pxe-server | grep '"GET /images/' | awk '{print $1, $7, $9}'

# Monitor error patterns
docker-compose logs pxe-server | grep ERROR | tail -20
```

### Performance Tuning

```bash
# Check Nginx worker status
docker-compose exec pxe-server nginx -T | grep worker

# Monitor connection counts
docker-compose exec pxe-server netstat -tunp | wc -l

# Test throughput
iperf -c <client-ip> -p 8080
```

## Getting Help

If you can't resolve an issue:

1. **Gather diagnostic information:**
   ```bash
   # Create diagnostic bundle
   docker-compose logs > logs.txt
   docker-compose config > config.txt
   docker-compose ps > status.txt
   ```

2. **Check existing issues:**
   - Search GitHub issues for similar problems

3. **Open a new issue:**
   - Include diagnostic bundle
   - Describe your environment
   - Provide exact error messages
   - Include steps to reproduce

## Prevention

### Monitoring Setup

```bash
# Set up log monitoring
docker-compose logs -f pxe-server | tee /var/log/pxe-server.log

# Configure alerts for critical errors
# Example: Alert on DHCP failures
docker-compose logs pxe-server | grep -i "dhcp.*fail"
```

### Regular Maintenance

```bash
# Weekly tasks
docker system prune -f
docker-compose restart

# Monthly tasks
docker-compose pull
docker-compose up -d

# Check logs for anomalies
docker-compose logs --since 30d | grep -i error
