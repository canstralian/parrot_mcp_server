# Enterprise-Grade Nmap Integration

This document describes the enterprise-grade Nmap integration implemented in the Parrot MCP Server.

## Architecture Overview

```
┌─────────────────┐
│   Flask API     │
│   (8000)        │
│  - Auth/RBAC    │
│  - Rate Limit   │
│  - Validation   │
└────────┬────────┘
         │
         ├──► PostgreSQL (5432)
         │    - Scan Results
         │    - User Management
         │    - Audit Logs
         │
         ├──► Redis (6379)
         │    - Task Queue
         │    - Rate Limiting
         │    - Caching
         │
         └──► Celery Workers
              - Async Scan Execution
              - Result Processing
              - Scheduled Tasks
```

## Key Features

### 1. Scalability

**Asynchronous Task Processing**
- Celery + Redis for distributed task execution
- Configurable worker concurrency
- Priority-based task queuing
- Automatic retry on failure
- Task result caching

**Horizontal Scaling**
```bash
# Scale workers dynamically
docker-compose up -d --scale celery_worker=10
```

**Database Connection Pooling**
- SQLAlchemy with configurable pool size
- Connection recycling
- Timeout management

### 2. Security

**Multi-Layer Security Architecture**

1. **Input Validation**
   - IP/CIDR range validation with regex
   - Network size limits (max /24 for IPv4)
   - Forbidden range blocking (loopback, multicast, etc.)
   - Custom argument sanitization
   - Command injection prevention

2. **Authentication & Authorization**
   - JWT-based authentication
   - API key authentication
   - Role-Based Access Control (RBAC)
   - Password hashing with bcrypt
   - Token expiration and refresh

3. **Rate Limiting**
   - Per-endpoint rate limits
   - IP-based tracking
   - Redis-backed storage
   - Customizable limits per role

4. **Audit Logging**
   - Comprehensive action logging
   - IP address tracking
   - User agent logging
   - Status code tracking
   - Searchable audit trail

5. **Container Security**
   - Non-root user execution
   - Limited Linux capabilities
   - No new privileges
   - Security options enforcement

### 3. Result Management

**Database Storage**
- PostgreSQL for persistent storage
- Structured scan metadata
- Raw output preservation
- Parsed result JSON
- Full-text search capability

**Report Generation**
- JSON: Structured data export
- CSV: Tabular analysis
- PDF: Professional reports
- HTML: Interactive visualization

**Data Lifecycle**
- Automatic cleanup of old results
- Configurable retention policies
- Report expiration management
- Storage optimization

### 4. Monitoring & Observability

**Health Checks**
```bash
# API health
curl http://localhost:8000/health

# Celery worker status
celery -A mcp_server.worker.celery_app inspect active
```

**Metrics** (via Prometheus)
- Request count and latency
- Scan duration statistics
- Queue depth
- Worker utilization
- Error rates

**Logging**
- Structured JSON logging
- Multiple log levels
- Centralized log aggregation
- Log rotation

**Monitoring Dashboard**
- Flower for Celery monitoring
- Real-time task visibility
- Worker management
- Task history

### 5. Enterprise Features

**Role-Based Access Control**

| Role | Permissions |
|------|-------------|
| **Admin** | Full system access, user management, audit logs, all scans |
| **Analyst** | Create scans, view all scans, generate reports, read users |
| **User** | Create scans, view own scans, generate own reports |

**Permission Matrix**

| Permission | Admin | Analyst | User |
|------------|-------|---------|------|
| `scan:create` | ✅ | ✅ | ✅ |
| `scan:read` | ✅ (all) | ✅ (all) | ✅ (own) |
| `scan:delete` | ✅ (all) | ✅ (own) | ✅ (own) |
| `user:create` | ✅ | ❌ | ❌ |
| `user:manage` | ✅ | ❌ | ❌ |
| `system:audit` | ✅ | ❌ | ❌ |
| `report:create` | ✅ | ✅ | ✅ |

**Compliance Features**
- Complete audit trail
- Data retention policies
- Export capabilities
- Access logs
- Role separation

## Scan Types and Configuration

### Predefined Scan Profiles

```python
{
    "quick": ["-T4", "-F"],                          # Top 100 ports
    "default": ["-T4", "-Pn"],                       # Standard scan
    "full": ["-sS", "-sV", "-T4", "-p-"],           # All 65535 ports
    "stealth": ["-sS", "-T2", "-f"],                # Stealthy scan
    "os": ["-O", "--osscan-guess"],                 # OS detection
    "vuln": ["-sV", "--script=vuln", "-T4"]         # Vulnerability scan
}
```

### Custom Scans

```bash
curl -X POST http://localhost:8000/api/v1/scans \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "target": "192.168.1.0/24",
    "scan_type": "custom",
    "custom_args": "-sS -p 80,443,8080 -T4"
  }'
```

**Security Validation for Custom Args:**
- No path traversal attempts
- No file system access
- No shell metacharacters
- Argument whitelist enforcement

## Performance Optimization

### Concurrent Scan Management

```python
# Configuration
MAX_CONCURRENT_TASKS = 10  # System-wide limit
NMAP_TIMEOUT = 300         # Per-scan timeout (seconds)
```

### Worker Configuration

```yaml
celery_worker:
  concurrency: 4              # Parallel tasks per worker
  max_tasks_per_child: 50     # Restart after N tasks (memory)
  prefetch_multiplier: 1      # Fair task distribution
```

### Database Optimization

```python
# Connection pooling
SQLALCHEMY_POOL_SIZE = 10
SQLALCHEMY_POOL_TIMEOUT = 30
SQLALCHEMY_POOL_RECYCLE = 1800  # 30 minutes
```

### Caching Strategy

- Redis for rate limit counters
- Task result caching (24 hours)
- API response caching (optional)

## Deployment Architectures

### Single Server (Small Scale)

```
Docker Compose
├── API Server (1 instance)
├── Celery Workers (2-4)
├── PostgreSQL
├── Redis
└── Celery Beat
```

**Capacity:** 10-50 scans/hour

### Clustered (Medium Scale)

```
├── Load Balancer (Nginx)
├── API Servers (2-4 instances)
├── Celery Workers (10-20)
├── PostgreSQL (Primary + Replica)
├── Redis (Master + Replica)
└── Celery Beat (1 instance)
```

**Capacity:** 100-500 scans/hour

### Enterprise (Large Scale)

```
├── Load Balancer Cluster
├── API Server Auto-scaling Group
├── Celery Worker Auto-scaling Group
├── PostgreSQL Cluster (Primary + Multi-Replica)
├── Redis Cluster (Sharded)
├── Elasticsearch (Logs & Search)
├── Prometheus + Grafana (Metrics)
└── Kubernetes Orchestration
```

**Capacity:** 1000+ scans/hour

## Integration Patterns

### API Integration

```python
import requests

class NmapScanClient:
    def __init__(self, base_url, api_key):
        self.base_url = base_url
        self.headers = {"X-API-Key": api_key}

    def create_scan(self, target, scan_type="quick"):
        response = requests.post(
            f"{self.base_url}/api/v1/scans",
            headers=self.headers,
            json={"target": target, "scan_type": scan_type}
        )
        return response.json()

    def get_results(self, scan_id):
        response = requests.get(
            f"{self.base_url}/api/v1/scans/{scan_id}",
            headers=self.headers
        )
        return response.json()
```

### Webhook Integration (Future)

```python
# Configure webhook for scan completion
{
    "webhook_url": "https://your-system.com/webhook",
    "events": ["scan.completed", "scan.failed"],
    "secret": "webhook_secret_key"
}
```

### CI/CD Integration

```yaml
# .gitlab-ci.yml
security_scan:
  stage: test
  script:
    - |
      SCAN_ID=$(curl -X POST $NMAP_SERVER/api/v1/scans \
        -H "X-API-Key: $API_KEY" \
        -d '{"target":"$CI_ENVIRONMENT_URL","scan_type":"quick"}' \
        | jq -r '.scan.id')
    - while true; do
        STATUS=$(curl $NMAP_SERVER/api/v1/scans/$SCAN_ID | jq -r '.scan.status')
        [ "$STATUS" = "completed" ] && break
        sleep 10
      done
```

## Best Practices

### Security

1. **Never expose the API without TLS in production**
2. **Use strong, unique secrets for JWT and database**
3. **Regularly rotate API keys**
4. **Implement IP whitelisting for sensitive endpoints**
5. **Monitor audit logs for suspicious activity**
6. **Keep Nmap and dependencies updated**

### Performance

1. **Scale workers based on scan volume**
2. **Use database read replicas for heavy read loads**
3. **Implement caching for frequently accessed data**
4. **Set appropriate scan timeouts**
5. **Monitor queue depth and adjust concurrency**

### Reliability

1. **Enable automatic retry for failed scans**
2. **Implement health checks and alerting**
3. **Regular database backups (automated)**
4. **Test disaster recovery procedures**
5. **Use container orchestration for auto-recovery**

### Compliance

1. **Document all scan activities in audit logs**
2. **Implement data retention policies**
3. **Provide export capabilities for compliance reporting**
4. **Maintain role separation and least privilege**
5. **Regular security assessments**

## Troubleshooting

### Common Issues

**High Memory Usage**
- Reduce Celery concurrency
- Enable worker max_tasks_per_child restart
- Implement result pagination

**Slow Scans**
- Adjust Nmap timing (-T parameter)
- Increase worker count
- Check network latency

**Database Locks**
- Increase connection pool
- Optimize query patterns
- Use read replicas

**Queue Backlog**
- Scale workers horizontally
- Increase worker concurrency
- Adjust task priorities

## Future Enhancements

### Planned Features

1. **OpenVAS Integration** - Deeper vulnerability assessment
2. **Webhooks** - Real-time notifications
3. **Advanced Reporting** - Grafana dashboards, trends
4. **Machine Learning** - Anomaly detection
5. **Multi-tenancy** - Organization-level isolation
6. **Scheduled Scans** - Recurring scan jobs
7. **Scan Templates** - Reusable configurations
8. **Export Integrations** - SIEM, ticketing systems
9. **GraphQL API** - Alternative API interface
10. **Mobile App** - iOS/Android monitoring

## Support & Maintenance

### Monitoring Checklist

- [ ] API health endpoint responding
- [ ] Celery workers processing tasks
- [ ] Database connection pool healthy
- [ ] Redis operational
- [ ] Disk space sufficient
- [ ] Log rotation active
- [ ] Backup jobs running
- [ ] SSL certificates valid

### Maintenance Tasks

**Daily**
- Monitor error rates
- Check queue depth
- Review failed scans

**Weekly**
- Review audit logs
- Check disk usage
- Verify backups

**Monthly**
- Update dependencies
- Review security advisories
- Optimize database
- Clean old reports

**Quarterly**
- Security audit
- Performance review
- Capacity planning
- Disaster recovery test

## References

- [Nmap Documentation](https://nmap.org/docs.html)
- [Celery Documentation](https://docs.celeryq.dev/)
- [Flask Documentation](https://flask.palletsprojects.com/)
- [PostgreSQL Best Practices](https://wiki.postgresql.org/wiki/Don't_Do_This)
- [OWASP Top 10](https://owasp.org/www-project-top-ten/)

---

**Document Version:** 1.0
**Last Updated:** 2025-11-11
**Maintained By:** Parrot MCP Team
