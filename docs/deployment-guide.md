# Deployment Guide

## Overview

This deployment guide provides comprehensive instructions for deploying, upgrading, and managing the n8n Kubernetes deployment using Helm charts. The guide covers setup procedures, configuration options, and operational best practices.

## Prerequisites

### System Requirements
- **Kubernetes Cluster:** v1.25+ with RBAC enabled
- **Helm:** v3.8+
- **kubectl:** v1.25+
- **Storage Class:** Persistent storage with ReadWriteOnce access
- **Network Policy:** Ingress controller (Traefik recommended)

### Resource Requirements
```yaml
Minimum Resources:
  - Main Service: 1 CPU / 4Gi RAM
  - Webhook Service: 2 CPU / 4Gi RAM (auto-scaled)
  - Worker Service: 2 CPU / 4Gi RAM (auto-scaled)
  - Database: 20GB persistent storage
  - Cache: 10GB persistent storage
  - Total: ~5 CPU / 12Gi RAM minimum
```

### Storage Requirements
```yaml
Storage Classes:
  - Primary: nfs-client (ReadWriteOnce)
  - Backup: Storage class with snapshot support
  - Size:
    - PostgreSQL: 20GB
    - Redis: 10GB
    - Total: 30GB minimum
```

## Initial Deployment

### 1. Repository Setup

#### Clone the Repository
```bash
git clone <repository-url>
cd n8n
```

#### Verify Repository Structure
```bash
ls -la
# Expected output:
# ├── n8n-helm-chart/
# ├── docs/
# ├── backups/
# ├── .repomixignore
# └── CLAUDE.md
```

### 2. Environment Preparation

#### Create Namespace
```bash
kubectl create namespace n8n
kubectl config set-context --current --namespace=n8n
```

#### Verify Cluster Access
```bash
kubectl cluster-info
kubectl get nodes
```

### 3. Database Preparation

#### PostgreSQL Setup
```bash
# Verify PostgreSQL HA service is available
kubectl get services -n database
kubectl get pods -n database

# Test database connectivity
kubectl run -i --tty --rm debug --image=postgres:15 --restart=Never -- psql postgresql://n8n_postgres_user:password@postgres-ha.database.svc.cluster.local:5432/n8n_postgres_db
```

#### Redis Setup
```bash
# Verify Redis HA service is available
kubectl get services -n database
kubectl get pods -n database

# Test Redis connectivity
kubectl run -i --tty --rm debug --image=redis:7 --restart=Never -- redis-cli -h redis-ha-haproxy.database.svc.cluster.local -p 6379 ping
```

### 4. Helm Chart Installation

#### Chart Validation
```bash
# Validate Helm chart
helm lint ./n8n-helm-chart

# Dry run installation
helm upgrade --install n8n ./n8n-helm-chart --dry-run --debug

# Dry run installation with namespace
helm upgrade --install n8n ./n8n-helm-chart --namespace n8n --create-namespace --dry-run
```

#### Initial Deployment
```bash
# Install n8n with default configuration
helm upgrade --install n8n ./n8n-helm-chart \
  --namespace n8n \
  --create-namespace \
  --wait \
  --timeout=300s
```

#### Verify Installation
```bash
# Check pods status
kubectl get pods -n n8n

# Check services status
kubectl get services -n n8n

# Check ingress status
kubectl get ingress -n n8n

# Check deployments
kubectl get deployments -n n8n
```

### 5. Configuration Verification

#### Test Service Connectivity
```bash
# Test n8n main service
kubectl port-forward svc/n8n-main 5678:80 -n n8n &
curl http://localhost:5678/

# Test webhook service
kubectl port-forward svc/n8n-webhook 5678:80 -n n8n &
curl http://localhost:5678/webhook-test/

# Test HTTPS connectivity
curl -k https://auto.docaohieu.com/
```

#### Test Database Connectivity
```bash
# Test PostgreSQL connection from n8n pod
kubectl exec -it deployment/n8n-main -n n8n -- psql postgresql://n8n_postgres_user:password@postgres-ha.database.svc.cluster.local:5432/n8n_postgres_db -c "SELECT 1;"

# Test Redis connection from n8n pod
kubectl exec -it deployment/n8n-main -n n8n -- redis-cli -h redis-ha-haproxy.database.svc.cluster.local -p 6379 ping
```

## Configuration Management

### 1. Configuration Overview

#### Core Configuration File
```yaml
# File: n8n-helm-chart/values.yaml
global:
  namespace: n8n

main:
  replicaCount: 1
  image:
    repository: n8nio/n8n
    tag: "1.123.1"
  resources:
    requests:
      memory: "1Gi"
      cpu: "1000m"
    limits:
      memory: "4Gi"
      cpu: "2000m"
```

#### Key Configuration Sections
```yaml
# Application Configuration
config:
  host: "auto.docaohieu.com"
  port: "5678"
  protocol: "https"
  timezone: "Asia/Ho_Chi_Minh"

# Database Configuration
database:
  type: "postgresdb"
  host: "postgres-ha.database.svc.cluster.local"
  port: "5432"
  name: "n8n_postgres_db"
  user: "n8n_postgres_user"

# Redis Configuration
redis:
  host: "redis-ha-haproxy.database.svc.cluster.local"
  port: "6379"
  queueDb: "1"
  cacheDb: "2"
```

### 2. Custom Configuration

#### Environment-Specific Configuration
```yaml
# values.production.yaml
global:
  namespace: n8n

main:
  replicaCount: 2
  resources:
    requests:
      memory: "2Gi"
      cpu: "2000m"
    limits:
      memory: "8Gi"
      cpu: "4000m"

webhook:
  replicaCount: 4
  autoscaling:
    minReplicas: 4
    maxReplicas: 16

worker:
  replicaCount: 4
  autoscaling:
    minReplicas: 4
    maxReplicas: 12
```

#### Custom Values File Usage
```bash
# Deploy with custom values
helm upgrade --install n8n ./n8n-helm-chart \
  --namespace n8n \
  --values values.production.yaml \
  --wait \
  --timeout=300s

# Merge multiple values files
helm upgrade --install n8n ./n8n-helm-chart \
  --namespace n8n \
  --values values.base.yaml \
  --values values.production.yaml \
  --values values.custom.yaml \
  --wait
```

### 3. Configuration Validation

#### Validate Configuration
```bash
# Test configuration rendering
helm template n8n ./n8n-helm-chart --values values.custom.yaml > /dev/null

# Validate resource allocation
kubectl get deployment n8n-main -n n8n -o yaml | grep resources

# Check service configuration
kubectl get service n8n-main -n n8n -o yaml
```

## System Upgrades

### 1. Pre-Upgrade Preparation

#### Backup Strategy
```bash
# Create backup script
cat > backup-system.sh << 'EOF'
#!/bin/bash

# Backup PostgreSQL
kubectl exec -n database deployment/postgres-ha-primary -- pg_dump -U n8n_postgres_user n8n_postgres_db > n8n_postgres_backup_$(date +%Y%m%d_%H%M%S).sql

# Backup Redis
kubectl exec -n database deployment/redis-ha-master -- redis-cli BGSAVE

# Backup n8n configuration
helm get values n8n -n n8n > n8n_config_backup_$(date +%Y%m%d_%H%M%S).yaml

echo "Backup completed: $(date)"
EOF

chmod +x backup-system.sh
./backup-system.sh
```

#### Health Check
```bash
# Verify system health before upgrade
kubectl get pods -n n8n
kubectl get services -n n8n
kubectl get ingress -n n8n

# Test service health
curl -k https://auto.docaohieu.com/
curl -k https://auto.docaohieu.com/webhook-test/
```

### 2. Upgrade Process

#### Version Upgrade (Current: 1.123.1)
```bash
# Update chart version in Chart.yaml
vim n8n-helm-chart/Chart.yaml
# version: 1.0.5 (increment chart version)

# Update n8n version
vim n8n-helm-chart/values.yaml
# tag: "1.123.1" (update to new version)

# Perform upgrade
helm upgrade --install n8n ./n8n-helm-chart \
  --namespace n8n \
  --wait \
  --timeout=300s
```

#### Zero-Downtime Upgrade
```bash
# Verify rolling update
kubectl rollout status deployment/n8n-main -n n8n
kubectl rollout status deployment/n8n-webhook -n n8n
kubectl rollout status deployment/n8n-worker -n n8n

# Check pod status during upgrade
kubectl get pods -n n8n -w

# Verify service health after upgrade
curl -k https://auto.docaohieu.com/
curl -k https://auto.docaohieu.com/webhook-test/
```

### 3. Post-Upgrade Validation

#### Health Verification
```bash
# Verify all pods are running
kubectl get pods -n n8n

# Verify all services are healthy
kubectl get services -n n8n

# Verify ingress is working
kubectl get ingress -n n8n

# Test connectivity
curl -k https://auto.docaohieu.com/
```

#### Performance Verification
```bash
# Check resource usage
kubectl top pods -n n8n

# Check deployment status
kubectl get deployments -n n8n

# Test service response time
curl -w "@curl-format.txt" -o /dev/null -s https://auto.docaohieu.com/
```

## Configuration Management

### 1. Environment-Specific Deployments

#### Development Environment
```yaml
# values.dev.yaml
global:
  namespace: n8n-dev

main:
  replicaCount: 1
  resources:
    requests:
      memory: "512Mi"
      cpu: "500m"
    limits:
      memory: "1Gi"
      cpu: "1000m"

webhook:
  replicaCount: 1
  autoscaling:
    enabled: false
    minReplicas: 1
    maxReplicas: 1

worker:
  replicaCount: 1
  autoscaling:
    enabled: false
    minReplicas: 1
    maxReplicas: 1
```

#### Production Environment
```yaml
# values.prod.yaml
global:
  namespace: n8n-prod

main:
  replicaCount: 2
  resources:
    requests:
      memory: "2Gi"
      cpu: "2000m"
    limits:
      memory: "8Gi"
      cpu: "4000m"

webhook:
  replicaCount: 4
  autoscaling:
    enabled: true
    minReplicas: 4
    maxReplicas: 16

worker:
  replicaCount: 4
  autoscaling:
    enabled: true
    minReplicas: 4
    maxReplicas: 12
```

### 2. Secret Management

#### Create Secrets
```bash
# Create secret from file
kubectl create secret generic n8n-secrets \
  --from-file=postgres-password=postgres-password.txt \
  --from-file=postgres-user=postgres-user.txt \
  --from-file=postgres-db=postgres-db.txt \
  --from-file=encryption-key=encryption-key.txt \
  -n n8n

# Create secret from literal values
kubectl create secret generic n8n-secrets \
  --from-literal=postgres-password="your-password" \
  --from-literal=encryption-key="your-encryption-key" \
  -n n8n
```

#### Update Secrets
```bash
# Update existing secret
kubectl create secret generic n8n-secrets \
  --from-literal=postgres-password="new-password" \
  --from-literal=encryption-key="new-encryption-key" \
  --dry-run=client -o yaml | kubectl apply -f - -n n8n
```

## Monitoring and Maintenance

### 1. System Monitoring

#### Resource Monitoring
```bash
# Monitor resource usage
kubectl top pods -n n8n

# Monitor deployments
kubectl get deployments -n n8n

# Monitor pods
kubectl get pods -n n8n

# Monitor services
kubectl get services -n n8n
```

#### Log Monitoring
```bash
# View application logs
kubectl logs -f deployment/n8n-main -n n8n

# View webhook logs
kubectl logs -f deployment/n8n-webhook -n n8n

# View worker logs
kubectl logs -f deployment/n8n-worker -n n8n

# View all logs
kubectl logs -f deployment/n8n-main -n n8n | grep -i error
```

### 2. Health Checks

#### Service Health Verification
```bash
# Check service health
kubectl get endpoints -n n8n

# Check pod health
kubectl describe pod -n n8n <pod-name>

# Check deployment health
kubectl describe deployment -n n8n <deployment-name>
```

#### External Health Checks
```bash
# Test HTTPS connectivity
curl -k -I https://auto.docaohieu.com/

# Test webhook endpoint
curl -k -I https://auto.docaohieu.com/webhook-test/

# Test API health
curl -k https://auto.docaohieu.com/
```

### 3. Backup and Recovery

#### Daily Backup Script
```bash
#!/bin/bash
# backup-daily.sh

DATE=$(date +%Y%m%d_%H%M%S)
NAMESPACE="n8n"
BACKUP_DIR="/backups/n8n"

# Create backup directory
mkdir -p $BACKUP_DIR

# Backup n8n configuration
helm get values n8n -n $NAMESPACE > $BACKUP_DIR/n8n_config_$DATE.yaml

# Backup PostgreSQL
kubectl exec -n database deployment/postgres-ha-primary -- pg_dump -U n8n_postgres_user n8n_postgres_db > $BACKUP_DIR/postgres_$DATE.sql

# Backup Redis
kubectl exec -n database deployment/redis-ha-master -- redis-cli BGSAVE
kubectl cp -n database $(kubectl get pods -n database -l app=redis-ha-master -o jsonpath='{.items[0].metadata.name}'):/data/dump.rdb $BACKUP_DIR/redis_$DATE.rdb

echo "Backup completed: $DATE"
```

#### Recovery Procedure
```bash
#!/bin/bash
# recovery.sh

DATE=$1
NAMESPACE="n8n"
BACKUP_DIR="/backups/n8n"

# Verify backup exists
if [ ! -f "$BACKUP_DIR/n8n_config_$DATE.yaml" ]; then
    echo "Backup not found: $BACKUP_DIR/n8n_config_$DATE.yaml"
    exit 1
fi

# Restore configuration
helm upgrade --install n8n ./n8n-helm-chart \
  --namespace $NAMESPACE \
  --values $BACKUP_DIR/n8n_config_$DATE.yaml \
  --wait

# Restore PostgreSQL
kubectl exec -n database deployment/postgres-ha-primary -- psql -U n8n_postgres_user n8n_postgres_db < $BACKUP_DIR/postgres_$DATE.sql

# Restore Redis
kubectl cp -n database $BACKUP_DIR/redis_$DATE.rdb $(kubectl get pods -n database -l app=redis-ha-master -o jsonpath='{.items[0].metadata.name}'):/data/dump.rdb
kubectl exec -n database deployment/redis-ha-master -- redis-cli CONFIG SET dir /data
kubectl exec -n database deployment/redis-ha-master -- redis-cli CONFIG SET dbfilename dump.rdb
kubectl exec -n database deployment/redis-ha-master -- redis-cli BGSAVE

echo "Recovery completed: $DATE"
```

## Troubleshooting

### 1. Common Issues

#### Pod Issues
```bash
# Check pod status
kubectl get pods -n n8n

# Check pod events
kubectl describe pod -n n8n <pod-name>

# Check pod logs
kubectl logs -n n8n <pod-name>

# Check pod resource usage
kubectl describe pod -n n8n <pod-name> | grep -i memory
```

#### Service Issues
```bash
# Check service status
kubectl get services -n n8n

# Check endpoint status
kubectl get endpoints -n n8n

# Check service logs
kubectl logs -n n8n <service-name>
```

#### Network Issues
```bash
# Check network policies
kubectl get networkpolicies -n n8n

# Check ingress status
kubectl get ingress -n n8n

# Test network connectivity
kubectl exec -it deployment/n8n-main -n n8n -- curl -I http://n8n-webhook.n8n.svc.cluster.local:80
```

### 2. Debug Mode

#### Enable Debug Logging
```yaml
# values.debug.yaml
config:
  logging:
    level: "debug"
    output: "console"

main:
  resources:
    requests:
      memory: "2Gi"
      cpu: "2000m"
    limits:
      memory: "4Gi"
      cpu: "4000m"
```

#### Debug Commands
```bash
# Enable debug deployment
helm upgrade --install n8n ./n8n-helm-chart \
  --namespace n8n \
  --values values.debug.yaml \
  --wait

# View debug logs
kubectl logs -f deployment/n8n-main -n n8n | grep -i debug

# Check resource usage
kubectl top pods -n n8n
```

### 3. Rollback Procedures

#### Rollback Deployment
```bash
# Get previous release versions
helm history n8n -n n8n

# Rollback to previous version
helm rollback n8n <previous-version> -n n8n

# Verify rollback
kubectl get deployments -n n8n
```

#### Emergency Procedures
```bash
# Emergency stop all services
kubectl scale deployment --replicas=0 -n n8n

# Emergency start main service
kubectl scale deployment --replicas=1 n8n-main -n n8n

# Check service status
kubectl get pods -n n8n
```

## Security Considerations

### 1. Security Best Practices

#### Network Security
```yaml
# Enable network policies
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: n8n-network-policy
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: ingress-nginx
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              name: database
```

#### Security Scanning
```bash
# Scan for vulnerabilities
trivy image n8nio/n8n:1.123.1

# Scan configuration
helm template n8n ./n8n-helm-chart | kubeval --strict

# Check for secrets
kubectl get secrets -n n8n -o yaml | grep -i password
```

### 2. Compliance Requirements

#### Data Protection
- Encryption at rest and in transit
- Regular security updates
- Access control logging
- Data retention policies

#### Compliance Monitoring
```bash
# Monitor compliance
kubectl get configmap -n n8n -o yaml

# Check security configurations
kubectl get secret -n n8n -o yaml

# Monitor access logs
kubectl logs -n n8n deployment/n8n-main | grep -i access
```

## Performance Optimization

### 1. Resource Optimization

#### Right-sizing Resources
```yaml
# values.optimized.yaml
main:
  resources:
    requests:
      memory: "1.5Gi"
      cpu: "1500m"
    limits:
      memory: "6Gi"
      cpu: "3000m"

webhook:
  resources:
    requests:
      memory: "768Mi"
      cpu: "750m"
    limits:
      memory: "3Gi"
      cpu: "1500m"

worker:
  resources:
    requests:
      memory: "768Mi"
      cpu: "750m"
    limits:
      memory: "3Gi"
      cpu: "1500m"
```

#### Horizontal Pod Autoscaler
```bash
# Verify HPA status
kubectl get hpa -n n8n

# Check HPA metrics
kubectl describe hpa n8n-webhook -n n8n
```

### 2. Database Optimization

#### Connection Pooling
```yaml
# Database optimization values
database:
  poolSize: "25"
  minPoolSize: "8"
  acquireTimeoutMillis: "15000"
  connectionTimeoutMillis: "8000"
  idleTimeoutMillis: "45000"
  maxUses: "10000"
```

#### Query Optimization
```bash
# Monitor database performance
kubectl exec -n database deployment/postgres-ha-primary -- psql -U n8n_postgres_user -c "SELECT query, calls, total_time FROM pg_stat_statements ORDER BY total_time DESC LIMIT 10;"

# Monitor database connections
kubectl exec -n database deployment/postgres-ha-primary -- psql -U n8n_postgres_user -c "SELECT count(*) FROM pg_stat_activity;"
```

## Conclusion

This deployment guide provides comprehensive instructions for deploying, managing, and optimizing the n8n Kubernetes deployment. The guide covers initial setup, configuration management, upgrades, monitoring, troubleshooting, and security best practices.

Following these procedures ensures a reliable, secure, and performant n8n deployment that meets production requirements. Regular maintenance and monitoring are essential to maintain system health and performance.

**Document Version:** 1.0.4
**Last Updated:** December 3, 2025
**Next Review:** March 3, 2026
**Contact:** hieudc for deployment assistance