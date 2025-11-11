# 🚀 Deployment Guide - Parrot MCP Server

This guide provides comprehensive instructions for deploying the Parrot MCP Server to various environments.

## 📋 Table of Contents

- [Prerequisites](#prerequisites)
- [Local Development](#local-development)
- [Docker Deployment](#docker-deployment)
- [Kubernetes Deployment](#kubernetes-deployment)
- [CI/CD Pipeline](#cicd-pipeline)
- [Monitoring & Observability](#monitoring--observability)
- [Rollback Procedures](#rollback-procedures)
- [Troubleshooting](#troubleshooting)

## Prerequisites

### Required Tools

- **Docker** (v20.10+)
- **Docker Compose** (v2.0+) - for local Docker deployment
- **kubectl** (v1.24+) - for Kubernetes deployment
- **Git** - for source control
- **Bash** (v4.0+) - for running scripts

### Access Requirements

- GitHub account with repository access
- GitHub Container Registry (ghcr.io) access
- Kubernetes cluster access (for production deployment)
- Appropriate permissions for your target environment

## Local Development

### Quick Start

```bash
# Clone the repository
git clone https://github.com/canstralian/parrot_mcp_server.git
cd parrot_mcp_server

# Make scripts executable
chmod +x rpi-scripts/*.sh

# Start the server
./rpi-scripts/start_mcp_server.sh

# Run tests
./rpi-scripts/test_mcp_local.sh

# Stop the server
./rpi-scripts/stop_mcp_server.sh
```

### Running Tests

```bash
# Run all tests
cd rpi-scripts && ./test_mcp_local.sh

# Check logs
tail -f logs/parrot.log
```

## Docker Deployment

### Building the Docker Image

```bash
# Build the image
docker build -t parrot-mcp-server:latest .

# Run the container
docker run -d \
  --name mcp-server \
  -p 8080:8080 \
  -v $(pwd)/logs:/app/logs \
  parrot-mcp-server:latest
```

### Using Docker Compose

```bash
# Start services
docker-compose up -d

# View logs
docker-compose logs -f

# Stop services
docker-compose down
```

### Docker Image Management

```bash
# Tag for registry
docker tag parrot-mcp-server:latest ghcr.io/canstralian/parrot_mcp_server/parrot-mcp-server:latest

# Push to registry (requires authentication)
docker push ghcr.io/canstralian/parrot_mcp_server/parrot-mcp-server:latest
```

## Kubernetes Deployment

### Prerequisites

1. **Kubernetes cluster** (v1.24+)
2. **kubectl** configured with cluster access
3. **Ingress controller** (nginx-ingress recommended)
4. **cert-manager** (for TLS certificates)

### Deployment Steps

#### 1. Create Namespace

```bash
kubectl create namespace mcp-server
kubectl config set-context --current --namespace=mcp-server
```

#### 2. Apply Configurations

```bash
# Apply ConfigMap
kubectl apply -f k8s/configmap.yaml

# Create Persistent Volume Claim
kubectl apply -f k8s/pvc.yaml

# Deploy the application
kubectl apply -f k8s/deployment.yaml

# Create service
kubectl apply -f k8s/service.yaml

# Setup ingress (update domain first!)
kubectl apply -f k8s/ingress.yaml
```

#### 3. Verify Deployment

```bash
# Check deployment status
kubectl get deployments
kubectl rollout status deployment/mcp-server

# Check pods
kubectl get pods -l app=mcp-server

# Check services
kubectl get services

# Check ingress
kubectl get ingress
```

#### 4. View Logs

```bash
# Get logs from all pods
kubectl logs -l app=mcp-server --tail=100 -f

# Get logs from specific pod
kubectl logs <pod-name> -f
```

### Scaling

```bash
# Scale up
kubectl scale deployment/mcp-server --replicas=5

# Scale down
kubectl scale deployment/mcp-server --replicas=2

# Enable autoscaling
kubectl autoscale deployment/mcp-server --min=2 --max=10 --cpu-percent=80
```

### Updating Deployment

```bash
# Update image
kubectl set image deployment/mcp-server \
  mcp-server=ghcr.io/canstralian/parrot_mcp_server/parrot-mcp-server:v1.2.0

# Monitor rollout
kubectl rollout status deployment/mcp-server

# Check rollout history
kubectl rollout history deployment/mcp-server
```

## CI/CD Pipeline

### GitHub Actions Workflows

The project includes three main workflows:

#### 1. CI Pipeline (`.github/workflows/ci.yml`)

Runs on every push and pull request:

- **Linting**: ShellCheck for shell scripts
- **Testing**: MCP protocol compliance tests
- **Security**: Trivy scanning for vulnerabilities
- **Build**: Docker image build and validation
- **Integration**: End-to-end integration tests

#### 2. Staging Deployment (`.github/workflows/deploy-staging.yml`)

Automatically deploys to staging on push to `develop` branch:

- Builds and pushes Docker image
- Deploys to staging environment
- Runs smoke tests
- Sends deployment notifications

#### 3. Production Deployment (`.github/workflows/deploy-production.yml`)

Deploys to production on release or manual trigger:

- Requires manual approval
- Blue-green deployment strategy
- Comprehensive smoke tests
- Automatic rollback on failure

### Triggering Deployments

#### Staging Deployment

```bash
# Merge to develop branch
git checkout develop
git merge feature-branch
git push origin develop
```

#### Production Deployment

```bash
# Create and push a release tag
git tag -a v1.0.0 -m "Release version 1.0.0"
git push origin v1.0.0

# Or create a GitHub release through the web interface
```

#### Manual Deployment

Use GitHub Actions UI to trigger workflows manually with specific parameters.

## Monitoring & Observability

### Health Checks

The application includes built-in health checks:

```bash
# Docker health check
docker inspect --format='{{.State.Health.Status}}' mcp-server

# Kubernetes health check
kubectl get pods -l app=mcp-server -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}'
```

### Logs

#### Docker Logs

```bash
# View real-time logs
docker logs -f mcp-server

# View last 100 lines
docker logs --tail 100 mcp-server
```

#### Kubernetes Logs

```bash
# All pods
kubectl logs -l app=mcp-server --tail=100 -f

# Specific pod
kubectl logs <pod-name> -f

# Previous pod instance
kubectl logs <pod-name> --previous
```

### Metrics (Future Enhancement)

Prometheus metrics endpoint (planned):
- Request count
- Request duration
- Error rates
- System resource usage

## Rollback Procedures

### Kubernetes Rollback

```bash
# View rollout history
kubectl rollout history deployment/mcp-server

# Rollback to previous version
kubectl rollout undo deployment/mcp-server

# Rollback to specific revision
kubectl rollout undo deployment/mcp-server --to-revision=2

# Monitor rollback
kubectl rollout status deployment/mcp-server
```

### Docker Rollback

```bash
# Stop current container
docker stop mcp-server
docker rm mcp-server

# Run previous version
docker run -d \
  --name mcp-server \
  -p 8080:8080 \
  ghcr.io/canstralian/parrot_mcp_server/parrot-mcp-server:v1.0.0
```

### Verification After Rollback

```bash
# Run smoke tests
./scripts/smoke-test.sh

# Check logs for errors
tail -f logs/parrot.log

# Verify service availability
curl -I http://localhost:8080
```

## Troubleshooting

### Common Issues

#### 1. Container Won't Start

```bash
# Check logs
docker logs mcp-server

# Inspect container
docker inspect mcp-server

# Check resource constraints
docker stats mcp-server
```

#### 2. Pods Failing in Kubernetes

```bash
# Describe pod for events
kubectl describe pod <pod-name>

# Check logs
kubectl logs <pod-name>

# Check resource usage
kubectl top pods
```

#### 3. Permission Errors

```bash
# Ensure scripts are executable
find . -name "*.sh" -type f -exec chmod +x {} \;

# Check file ownership in container
docker exec mcp-server ls -la /app
```

#### 4. Network Issues

```bash
# Test internal connectivity
kubectl run -it --rm debug --image=alpine --restart=Never -- sh
# Inside the pod:
# wget -O- http://mcp-server

# Check ingress
kubectl describe ingress mcp-server-ingress
```

### Debug Mode

Enable debug logging:

```bash
# Docker
docker run -e DEBUG_MODE=1 parrot-mcp-server

# Kubernetes
kubectl set env deployment/mcp-server DEBUG_MODE=1
```

### Getting Help

1. Check logs first: `logs/parrot.log`
2. Review GitHub Issues: https://github.com/canstralian/parrot_mcp_server/issues
3. Consult documentation: `README.md`
4. Run smoke tests: `./scripts/smoke-test.sh`

## Security Considerations

### Image Security

- Images run as non-root user (UID 1000)
- Minimal base image (Alpine Linux)
- Regular security scanning with Trivy
- No unnecessary packages

### Network Security

- TLS/SSL enforced in production
- Rate limiting on ingress
- Internal service communication only

### Secrets Management

Never commit secrets to the repository. Use:
- Kubernetes Secrets for sensitive data
- Environment variables for configuration
- GitHub Secrets for CI/CD credentials

```bash
# Create Kubernetes secret
kubectl create secret generic mcp-secrets \
  --from-literal=api-key=your-secret-key
```

## Performance Tuning

### Resource Limits

Adjust resource requests/limits in `k8s/deployment.yaml`:

```yaml
resources:
  requests:
    memory: "256Mi"
    cpu: "200m"
  limits:
    memory: "1Gi"
    cpu: "1000m"
```

### Replica Count

```bash
# Adjust based on load
kubectl scale deployment/mcp-server --replicas=5
```

## Disaster Recovery

### Backup

```bash
# Backup persistent data
kubectl exec -it <pod-name> -- tar czf /tmp/backup.tar.gz /app/data
kubectl cp <pod-name>:/tmp/backup.tar.gz ./backup.tar.gz
```

### Restore

```bash
# Restore from backup
kubectl cp ./backup.tar.gz <pod-name>:/tmp/backup.tar.gz
kubectl exec -it <pod-name> -- tar xzf /tmp/backup.tar.gz -C /
```

## Maintenance

### Regular Tasks

1. **Update dependencies**: Monitor for security updates
2. **Review logs**: Check for errors and warnings
3. **Monitor metrics**: Track performance and usage
4. **Test backups**: Verify backup and restore procedures
5. **Update documentation**: Keep deployment docs current

### Scheduled Maintenance

```bash
# Drain node for maintenance
kubectl drain <node-name> --ignore-daemonsets

# Perform maintenance
# ...

# Uncordon node
kubectl uncordon <node-name>
```

---

## 📞 Support

For issues and questions:
- GitHub Issues: https://github.com/canstralian/parrot_mcp_server/issues
- Documentation: See `README.md` and other docs in the repository

---

**Note**: This deployment guide is for the Bash-based Parrot MCP Server. Adjust configurations and commands based on your specific environment and requirements.
