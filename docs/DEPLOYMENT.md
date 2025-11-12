# Deployment Guide - Enterprise Nmap MCP Server

This guide provides step-by-step instructions for deploying the Parrot MCP Server with enterprise-grade Nmap integration.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Environment Setup](#environment-setup)
- [Docker Deployment](#docker-deployment)
- [Manual Deployment](#manual-deployment)
- [Configuration](#configuration)
- [Security Hardening](#security-hardening)
- [Monitoring and Maintenance](#monitoring-and-maintenance)

## Prerequisites

### System Requirements

- **OS**: Linux (Ubuntu 20.04+, Debian 11+, RHEL 8+) or Docker
- **CPU**: 2+ cores recommended
- **RAM**: 4GB minimum, 8GB recommended
- **Disk**: 20GB minimum for application and logs
- **Network**: Outbound internet access for dependencies

### Required Software

- Docker 20.10+ and Docker Compose 2.0+ (for Docker deployment)
- Python 3.11+ (for manual deployment)
- PostgreSQL 15+
- Redis 7+
- Nmap 7.90+

## Environment Setup

### 1. Clone Repository

```bash
git clone https://github.com/canstralian/parrot_mcp_server.git
cd parrot_mcp_server
```

### 2. Configure Environment Variables

Create a `.env` file from the example:

```bash
cp .env.example .env
```

Edit `.env` with your configuration:

```bash
# Security (CHANGE THESE IN PRODUCTION!)
SECRET_KEY=your-secret-key-here-use-strong-random-string
JWT_SECRET_KEY=your-jwt-secret-key-here
DB_PASSWORD=secure_database_password
REDIS_PASSWORD=secure_redis_password

# Application
APP_ENV=production
APP_DEBUG=false
HOST=0.0.0.0
PORT=8000

# Database
DB_HOST=db
DB_PORT=5432
DB_NAME=parrot_mcp
DB_USER=parrot

# Rate Limiting
ENABLE_RATE_LIMIT=true
RATE_LIMIT=100 per hour

# Nmap Configuration
NMAP_TIMEOUT=300
MAX_CONCURRENT_TASKS=10

# Logging
LOG_LEVEL=INFO
LOG_FORMAT=json
```

**Security Note**: Generate strong secrets using:

```bash
# Generate SECRET_KEY
python -c "import secrets; print(secrets.token_urlsafe(32))"

# Generate JWT_SECRET_KEY
python -c "import secrets; print(secrets.token_urlsafe(32))"
```

## Docker Deployment

### Quick Start

1. **Build and start all services:**

```bash
docker-compose up -d
```

2. **Check service status:**

```bash
docker-compose ps
```

3. **View logs:**

```bash
# All services
docker-compose logs -f

# Specific service
docker-compose logs -f api
docker-compose logs -f celery_worker
```

### Initialize Database

```bash
# Run database migrations
docker-compose exec api flask db upgrade

# Create initial admin user
docker-compose exec api python -c "
from mcp_server.auth import AuthService
from mcp_server.db import db
from mcp_server.app import create_app

app = create_app()
with app.app_context():
    user = AuthService.create_user(
        username='admin',
        email='admin@example.com',
        password='change-this-password',
        role='admin'
    )
    print(f'Admin user created: {user.username}')
"
```

### Access Services

- **API**: http://localhost:8000
- **Health Check**: http://localhost:8000/health
- **Flower (Celery Monitor)**: http://localhost:5555 (requires `--profile dev`)

### Enable Development Tools

```bash
# Start with Flower monitoring
docker-compose --profile dev up -d
```

## Manual Deployment

### 1. Install System Dependencies

```bash
# Ubuntu/Debian
sudo apt update
sudo apt install -y python3.11 python3.11-venv python3-pip \
    postgresql postgresql-contrib redis-server nmap

# RHEL/CentOS
sudo dnf install -y python3.11 postgresql-server redis nmap
```

### 2. Setup PostgreSQL

```bash
# Create database and user
sudo -u postgres psql <<EOF
CREATE DATABASE parrot_mcp;
CREATE USER parrot WITH ENCRYPTED PASSWORD 'secure_password';
GRANT ALL PRIVILEGES ON DATABASE parrot_mcp TO parrot;
EOF
```

### 3. Setup Redis

```bash
# Configure Redis with password
sudo sed -i 's/# requirepass foobared/requirepass your_redis_password/' /etc/redis/redis.conf
sudo systemctl restart redis
```

### 4. Create Python Virtual Environment

```bash
python3.11 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
```

### 5. Initialize Database

```bash
# Set environment variables
export DATABASE_URL="postgresql://parrot:secure_password@localhost/parrot_mcp"

# Run migrations
flask db upgrade

# Or create tables directly
python -c "
from mcp_server.app import create_app
from mcp_server.db import db

app = create_app()
with app.app_context():
    db.create_all()
"
```

### 6. Create Admin User

```bash
python scripts/create_admin.py --username admin --email admin@example.com --password securepass
```

### 7. Start Services

**Terminal 1 - Flask API:**
```bash
gunicorn -w 4 -b 0.0.0.0:8000 "mcp_server.app:create_app()" --access-logfile - --error-logfile -
```

**Terminal 2 - Celery Worker:**
```bash
celery -A mcp_server.worker.celery_app worker --loglevel=info --concurrency=4
```

**Terminal 3 - Celery Beat (scheduled tasks):**
```bash
celery -A mcp_server.worker.celery_app beat --loglevel=info
```

## Configuration

### Nmap Scan Types

Configure allowed scan types and their parameters:

| Scan Type | Description | Nmap Args | Use Case |
|-----------|-------------|-----------|----------|
| `quick` | Fast scan of top 100 ports | `-T4 -F` | Quick network reconnaissance |
| `default` | Standard scan | `-T4 -Pn` | General purpose scanning |
| `full` | Full TCP scan all ports | `-sS -sV -T4 -p-` | Comprehensive port discovery |
| `stealth` | Stealth SYN scan | `-sS -T2 -f` | Evasive scanning |
| `os` | OS detection | `-O --osscan-guess` | Identify operating systems |
| `vuln` | Vulnerability scan | `-sV --script=vuln` | Security assessment |

### Rate Limiting

Adjust rate limits in `.env`:

```bash
# Per-endpoint limits (examples)
RATE_LIMIT=100 per hour          # Default for all endpoints
SCAN_CREATE_LIMIT=20 per hour    # Scan creation
LOGIN_LIMIT=10 per minute        # Authentication
```

### Logging Configuration

```bash
LOG_LEVEL=INFO              # DEBUG, INFO, WARNING, ERROR, CRITICAL
LOG_FORMAT=json             # json or text
LOG_FILE=/app/logs/mcp_server.log
```

## Security Hardening

### 1. Network Security

```bash
# Configure firewall (UFW example)
sudo ufw allow 8000/tcp  # API port
sudo ufw enable
```

### 2. TLS/SSL Configuration

Use a reverse proxy like Nginx with Let's Encrypt:

```bash
# Install Nginx
sudo apt install nginx certbot python3-certbot-nginx

# Obtain certificate
sudo certbot --nginx -d your-domain.com

# Configure Nginx proxy
sudo nano /etc/nginx/sites-available/parrot-mcp
```

**Nginx Configuration:**

```nginx
server {
    listen 443 ssl http2;
    server_name your-domain.com;

    ssl_certificate /etc/letsencrypt/live/your-domain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/your-domain.com/privkey.pem;

    location / {
        proxy_pass http://localhost:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

### 3. Database Security

```bash
# Restrict PostgreSQL connections
sudo nano /etc/postgresql/15/main/pg_hba.conf

# Change from 'trust' to 'md5' or 'scram-sha-256'
# host    all    all    127.0.0.1/32    scram-sha-256
```

### 4. Container Security

```bash
# Run containers with limited capabilities
docker-compose up -d --no-build --force-recreate
```

See `docker-compose.yml` for security configurations:
- Non-root user execution
- Capability restrictions
- No new privileges

## Monitoring and Maintenance

### Health Checks

```bash
# Check API health
curl http://localhost:8000/health

# Check Celery workers
docker-compose exec celery_worker celery -A mcp_server.worker.celery_app inspect active
```

### Log Management

```bash
# View API logs
docker-compose logs -f api

# View worker logs
docker-compose logs -f celery_worker

# Export logs
docker-compose logs --no-color > application.log
```

### Database Backups

```bash
# Backup PostgreSQL
docker-compose exec db pg_dump -U parrot parrot_mcp > backup_$(date +%Y%m%d).sql

# Restore
docker-compose exec -T db psql -U parrot parrot_mcp < backup_20250101.sql
```

### Update and Restart

```bash
# Pull latest changes
git pull origin main

# Rebuild containers
docker-compose build

# Restart services (zero-downtime)
docker-compose up -d --no-deps --build api
docker-compose up -d --no-deps --build celery_worker
```

### Performance Tuning

**PostgreSQL:**
```bash
# Adjust connection pool size
export DB_POOL_SIZE=20
```

**Celery Worker:**
```bash
# Increase concurrency
docker-compose up -d --scale celery_worker=4
```

**Redis:**
```bash
# Increase max memory
docker-compose exec redis redis-cli CONFIG SET maxmemory 2gb
```

## Troubleshooting

### Common Issues

**Issue: Database connection errors**
```bash
# Check PostgreSQL is running
docker-compose ps db

# Check connection
docker-compose exec db psql -U parrot -d parrot_mcp -c "SELECT 1;"
```

**Issue: Celery tasks not executing**
```bash
# Check Redis connection
docker-compose exec redis redis-cli ping

# Inspect Celery
docker-compose exec celery_worker celery -A mcp_server.worker.celery_app inspect stats
```

**Issue: Nmap permission denied**
```bash
# Verify Nmap capabilities in container
docker-compose exec api nmap --version
```

## Production Checklist

- [ ] Changed all default passwords and secrets
- [ ] Configured TLS/SSL with valid certificates
- [ ] Set up database backups
- [ ] Configured log rotation
- [ ] Enabled firewall rules
- [ ] Set up monitoring and alerting
- [ ] Tested disaster recovery procedures
- [ ] Reviewed and hardened security settings
- [ ] Configured rate limiting appropriately
- [ ] Set up regular security updates

## Support

For issues and questions:
- GitHub Issues: https://github.com/canstralian/parrot_mcp_server/issues
- Security Issues: See SECURITY.md

---

**Last Updated**: 2025-11-11
