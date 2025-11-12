# Parrot MCP Server - Enterprise Nmap Integration

![Build Status](https://img.shields.io/badge/build-passing-brightgreen)
![Test Status](https://img.shields.io/badge/tests-passing-brightgreen)
![License](https://img.shields.io/badge/license-MIT-blue)
![Python](https://img.shields.io/badge/python-3.11+-blue)
![Docker](https://img.shields.io/badge/docker-ready-blue)

**Enterprise-grade network scanning solution with comprehensive Nmap integration, asynchronous task processing, and production-ready security.**

## 🚀 Overview

The Parrot MCP Server provides a robust, scalable REST API for network scanning operations powered by Nmap. Built with enterprise requirements in mind, it offers:

- **Production-Ready**: Battle-tested components with comprehensive security
- **Scalable Architecture**: Asynchronous task processing with Celery + Redis
- **Enterprise Security**: JWT/API key auth, RBAC, rate limiting, audit logging
- **Multiple Scan Types**: Quick, full, stealth, OS detection, vulnerability scans
- **Advanced Reporting**: JSON, CSV, PDF, and HTML report generation
- **Docker-Ready**: Complete containerized deployment with docker-compose

## ✨ Key Features

### 🔒 Security First
- **Multi-layer authentication**: JWT tokens and API keys
- **Role-Based Access Control**: Admin, Analyst, and User roles with granular permissions
- **Input validation**: Protection against command injection and path traversal
- **Rate limiting**: Configurable per-endpoint limits
- **Audit logging**: Complete trail of all actions for compliance
- **Container security**: Non-root execution with limited capabilities

### 📊 Comprehensive Scanning
- **6 Scan Profiles**: Quick, default, full, stealth, OS detection, vulnerability
- **Custom Scans**: Flexible Nmap argument support with security validation
- **Asynchronous Execution**: Non-blocking scans with Celery workers
- **Priority Queuing**: Manage scan execution order
- **Real-time Status**: Track scan progress and view results instantly

### 📈 Enterprise Features
- **PostgreSQL Database**: Persistent storage with connection pooling
- **Redis Caching**: Fast task queuing and rate limit tracking
- **Multi-format Reports**: Export results in JSON, CSV, PDF, or HTML
- **Horizontal Scaling**: Add workers dynamically to handle load
- **Health Monitoring**: Built-in health checks and metrics
- **Log Management**: Structured JSON logging with rotation

## 🏗️ Architecture

```
┌─────────────────┐     ┌──────────────┐
│   Client App    │────▶│  Flask API   │
│  (REST/JSON)    │     │   + Auth     │
└─────────────────┘     └──────┬───────┘
                               │
                    ┌──────────┼──────────┐
                    ▼          ▼          ▼
              ┌──────────┬──────────┬──────────┐
              │PostgreSQL│  Redis   │  Celery  │
              │   (DB)   │ (Queue)  │ Workers  │
              └──────────┴──────────┴──────────┘
```

## 🚀 Quick Start

### Prerequisites
- Docker 20.10+
- Docker Compose 2.0+

### 1. Clone and Configure

```bash
git clone https://github.com/canstralian/parrot_mcp_server.git
cd parrot_mcp_server

# Copy and configure environment
cp .env.example .env
# Edit .env with your settings (see Configuration section)
```

### 2. Deploy with Docker

```bash
# Start all services
docker-compose up -d

# Check status
docker-compose ps

# View logs
docker-compose logs -f api
```

### 3. Initialize Database

```bash
# Run initialization script
docker-compose exec api python scripts/init_db.py \
  --admin-username admin \
  --admin-email admin@example.com
# You'll be prompted for a password
```

### 4. Test the API

```bash
# Health check
curl http://localhost:8000/health

# Login
TOKEN=$(curl -s -X POST http://localhost:8000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"YOUR_PASSWORD"}' \
  | jq -r '.access_token')

# Create a scan
curl -X POST http://localhost:8000/api/v1/scans \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "target": "192.168.1.0/24",
    "scan_type": "quick"
  }'
```

## 📋 API Examples

### Authentication

```bash
# Register a new user
curl -X POST http://localhost:8000/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "username": "analyst",
    "email": "analyst@example.com",
    "password": "SecurePass123!",
    "role": "analyst"
  }'

# Login and get token
curl -X POST http://localhost:8000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"analyst","password":"SecurePass123!"}'
```

### Scanning

```bash
# Quick scan (top 100 ports)
curl -X POST http://localhost:8000/api/v1/scans \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"target":"192.168.1.100","scan_type":"quick"}'

# Full scan (all 65535 ports)
curl -X POST http://localhost:8000/api/v1/scans \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"target":"192.168.1.100","scan_type":"full"}'

# Vulnerability scan
curl -X POST http://localhost:8000/api/v1/scans \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"target":"192.168.1.100","scan_type":"vuln"}'

# Get scan results
curl http://localhost:8000/api/v1/scans/1 \
  -H "Authorization: Bearer $TOKEN"

# List all scans
curl "http://localhost:8000/api/v1/scans?page=1&per_page=20" \
  -H "Authorization: Bearer $TOKEN"
```

## 🔧 Configuration

Key environment variables (see `.env.example` for complete list):

```bash
# Security (CHANGE IN PRODUCTION!)
SECRET_KEY=your-secret-key-here
JWT_SECRET_KEY=your-jwt-secret-here
DB_PASSWORD=secure_database_password
REDIS_PASSWORD=secure_redis_password

# Application
APP_ENV=production
PORT=8000

# Database
DB_HOST=db
DB_NAME=parrot_mcp
DB_USER=parrot

# Scanning
NMAP_TIMEOUT=300
MAX_CONCURRENT_TASKS=10

# Rate Limiting
ENABLE_RATE_LIMIT=true
RATE_LIMIT=100 per hour
```

## 📚 Documentation

- **[Deployment Guide](docs/DEPLOYMENT.md)** - Complete deployment instructions
- **[API Documentation](docs/API.md)** - Full API reference with examples
- **[Enterprise Guide](docs/ENTERPRISE_NMAP.md)** - Architecture and best practices
- **[Security Policy](SECURITY.md)** - Security guidelines and reporting
- **[Changelog](CHANGELOG.md)** - Version history and changes

## 🎯 Scan Types

| Type | Description | Use Case | Nmap Args |
|------|-------------|----------|-----------|
| `quick` | Fast scan of top 100 ports | Quick reconnaissance | `-T4 -F` |
| `default` | Standard scan | General purpose | `-T4 -Pn` |
| `full` | Complete TCP scan all ports | Comprehensive discovery | `-sS -sV -T4 -p-` |
| `stealth` | Stealthy SYN scan | Evasive scanning | `-sS -T2 -f` |
| `os` | Operating system detection | Identify systems | `-O --osscan-guess` |
| `vuln` | Vulnerability assessment | Security testing | `-sV --script=vuln` |

## 👥 User Roles & Permissions

| Role | Description | Permissions |
|------|-------------|-------------|
| **Admin** | Full system access | All operations, user management, audit logs |
| **Analyst** | Security analyst | Create/view all scans, generate reports |
| **User** | Basic user | Create/view own scans only |

## 🛠️ Development

### Manual Setup (without Docker)

```bash
# Install dependencies
python3.11 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# Setup PostgreSQL and Redis
# (See DEPLOYMENT.md for details)

# Initialize database
python scripts/init_db.py

# Start services
gunicorn -w 4 -b 0.0.0.0:8000 "mcp_server.app:create_app()"
celery -A mcp_server.worker.celery_app worker --loglevel=info
```

### Running Tests

```bash
# Install test dependencies
pip install -r requirements.txt

# Run tests
pytest tests/ -v --cov=mcp_server

# Run with coverage report
pytest tests/ --cov=mcp_server --cov-report=html
```

## 📊 Monitoring

### Celery Flower (Task Monitoring)

```bash
# Start with development profile
docker-compose --profile dev up -d

# Access Flower
open http://localhost:5555
```

### Health Checks

```bash
# API health
curl http://localhost:8000/health

# Database connection
docker-compose exec db psql -U parrot -d parrot_mcp -c "SELECT 1;"

# Redis connection
docker-compose exec redis redis-cli ping
```

## 🔐 Security

This project follows security best practices:

- ✅ No hardcoded credentials
- ✅ Input validation and sanitization
- ✅ SQL injection prevention (SQLAlchemy ORM)
- ✅ Command injection prevention
- ✅ Rate limiting on all endpoints
- ✅ Comprehensive audit logging
- ✅ Container security (non-root user)
- ✅ TLS/SSL ready (use reverse proxy)

See [SECURITY.md](SECURITY.md) for detailed security information and reporting vulnerabilities.

## 🤝 Contributing

We welcome contributions! Please see our contributing guidelines:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- [Nmap](https://nmap.org/) - Network scanning tool
- [Flask](https://flask.palletsprojects.com/) - Web framework
- [Celery](https://docs.celeryq.dev/) - Distributed task queue
- [PostgreSQL](https://www.postgresql.org/) - Database
- [Redis](https://redis.io/) - In-memory data store

## 📞 Support

- **GitHub Issues**: [Report bugs or request features](https://github.com/canstralian/parrot_mcp_server/issues)
- **Security Issues**: See [SECURITY.md](SECURITY.md) for responsible disclosure
- **Documentation**: Check the [docs](docs/) directory

---

**Built with ❤️ by the Parrot MCP Team**

*Empowering security professionals with enterprise-grade network scanning*