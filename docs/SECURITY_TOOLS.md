# Security Tools Integration

## ⚠️ CRITICAL WARNING ⚠️

**These security tools are for AUTHORIZED SECURITY TESTING ONLY.**

Unauthorized use of these tools against systems you do not own or have explicit permission to test is **ILLEGAL** and may result in:
- Criminal prosecution
- Significant fines
- Prison time
- Civil liability

**READ AND ACKNOWLEDGE** the `rpi-scripts/security-tools/LEGAL_NOTICE.txt` before proceeding.

---

## Overview

The Parrot MCP Server includes integration with professional security testing tools for authorized penetration testing, vulnerability assessment, and security research.

**Iteration 1: Network Scanning** (Current Implementation)
- ✅ Nmap - Network discovery and port scanning
- ✅ OpenVAS/GVM - Vulnerability scanning

**Future Iterations** (Planned):
- Metasploit, searchsploit (penetration testing)
- Hydra, John the Ripper (password security)
- Volatility, Autopsy (forensics)
- Aircrack-ng, Kismet (wireless security)
- Snort, Suricata (IDS/IPS)
- Ghidra (reverse engineering)

---

## Architecture

### Component Overview

```
security-tools/
├── security_config.sh          # Configuration and utility functions
├── nmap_wrapper.sh              # Nmap execution wrapper
├── openvas_wrapper.sh           # OpenVAS/GVM wrapper
├── security_api.py              # REST API server
├── requirements.txt             # Python dependencies
├── LEGAL_NOTICE.txt             # Legal terms and acknowledgment
├── configs/                     # Configuration files
│   ├── ip_whitelist.conf        # Authorized scan targets
│   ├── ip_blacklist.conf        # Prohibited targets
│   └── api_keys.conf            # API authentication keys
└── scan-results/                # Encrypted scan results
```

### Security Controls

✅ **Authentication**: API key-based authentication
✅ **Authorization**: User whitelist, role validation
✅ **Rate Limiting**: Max 10 scans/hour per user
✅ **Target Validation**: IP whitelist/blacklist enforcement
✅ **Input Validation**: Strict parameter validation
✅ **Audit Logging**: Comprehensive security audit trail
✅ **Result Encryption**: GPG or OpenSSL encryption at rest
✅ **Sandboxing**: Optional Docker/namespace isolation

---

## Installation

### Prerequisites

```bash
# Install required tools
sudo apt-get update
sudo apt-get install -y nmap ipcalc

# For OpenVAS (optional, requires more setup)
sudo apt-get install -y gvm

# Install Python dependencies
cd rpi-scripts/security-tools
pip3 install -r requirements.txt
```

### Configuration

1. **Initialize Security Tools**:
```bash
cd /home/user/parrot_mcp_server/rpi-scripts
source security-tools/security_config.sh
security_init
```

2. **Configure IP Whitelist** (REQUIRED):
```bash
# Edit whitelist to include only authorized targets
nano security-tools/configs/ip_whitelist.conf

# Example entries:
# 192.168.1.0/24      # Home lab network
# 10.0.100.0/24       # Test environment
# 172.16.50.100/32    # Single test host
```

3. **Configure IP Blacklist** (RECOMMENDED):
```bash
# Edit blacklist to explicitly block sensitive targets
nano security-tools/configs/ip_blacklist.conf

# Default blacklist includes:
# - Public DNS servers (8.8.8.8, 1.1.1.1)
# - Reserved ranges
# Add your own critical infrastructure IPs here
```

4. **Create API Keys**:
```bash
# Generate API key
API_KEY=$(openssl rand -hex 32)
echo "Your API key: $API_KEY"

# Hash and store
echo -n "$API_KEY" | sha256sum | awk '{print "admin:" $1}' >> security-tools/configs/api_keys.conf
chmod 600 security-tools/configs/api_keys.conf
```

5. **Configure OpenVAS** (if using):
```bash
# Store OpenVAS password securely
echo "your_openvas_password" > security-tools/configs/.openvas_password
chmod 600 security-tools/configs/.openvas_password

# Start GVM services
sudo gvm-start
```

---

## Usage

### Option 1: Command Line Interface

#### Nmap Wrapper

**Basic TCP Scan**:
```bash
./security-tools/nmap_wrapper.sh \
    -t 192.168.1.100 \
    -s tcp \
    -u admin \
    -k YOUR_API_KEY
```

**Version Detection**:
```bash
./security-tools/nmap_wrapper.sh \
    -t 192.168.1.0/24 \
    -s version \
    -p 22,80,443 \
    -u admin \
    -k YOUR_API_KEY
```

**Ping Sweep**:
```bash
./security-tools/nmap_wrapper.sh \
    -t 192.168.1.0/24 \
    -s ping \
    -u admin \
    -k YOUR_API_KEY
```

**Custom Output**:
```bash
./security-tools/nmap_wrapper.sh \
    -t 192.168.1.100 \
    -s tcp \
    -o production_server_scan \
    -u admin \
    -k YOUR_API_KEY
```

#### OpenVAS Wrapper

**Quick Vulnerability Scan**:
```bash
./security-tools/openvas_wrapper.sh \
    -t 192.168.1.100 \
    -c full_and_fast \
    -u admin \
    -k YOUR_API_KEY
```

**Deep Scan with Custom Name**:
```bash
./security-tools/openvas_wrapper.sh \
    -t 192.168.1.0/24 \
    -c full_and_deep \
    -n "Production Network Q4 2025" \
    -u admin \
    -k YOUR_API_KEY
```

**Wait for Completion**:
```bash
./security-tools/openvas_wrapper.sh \
    -t 192.168.1.100 \
    --wait \
    -u admin \
    -k YOUR_API_KEY
```

### Option 2: REST API

#### Start API Server

```bash
cd /home/user/parrot_mcp_server/rpi-scripts/security-tools
python3 security_api.py
```

**Server runs on**: `http://127.0.0.1:5000`

#### API Endpoints

**Health Check**:
```bash
curl http://127.0.0.1:5000/health
```

**Nmap Scan**:
```bash
curl -X POST http://127.0.0.1:5000/api/v1/scan/nmap \
    -H "Authorization: Bearer YOUR_API_KEY" \
    -H "Content-Type: application/json" \
    -d '{
        "user": "admin",
        "target": "192.168.1.100",
        "scan_type": "tcp",
        "ports": "80,443,22"
    }'
```

**OpenVAS Scan**:
```bash
curl -X POST http://127.0.0.1:5000/api/v1/scan/openvas \
    -H "Authorization: Bearer YOUR_API_KEY" \
    -H "Content-Type: application/json" \
    -d '{
        "user": "admin",
        "target": "192.168.1.100",
        "config": "full_and_fast",
        "name": "Weekly Security Scan",
        "wait": false
    }'
```

**List Results**:
```bash
curl http://127.0.0.1:5000/api/v1/results \
    -H "Authorization: Bearer YOUR_API_KEY" \
    -G -d "user=admin"
```

**Download Result**:
```bash
curl http://127.0.0.1:5000/api/v1/results/nmap_20251111_120000_12345.xml \
    -H "Authorization: Bearer YOUR_API_KEY" \
    -G -d "user=admin" \
    -o scan_result.xml
```

**Get Whitelist**:
```bash
curl http://127.0.0.1:5000/api/v1/config/whitelist \
    -H "Authorization: Bearer YOUR_API_KEY" \
    -G -d "user=admin"
```

**Update Whitelist**:
```bash
curl -X POST http://127.0.0.1:5000/api/v1/config/whitelist \
    -H "Authorization: Bearer YOUR_API_KEY" \
    -H "Content-Type: application/json" \
    -d '{
        "user": "admin",
        "whitelist": [
            "192.168.1.0/24",
            "10.0.0.0/8"
        ]
    }'
```

---

## Scan Types

### Nmap Scan Types

| Type | Flag | Description | Speed | Stealth |
|------|------|-------------|-------|---------|
| `tcp` | `-sS` | TCP SYN scan (default) | Fast | High |
| `tcp-connect` | `-sT` | TCP connect scan | Medium | Low |
| `udp` | `-sU` | UDP scan | Slow | Medium |
| `version` | `-sV` | Service version detection | Slow | Low |
| `ping` | `-sn` | Ping sweep (no port scan) | Very Fast | High |
| `os` | `-O` | OS detection | Medium | Medium |
| `default` | `-sC` | Default NSE scripts | Medium | Low |

### OpenVAS Scan Configurations

| Configuration | UUID | Description | Duration |
|---------------|------|-------------|----------|
| `full_and_fast` | `daba56c8-...` | Comprehensive scan, optimized | 1-2 hours |
| `full_and_deep` | `698f691e-...` | Thorough scan, all checks | 4-8 hours |
| `discovery` | `8715c877-...` | Network discovery only | 10-30 min |
| `system_discovery` | `bbca7412-...` | System identification | 5-15 min |

---

## Output Formats

### Nmap Output

Results are saved in multiple formats:
- **`.txt`**: Human-readable normal output
- **`.xml`**: Machine-parseable XML format
- **`.log`**: Execution log with stderr

### OpenVAS Output

Results are saved in:
- **`.xml`**: Full vulnerability report (XML)
- **`.html`**: Web-viewable report (if available)

### Encryption

If `SECURITY_ENCRYPT_RESULTS=true` (default), all result files are encrypted:
- **GPG**: `.enc` extension, encrypted with configured key
- **OpenSSL**: `.enc` extension, AES-256-CBC encryption

**Decrypt GPG**:
```bash
gpg --decrypt scan_result.xml.enc > scan_result.xml
```

**Decrypt OpenSSL** (requires password):
```bash
openssl enc -aes-256-cbc -d -in scan_result.xml.enc -out scan_result.xml
```

---

## Security Best Practices

### 1. Obtain Written Authorization

**Before any scanning**:
- ✅ Get written permission (email, contract, signed form)
- ✅ Define scope clearly (IP ranges, systems, time windows)
- ✅ Establish communication channels
- ✅ Set expectations for reporting

### 2. Configure Whitelisting Properly

```bash
# Whitelist ONLY what you're authorized to scan
# Use most specific CIDR notation possible
# Document authorization for each range

# Example whitelist:
192.168.1.0/24        # Home lab (owned)
10.0.50.100/32        # Test server (contract #12345)
172.16.100.0/28       # Client network (signed SOW)
```

### 3. Monitor Audit Logs

```bash
# Review security audit log regularly
tail -f logs/security_audit.log

# Check for unauthorized access attempts
grep "ERROR" logs/security_audit.log

# Generate audit report
awk -F'[][]' '/SECURITY/{print $2, $4, $6}' logs/security_audit.log
```

### 4. Rate Limiting

Default rate limits:
- **10 scans per hour** per user
- **60 second minimum** between scans

Adjust in `security_config.sh`:
```bash
SECURITY_MAX_SCANS_PER_HOUR=10
SECURITY_MIN_SCAN_INTERVAL=60
```

### 5. Result Retention

Results are automatically deleted after 30 days:
```bash
# Adjust retention period (days)
SECURITY_RESULTS_RETENTION_DAYS=30

# Manual cleanup
source security-tools/security_config.sh
security_cleanup_old_results
```

### 6. Principle of Least Privilege

- Run API server as dedicated user (not root)
- Use service account for automated scans
- Limit API key distribution
- Rotate keys regularly

### 7. Network Isolation

For maximum security:
```bash
# Enable network namespace isolation
SECURITY_USE_NETNS=true
SECURITY_NETNS_NAME=parrot_security

# Or use Docker containers
SECURITY_USE_DOCKER=true
SECURITY_DOCKER_IMAGE=kalilinux/kali-rolling
```

---

## Troubleshooting

### Nmap Issues

**"Target not authorized"**:
- Check IP whitelist: `cat security-tools/configs/ip_whitelist.conf`
- Ensure target matches a whitelisted CIDR range
- Install `ipcalc`: `sudo apt-get install ipcalc`

**"Authentication failed"**:
- Verify API key is correct
- Check `security-tools/configs/api_keys.conf` exists
- Ensure key hash matches: `echo -n "YOUR_KEY" | sha256sum`

**"Rate limit exceeded"**:
- Wait for rate limit window to expire (1 hour)
- Or adjust `SECURITY_MAX_SCANS_PER_HOUR` in config

### OpenVAS Issues

**"GVM socket not found"**:
- Start GVM: `sudo gvm-start`
- Check socket: `ls -la /var/run/gvmd/gvmd.sock`

**"OpenVAS authentication failed"**:
- Verify password file: `cat security-tools/configs/.openvas_password`
- Reset admin password: `sudo gvmd --user=admin --new-password=NEW_PASSWORD`

**"Scan timeout"**:
- Increase timeout: `OPENVAS_TIMEOUT=7200` (2 hours)
- Check scan progress in GVM web interface

### API Issues

**"Connection refused"**:
- Check API server is running: `ps aux | grep security_api.py`
- Start API: `python3 security-tools/security_api.py`

**"Missing Authorization header"**:
- Include header: `-H "Authorization: Bearer YOUR_API_KEY"`

**"Missing username"**:
- Include `"user"` in JSON body or query params

---

## Development

### Adding New Tools

To add a new security tool (e.g., Metasploit):

1. **Create wrapper script**:
```bash
rpi-scripts/security-tools/metasploit_wrapper.sh
```

2. **Follow wrapper pattern**:
- Load `security_config.sh`
- Implement authentication check
- Validate inputs
- Audit log all operations
- Return JSON result

3. **Add API endpoint**:
```python
# In security_api.py
@app.route('/api/v1/scan/metasploit', methods=['POST'])
@require_auth
def metasploit_scan():
    # Implementation
```

4. **Update documentation**:
- Add to this file
- Update LEGAL_NOTICE.txt if needed

### Testing

```bash
# Test Nmap wrapper
cd /home/user/parrot_mcp_server/rpi-scripts
./security-tools/nmap_wrapper.sh --help

# Test API health
curl http://127.0.0.1:5000/health

# Integration test (requires BATS)
cd tests
bats security_tools.bats
```

---

## References

### Tools Documentation
- [Nmap Reference Guide](https://nmap.org/book/man.html)
- [OpenVAS/GVM Documentation](https://www.greenbone.net/en/product-documentation/)

### Security Standards
- [OWASP Testing Guide](https://owasp.org/www-project-web-security-testing-guide/)
- [PTES - Penetration Testing Execution Standard](http://www.pentest-standard.org/)
- [NIST SP 800-115](https://csrc.nist.gov/publications/detail/sp/800-115/final) - Technical Guide to Information Security Testing

### Legal Resources
- [Computer Fraud and Abuse Act (CFAA)](https://www.law.cornell.edu/uscode/text/18/1030)
- [Responsible Disclosure Guidelines](https://cheatsheetseries.owasp.org/cheatsheets/Vulnerability_Disclosure_Cheat_Sheet.html)

---

## Support

For issues or questions:
- **GitHub Issues**: https://github.com/canstralian/parrot_mcp_server/issues
- **Security Concerns**: security@parrot-mcp.local (encrypt with project GPG key)

---

**Last Updated**: 2025-11-11
**Version**: 1.0.0 (Iteration 1: Network Scanning)
