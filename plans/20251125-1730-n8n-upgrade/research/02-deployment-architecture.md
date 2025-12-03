# Current Deployment Architecture Analysis

## Infrastructure Overview

### Kubernetes Cluster
- **Namespace**: n8n
- **Deployment Method**: Custom Helm Chart (local, not from Helm repo)
- **Chart Version**: 1.0.0
- **App Version**: 1.117.3 (Chart metadata - outdated)
- **Actual Running Version**: 1.119.0

### Components Architecture

#### 1. n8n-main (UI/API Server)
- **Replicas**: 2
- **Image**: n8nio/n8n:1.119.0
- **Image Pull Policy**: IfNotPresent
- **Resources**:
  - Requests: 1 CPU, 1Gi RAM
  - Limits: 2 CPU, 4Gi RAM
- **Service**: ClusterIP on port 80 → 5678
- **Metrics Port**: 9090
- **Health Checks**: startup, liveness, readiness on /healthz
- **Storage**: PVC (nfs-client, 10Gi, ReadWriteOnce)
- **Anti-Affinity**: Preferred pod spread across nodes

#### 2. n8n-webhook (Webhook Handler)
- **Replicas**: 2 (HPA managed)
- **Image**: n8nio/n8n:1.119.0
- **Resources**:
  - Requests: 500m CPU, 512Mi RAM
  - Limits: 1 CPU, 2Gi RAM
- **Service**: ClusterIP on port 80 → 5678
- **HPA**:
  - Min: 2, Max: 10
  - CPU target: 70%
  - Memory target: 80%
  - Current: 2 replicas (1% CPU, 31% memory)

#### 3. n8n-worker (Queue Worker)
- **Replicas**: 2 (HPA managed)
- **Image**: n8nio/n8n:1.119.0
- **Resources**:
  - Requests: 500m CPU, 512Mi RAM
  - Limits: 1 CPU, 2Gi RAM
- **Service**: ClusterIP on port 5678
- **HPA**:
  - Min: 2, Max: 10
  - CPU target: 70%
  - Memory target: 80%
  - Current: 2 replicas (1% CPU, 31% memory)

### External Dependencies

#### PostgreSQL HA
- **Host**: postgres-ha.database.svc.cluster.local
- **Port**: 5432
- **Database**: n8n_postgres_db
- **User**: n8n_postgres_user
- **Connection Pool**:
  - Pool Size: 20
  - Min Pool Size: 5
  - Acquire Timeout: 10s
  - Connection Timeout: 5s
  - Idle Timeout: 30s
  - Max Uses: 7500
- **SSL**: Enabled (reject unauthorized: false)

#### Redis HA
- **Host**: redis-ha-haproxy.database.svc.cluster.local
- **Port**: 6379
- **Queue DB**: 1
- **Cache DB**: 2
- **Password**: Stored in secrets

### Ingress Configuration
- **Class**: traefik-ingress
- **Host**: auto.docaohieu.com
- **Protocol**: HTTPS
- **Webhook Paths**: /webhook, /webhook-test, /webhook-waiting
- **Routing**: Webhooks → n8n-webhook-service, Others → n8n-main-service

### Configuration Management
- **ConfigMap**: n8n-config (80+ env vars)
- **Secrets**: n8n-secrets
  - Postgres password
  - Redis password
  - Encryption key
  - Redis encryption key

## Current Health Status
- All pods: Running ✓
- Webhook HPA: Healthy (low utilization)
- Worker HPA: Healthy (low utilization)
- Recent restarts observed (18 restarts on main pods over 21 days)

## Observations
1. Image tag in values.yaml is "latest" but actual deployment uses 1.119.0
2. Chart appVersion (1.117.3) doesn't match deployed version (1.119.0)
3. Many old ReplicaSets present (cleanup opportunity)
