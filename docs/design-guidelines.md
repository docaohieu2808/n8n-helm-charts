# Design Guidelines

## Overview

This document outlines the design principles, patterns, and guidelines used in the n8n Kubernetes deployment. These guidelines ensure consistency, maintainability, and scalability of the system architecture.

## Design Principles

### 1. Microservices Architecture

#### Core Principle
- **Single Responsibility:** Each service has a single, well-defined purpose
- **Loose Coupling:** Services communicate through well-defined APIs
- **Independent Deployment:** Each service can be deployed independently
- **Autonomous Scaling:** Each service can scale independently based on demand

#### Service Decomposition
```yaml
# Service Responsibilities
n8n-main:
  - Web UI management
  - REST API endpoint
  - User authentication
  - Workflow coordination
  - Configuration management

n8n-webhook:
  - External webhook handling
  - Event processing
  - Queue management
  - Error handling
  - Retry mechanisms

n8n-worker:
  - Workflow execution
  - Background processing
  - Resource management
  - Logging and monitoring
  - Performance optimization
```

#### Communication Patterns
```yaml
# Synchronous Communication
Client → n8n-main (HTTP/HTTPS)
n8n-main → n8n-worker (gRPC/HTTP)
n8n-worker → External APIs (HTTP/REST)

# Asynchronous Communication
External Service → n8n-webhook (HTTP)
n8n-webhook → Redis Queue
n8n-worker → Redis Queue
n8n-worker → PostgreSQL (Results)
```

### 2. Infrastructure as Code

#### Core Principle
- **Declarative Configuration:** Use YAML for configuration
- **Version Control:** All configurations stored in Git
- **Automation:** Automated deployment and scaling
- **Reproducibility:** Consistent environments across deployments

#### Helm Chart Structure
```yaml
# Chart Organization
n8n-helm-chart/
├── Chart.yaml              # Chart metadata
├── values.yaml             # Default values
├── values.production.yaml  # Production overrides
├── values.development.yaml # Development overrides
├── templates/              # Kubernetes manifests
│   ├── configmap.yaml      # Configuration data
│   ├── deployment.yaml     # Service deployments
│   ├── hpa.yaml           # Horizontal scaling
│   ├── ingress.yaml       # Ingress configuration
│   ├── secret.yaml        # Secret management
│   ├── service.yaml       # Service definitions
│   └── ...                # Additional templates
└── charts/                # Dependencies
```

#### Configuration Management
```yaml
# Environment-specific configurations
values.base.yaml:
  global:
    namespace: n8n
  main:
    replicaCount: 1
  webhook:
    replicaCount: 2
  worker:
    replicaCount: 2

values.production.yaml:
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

### 3. High Availability Design

#### Core Principle
- **Redundancy:** Multiple instances of critical services
- **Failover:** Automatic failover mechanisms
- **Load Balancing:** Even distribution of traffic
- **Health Monitoring:** Continuous health checks

#### High Availability Patterns
```yaml
# Multi-replica Deployment
main:
  replicaCount: 2  # Stateless, can be scaled
webhook:
  replicaCount: 4  # Auto-scaled based on demand
worker:
  replicaCount: 4  # Auto-scaled based on demand

# Database HA
database:
  type: "postgresdb"
  host: "postgres-ha.database.svc.cluster.local"
  sslEnabled: "true"
  sslRejectUnauthorized: "true"

# Cache HA
redis:
  host: "redis-ha-haproxy.database.svc.cluster.local"
  queueDb: "1"
  cacheDb: "2"
```

#### Health Check Patterns
```yaml
# Liveness and Readiness Probes
livenessProbe:
  httpGet:
    path: /
    port: http
  initialDelaySeconds: 30
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3

readinessProbe:
  httpGet:
    path: /
    port: http
  initialDelaySeconds: 5
  periodSeconds: 5
  timeoutSeconds: 3
  failureThreshold: 3
```

### 4. Security-First Design

#### Core Principle
- **Zero Trust:** No implicit trust, verify everything
- **Defense in Depth:** Multiple layers of security
- **Principle of Least Privilege:** Minimal required permissions
- **Regular Updates:** Continuous security patching

#### Security Patterns
```yaml
# Network Security
networkPolicy:
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

# Data Encryption
secrets:
  encryptionKey: "32-character-encryption-key"
  postgresEncryptionKey: "32-character-encryption-key"
  redisEncryptionKey: "32-character-encryption-key"

# SSL/TLS Configuration
config:
  protocol: "https"
  host: "auto.docaohieu.com"
  port: "5678"
  sslEnabled: "true"
  sslRejectUnauthorized: "true"
```

### 5. Performance-Optimized Design

#### Core Principle
- **Resource Optimization:** Efficient resource utilization
- **Caching Strategies:** Multi-layer caching approach
- **Connection Pooling:** Efficient database connections
- **Load Balancing:** Optimal traffic distribution

#### Performance Patterns
```yaml
# Resource Allocation
main:
  resources:
    requests:
      memory: "1Gi"
      cpu: "1000m"
    limits:
      memory: "4Gi"
      cpu: "2000m"

webhook:
  resources:
    requests:
      memory: "512Mi"
      cpu: "500m"
    limits:
      memory: "2Gi"
      cpu: "1000m"

worker:
  resources:
    requests:
      memory: "512Mi"
      cpu: "500m"
    limits:
      memory: "2Gi"
      cpu: "1000m"

# Database Optimization
database:
  poolSize: "20"
  minPoolSize: "5"
  acquireTimeoutMillis: "10000"
  connectionTimeoutMillis: "5000"
  idleTimeoutMillis: "30000"
  maxUses: "7500"

# Redis Optimization
redis:
  queueDb: "1"      # Dedicated queue database
  cacheDb: "2"      # Dedicated cache database
```

## Architecture Patterns

### 1. Layered Architecture

#### Presentation Layer
```yaml
# Ingress and Load Balancing
ingress:
  enabled: true
  className: traefik-ingress
  annotations:
    traefik.ingress.kubernetes.io/preserve-host: "true"
  host: auto.docaohieu.com
  webhookPaths:
    - /webhook
    - /webhook-test
    - /webhook-waiting
```

#### API Layer
```yaml
# n8n-main Service
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

#### Business Logic Layer
```yaml
# n8n-webhook and n8n-worker Services
webhook:
  replicaCount: 2
  autoscaling:
    enabled: true
    minReplicas: 2
    maxReplicas: 8
    targetCPUUtilizationPercentage: 70
    targetMemoryUtilizationPercentage: 80

worker:
  replicaCount: 2
  autoscaling:
    enabled: true
    minReplicas: 2
    maxReplicas: 6
    targetCPUUtilizationPercentage: 70
    targetMemoryUtilizationPercentage: 80
```

#### Data Layer
```yaml
# Database and Cache Services
database:
  type: "postgresdb"
  host: "postgres-ha.database.svc.cluster.local"
  port: "5432"
  name: "n8n_postgres_db"
  user: "n8n_postgres_user"
  poolSize: "20"

redis:
  host: "redis-ha-haproxy.database.svc.cluster.local"
  port: "6379"
  queueDb: "1"
  cacheDb: "2"
```

### 2. Service-Oriented Architecture

#### Service Decomposition
```yaml
# Service Boundaries
n8n-main:
  - Public-facing API
  - User interface
  - Authentication
  - Configuration management
  - Workflow coordination

n8n-webhook:
  - External webhook handling
  - Event processing
  - Queue management
  - Error handling
  - Retry mechanisms

n8n-worker:
  - Workflow execution
  - Background processing
  - Resource management
  - Logging and monitoring
```

#### Service Communication
```yaml
# Internal Communication
n8n-main → n8n-worker: gRPC/HTTP (workflow execution)
n8n-main → n8n-webhook: HTTP (webhook management)
n8n-webhook → Redis: Queue (event queuing)
n8n-worker → Redis: Queue (event consumption)
n8n-worker → PostgreSQL: JDBC (data persistence)
```

### 3. Event-Driven Architecture

#### Event Flow
```yaml
# Event Processing Flow
External Service → n8n-webhook → Redis Queue → n8n-worker → External APIs
                                   ↓
                               PostgreSQL Results
```

#### Event Processing Patterns
```yaml
# Queue Configuration
redis:
  queueDb: "1"      # Dedicated queue database
  cacheDb: "2"      # Dedicated cache database

# Execution Configuration
executions:
  mode: "queue"                    # Queue-based execution
  dataSaveOnError: "all"           # Save all error data
  dataSaveOnSuccess: "none"        # Don't save success data
  dataSaveManualExecutions: "true" # Save manual executions
  dataPrune: "true"                # Enable data cleanup
  dataMaxAge: "336"                # 14 days retention
```

### 4. Caching Architecture

#### Multi-Layer Caching
```yaml
# Cache Hierarchy
Browser Cache → n8n Cache → Redis Cache → Database Cache
               ↓              ↓              ↓
             Static         Session       Query
            Resources       Data          Cache
```

#### Cache Configuration
```yaml
# Redis Cache Configuration
redis:
  host: "redis-ha-haproxy.database.svc.cluster.local"
  port: "6379"
  queueDb: "1"      # Queue database
  cacheDb: "2"      # Cache database

# n8n Cache Configuration
cache:
  enabled: "true"
  jwtCacheEnabled: "true"
```

## Design Patterns

### 1. Circuit Breaker Pattern

#### Implementation
```yaml
# Circuit Breaker Configuration
config:
  executions:
    mode: "queue"                    # Queue-based execution
    retryForExecutionErrors: "true"   # Enable retry mechanisms
    maxExecutionRetries: "3"          # Maximum retry attempts
    waitBetweenRetries: "3600"        # Wait between retries (seconds)
```

#### Usage
```bash
# Circuit breaker handles database connection failures
# n8n-worker automatically retries failed executions
# After max retries, execution marked as failed
# Failed executions stored in PostgreSQL for review
```

### 2. Retry Pattern

#### Implementation
```yaml
# Retry Configuration
config:
  executions:
    retryForExecutionErrors: "true"   # Enable retry mechanisms
    maxExecutionRetries: "3"          # Maximum retry attempts
    waitBetweenRetries: "3600"        # Wait between retries (seconds)
    continueOnFail: "false"          # Stop on failure
```

#### Usage
```bash
# Retry workflow executions on transient failures
# Exponential backoff between retries
# Maximum retry attempts configured
# Failed executions logged for debugging
```

### 3. Bulkhead Pattern

#### Implementation
```yaml
# Resource Isolation
main:
  resources:
    requests:
      memory: "1Gi"
      cpu: "1000m"
    limits:
      memory: "4Gi"
      cpu: "2000m"

webhook:
  resources:
    requests:
      memory: "512Mi"
      cpu: "500m"
    limits:
      memory: "2Gi"
      cpu: "1000m"

worker:
  resources:
    requests:
      memory: "512Mi"
      cpu: "500m"
    limits:
      memory: "2Gi"
      cpu: "1000m"
```

#### Usage
```bash
# Each service has dedicated resource limits
# Resource contention prevented between services
# Isolated failure domains
# Independent scaling per service
```

### 4. Observer Pattern

#### Implementation
```yaml
# Monitoring and Observability
metrics:
  enabled: "true"
  includeDefaultMetrics: "true"
  includeWorkflowIdLabel: "true"
  includeNodeTypeLabel: "true"

logging:
  level: "warn"
  output: "console"
```

#### Usage
```bash
# Real-time metrics collection
# Structured logging for debugging
# Performance monitoring
# Error tracking and alerting
```

## Design Guidelines

### 1. Configuration Management

#### Environment-Specific Configurations
```yaml
# values.base.yaml (Default)
global:
  namespace: n8n

# values.development.yaml (Development)
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

# values.production.yaml (Production)
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
```

#### Configuration Validation
```bash
# Validate configuration files
helm lint ./n8n-helm-chart

# Test configuration rendering
helm template n8n ./n8n-helm-chart --values values.custom.yaml > /dev/null

# Verify configuration values
kubectl get configmap n8n-config -n n8n -o yaml
```

### 2. Security Guidelines

#### Network Security
```yaml
# Network Policies
networkPolicy:
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

#### Data Security
```yaml
# Encryption Configuration
secrets:
  encryptionKey: "32-character-encryption-key"
  postgresEncryptionKey: "32-character-encryption-key"
  redisEncryptionKey: "32-character-encryption-key"

# SSL/TLS Configuration
config:
  protocol: "https"
  host: "auto.docaohieu.com"
  port: "5678"
  sslEnabled: "true"
  sslRejectUnauthorized: "true"
```

### 3. Performance Guidelines

#### Resource Allocation
```yaml
# Right-sizing Resources
main:
  resources:
    requests:
      memory: "1Gi"
      cpu: "1000m"
    limits:
      memory: "4Gi"
      cpu: "2000m"

webhook:
  resources:
    requests:
      memory: "512Mi"
      cpu: "500m"
    limits:
      memory: "2Gi"
      cpu: "1000m"

worker:
  resources:
    requests:
      memory: "512Mi"
      cpu: "500m"
    limits:
      memory: "2Gi"
      cpu: "1000m"
```

#### Database Optimization
```yaml
# Connection Pooling
database:
  poolSize: "20"
  minPoolSize: "5"
  acquireTimeoutMillis: "10000"
  connectionTimeoutMillis: "5000"
  idleTimeoutMillis: "30000"
  maxUses: "7500"
```

### 4. Monitoring Guidelines

#### Health Checks
```yaml
# Liveness and Readiness Probes
livenessProbe:
  httpGet:
    path: /
    port: http
  initialDelaySeconds: 30
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3

readinessProbe:
  httpGet:
    path: /
    port: http
  initialDelaySeconds: 5
  periodSeconds: 5
  timeoutSeconds: 3
  failureThreshold: 3
```

#### Metrics Collection
```yaml
# Metrics Configuration
metrics:
  enabled: "true"
  includeDefaultMetrics: "true"
  includeWorkflowIdLabel: "true"
  includeNodeTypeLabel: "true"

logging:
  level: "warn"
  output: "console"
```

### 5. Backup and Recovery Guidelines

#### Backup Strategy
```yaml
# Daily Backup Script
backup-daily.sh:
  # Backup PostgreSQL
  pg_dump -U n8n_postgres_user n8n_postgres_db > postgres_backup.sql

  # Backup Redis
  redis-cli BGSAVE

  # Backup Configuration
  helm get values n8n -n n8n > config_backup.yaml
```

#### Recovery Procedures
```bash
# Recovery Steps
1. Stop all services
2. Restore PostgreSQL database
3. Restore Redis database
4. Restore configuration
5. Start services
6. Verify functionality
```

## Design Decisions

### 1. Technology Stack Selection

#### Kubernetes
- **Reason:** Container orchestration, auto-scaling, self-healing
- **Benefits:** Automated operations, resource optimization, portability

#### Helm
- **Reason:** Package management for Kubernetes
- **Benefits:** Configuration management, version control, dependency management

#### PostgreSQL
- **Reason:** Relational database with strong ACID compliance
- **Benefits:** Data integrity, complex queries, transaction support

#### Redis
- **Reason:** In-memory data store for caching and queuing
- **Benefits:** Fast performance, data structures, pub/sub capabilities

#### Traefik
- **Reason:** Modern HTTP reverse proxy and load balancer
- **Benefits:** Dynamic configuration, automatic SSL, Kubernetes integration

### 2. Architecture Decisions

#### Microservices vs Monolith
- **Decision:** Microservices architecture
- **Reason:** Scalability, maintainability, independent deployment
- **Benefits:** Technology flexibility, fault isolation, independent scaling

#### Stateful vs Stateless Services
- **Decision:** Stateless services with external state
- **Reason:** Simpler scaling and deployment
- **Benefits:** Horizontal scaling, load distribution, fault tolerance

#### Queue-based Execution
- **Decision:** Redis queue for workflow execution
- **Reason:** Decoupling, reliability, scalability
- **Benefits:** Asynchronous processing, retry mechanisms, load balancing

### 3. Performance Decisions

#### Resource Allocation
- **Decision:** Conservative resource limits
- **Reason:** Cost optimization and stability
- **Benefits:** Predictable costs, stable performance, efficient resource usage

#### Connection Pooling
- **Decision:** Database connection pooling
- **Reason:** Performance optimization
- **Benefits:** Reduced connection overhead, better resource utilization

#### Caching Strategy
- **Decision:** Multi-layer caching approach
- **Reason:** Performance optimization
- **Benefits:** Reduced latency, improved throughput, better user experience

### 4. Security Decisions

#### Zero Trust Architecture
- **Decision:** Zero trust security model
- **Reason:** Enhanced security posture
- **Benefits:** Reduced attack surface, better compliance, improved security

#### Encryption at Rest and in Transit
- **Decision:** Data encryption for all sensitive data
- **Reason:** Data protection and compliance
- **Benefits:** Regulatory compliance, data protection, customer trust

#### Network Security
- **Decision:** Network policies and ingress filtering
- **Reason:** Network security and isolation
- **Benefits:** Attack prevention, network segmentation, improved security

## Conclusion

These design guidelines provide a comprehensive framework for building, maintaining, and evolving the n8n Kubernetes deployment. The guidelines ensure consistency, security, performance, and scalability across all environments.

By following these principles and patterns, the n8n deployment maintains a robust, secure, and performant architecture that meets production requirements and can adapt to changing business needs.

**Document Version:** 1.0.4
**Last Updated:** December 3, 2025
**Next Review:** March 3, 2026
**Contact:** hieudc for design questions or changes