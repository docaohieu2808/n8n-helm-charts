# System Architecture Documentation

## Overview

This document provides a comprehensive overview of the n8n Kubernetes deployment system architecture, including component interactions, data flow patterns, infrastructure design, and operational considerations.

## Architecture Overview

### High-Level Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                           EXTERNAL SERVICES                                   │
│                                                                             │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────┐ │
│  │   Web Clients   │  │   Third APIs   │  │   Webhooks     │  │   CLI/SDK   │ │
│  │                 │  │                 │  │                │  │             │ │
│  │ - Dashboard UI  │  │ - OAuth        │  │ - External     │  │ - Admin     │ │
│  │ - API Clients   │  │ - REST APIs    │  │   Services    │  │   Scripts   │ │
│  │ - Mobile Apps   │  │ - Web Services │  │ - Git Events   │  │ - Dev Tools │ │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  └─────────────┘ │
│                  │            │                │              │              │
│                  ▼            ▼                ▼              ▼              │
│  ┌─────────────────────────────────────────────────────────────────────────┐ │
│  │                         TRAEFIK INGRESS                                   │ │
│  │                          (auto.docaohieu.com)                            │ │
│  │                                                                         │ │
│  │  HTTPS  │  HTTPS  │  HTTPS  │  HTTPS  │  HTTPS  │  HTTPS  │  HTTPS       │ │
│  └─────────────────────────────────────────────────────────────────────────┘ │
│                                    │                                         │
│                                    ▼                                         │
│  ┌─────────────────────────────────────────────────────────────────────────┐ │
│  │                           KUBERNETES CLUSTER                             │ │
│  │                                                                         │ │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐        │ │
│  │  │   n8n-main     │  │  n8n-webhook    │  │   n8n-worker   │        │ │
│  │  │   Service      │  │   Service      │  │   Service      │        │ │
│  │  │                 │  │                 │  │                 │        │ │
│  │  │ • UI/API       │  │ • Webhook      │  │ • Background   │        │ │
│  │  │ • Workflow     │  │ • Event        │  │   Processing   │        │ │
│  │  │   Management   │  │   Handling     │  │ • Queue        │        │ │
│  │  │ • 1 Replica    │  │ • 2 Replicas   │  │ • 2 Replicas   │        │ │
│  │  │ • 4Gi Memory   │  │ • 2Gi Memory   │  │ • 2Gi Memory   │        │ │
│  │  └─────────────────┘  └─────────────────┘  └─────────────────┘        │ │
│  │         │                  │                  │                       │ │
│  │         │                  │                  │                       │ │
│  └─────────┼──────────────────┼──────────────────┼───────────────────────┘ │
│            │                  │                  │                       │
│            ▼                  ▼                  ▼                       │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐        │ │
│  │   PostgreSQL    │  │     Redis      │  │     Volume      │        │ │
│  │     HA          │  │     HA         │  │     Storage     │        │ │
│  │                 │  │                 │  │                 │        │ │
│  │ • Primary/      │  │ • Master/      │  │ • 20GB PG      │        │ │
│  │   Replica       │  │   Replica      │  │     Storage    │        │ │
│  │ • 20GB Storage  │  │ • 10GB Storage │  │ • 10GB Redis    │        │ │
│  │ • Connection    │  │ • Session      │  │                 │        │ │
│  │   Pooling       │  │   Store        │  │                 │        │ │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘        │ │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────────┘
```

## Component Deep Dive

### 1. Main Service (n8n-main)

#### Purpose and Functionality
- **Primary Role:** Central UI/API hub for n8n operations
- **Key Functions:**
  - Web UI for workflow management
  - REST API for external integrations
  - Workflow execution coordination
  - User authentication and authorization
  - Configuration management

#### Technical Specifications
```yaml
Resource Allocation:
  Replicas: 1
  Memory: 1Gi (request) / 4Gi (limit)
  CPU: 1000m (request) / 2000m (limit)
  Storage: Ephemeral (data via volume mounts)

Networking:
  Service Type: ClusterIP
  Port: 80 (external) → 5678 (internal)
  Protocol: TCP
  Ingress: HTTPS via Traefik

Health Checks:
  Liveness Probe: HTTP GET / (30s initial, 10s period)
  Readiness Probe: HTTP GET / (5s initial, 5s period)
```

#### Data Flow Patterns
```
Client Request → Traefik Ingress → n8n-main Service → n8n-main Pod
                                                    ↓
                                               PostgreSQL (Queries)
                                                    ↓
                                               Redis (Cache)
                                                    ↓
                                               n8n-worker (Execution)
```

### 2. Webhook Service (n8n-webhook)

#### Purpose and Functionality
- **Primary Role:** Dedicated webhook processing and event handling
- **Key Functions:**
  - External webhook reception
  - Event queue management
  - Webhook payload validation
  - Event routing to workflows
  - Error handling and retries

#### Technical Specifications
```yaml
Resource Allocation:
  Replicas: 2 (auto-scalable 2-8)
  Memory: 512Mi (request) / 2Gi (limit)
  CPU: 500m (request) / 1000m (limit)
  Autoscaling: CPU 70%, Memory 80%

Networking:
  Service Type: ClusterIP
  Port: 80 (external) → 5678 (internal)
  Protocol: TCP
  Ingress Paths: /webhook, /webhook-test, /webhook-waiting
```

#### Autoscaling Configuration
```yaml
Horizontal Pod Autoscaler:
  Min Replicas: 2
  Max Replicas: 8
  Target CPU Utilization: 70%
  Target Memory Utilization: 80%
  Scale Up Cooldown: 5 minutes
  Scale Down Cooldown: 10 minutes
```

### 3. Worker Service (n8n-worker)

#### Purpose and Functionality
- **Primary Role:** Background workflow execution and processing
- **Key Functions:**
  - Workflow job processing
  - Queue consumption
  - Resource management
  - Execution logging
  - Performance optimization

#### Technical Specifications
```yaml
Resource Allocation:
  Replicas: 2 (auto-scalable 2-6)
  Memory: 512Mi (request) / 2Gi (limit)
  CPU: 500m (request) / 1000m (limit)
  Autoscaling: CPU 70%, Memory 80%

Networking:
  Service Type: ClusterIP
  Port: 5678 (internal only)
  Protocol: TCP
  Internal Access: n8n-main and n8n-webhook
```

### 4. Database Layer (PostgreSQL HA)

#### Architecture Design
```
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│   Primary DB   │  │   Replica DB    │  │   Replica DB   │
│                 │  │                 │  │                 │
│ • Read/Write   │  │ • Read Only     │  │ • Read Only     │
│ • Sync Replic. │  │ • Async Replic.│  │ • Async Replic.│
│ • 20GB Storage │  │ • 20GB Storage │  │ • 20GB Storage │
│ • Connection   │  │ • Connection    │  │ • Connection   │
│   Pooling      │  │   Pooling      │  │   Pooling      │
└─────────────────┘  └─────────────────┘  └─────────────────┘
        │                   │                   │
        │                   │                   │
        ▼                   ▼                   ▼
┌─────────────────────────────────────────────────────────┐
│                 Service Discovery                         │
│                 postgres-ha.database.svc.cluster.local   │
└─────────────────────────────────────────────────────────┘
```

#### Technical Specifications
```yaml
Database Configuration:
  Type: PostgreSQL 15+
  Storage: 20GB SSD
  Replication: Streaming replication
  High Availability: Patroni or similar
  Connection Pooling: 20 connections
  SSL: Enabled with certificate validation
  Backup: Daily automated, 30-day retention
```

#### Connection Pooling Configuration
```yaml
Database Connection Pool:
  Max Connections: 20
  Min Connections: 5
  Acquire Timeout: 10 seconds
  Connection Timeout: 5 seconds
  Idle Timeout: 30 seconds
  Max Uses: 7500 (before recycling)
```

### 5. Cache Layer (Redis HA)

#### Architecture Design
```
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│   Master Redis  │  │   Replica 1    │  │   Replica 2    │
│                 │  │                 │  │                 │
│ • Read/Write    │  │ • Read Only    │  │ • Read Only    │
│ • 10GB Storage  │  │ • 10GB Storage │  │ • 10GB Storage │
│ • Session Data  │  │ • Session Data │  │ • Session Data │
│ • Queue Data    │  │ • Queue Data   │  │ • Queue Data   │
└─────────────────┘  └─────────────────┘  └─────────────────┘
        │                   │                   │
        │                   │                   │
        ▼                   ▼                   ▼
┌─────────────────────────────────────────────────────────┐
│                 Service Discovery                         │
│                 redis-ha-haproxy.database.svc.cluster.local │
└─────────────────────────────────────────────────────────┘
```

#### Technical Specifications
```yaml
Redis Configuration:
  Type: Redis 7+
  Storage: 10GB SSD
  Replication: Sentinel-based HA
  Persistence: RDB snapshots
  Backup: Daily automated, 30-day retention
  Databases:
    - DB 0: Default (Session storage)
    - DB 1: Queue storage
    - DB 2: Cache storage
```

### 6. Ingress Layer (Traefik)

#### Architecture Design
```
┌─────────────────────────────────────────────────────────────────┐
│                           EXTERNAL                            │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │                        TRAEFIK                             │ │
│  │                  (Load Balancer/Proxy)                      │ │
│  │                                                             │ │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────┐  │ │
│  │  │     HTTPS       │  │     HTTPS       │  │   HTTPS     │  │ │
│  │  │   SSL/TLS       │  │   SSL/TLS       │  │   SSL/TLS   │  │ │
│  │  │   Termination   │  │   Termination   │  │ Termination │  │ │
│  │  │                 │  │                 │  │             │  │ │
│  │  │ • auto.docaohieu.com │ • api.docaohieu.com │ • ...     │  │ │
│  │  │                 │  │                 │  │             │  │ │
│  │  └─────────────────┘  └─────────────────┘  └─────────────┘  │ │
│  │                                                             │ │
│  │  ┌─────────────────────────────────────────────────────────┐ │ │
│  │  │                    RULE ENGINE                          │ │ │
│  │  │                                                         │ │ │
│  │  │  Path: /webhook      → n8n-webhook                      │ │ │
│  │  │  Path: /workflow     → n8n-main                         │ │ │
│  │  │  Path: /api         → n8n-main                         │ │ │
│  │  └─────────────────────────────────────────────────────────┘ │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                                    │                            │
│                                    ▼                            │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │                   KUBERNETES SERVICES                     │ │
│  │                                                         │ │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────┐  │ │
│  │  │  n8n-main      │  │  n8n-webhook    │  │  n8n-worker │  │ │
│  │  │  Service       │  │   Service       │  │  Service   │  │ │
│  │  └─────────────────┘  └─────────────────┘  └─────────────┘  │ │
│  └─────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

#### Technical Specifications
```yaml
Traefik Configuration:
  Load Balancer: Round Robin
  SSL: Automatic Let's Encrypt
  Health Check: HTTP GET /
  Timeouts:
    - Read Timeout: 30s
    - Write Timeout: 30s
    - Idle Timeout: 60s
```

## Data Flow Architecture

### 1. Normal Workflow Execution Flow

```
User Action → Web UI → n8n-main API → PostgreSQL (Auth/Config) → Redis (Session)
                                                                     ↓
User Workflow → n8n-worker Queue → Worker Service → External APIs → Results → PostgreSQL (Storage)
                                                                       ↓
                                                                    Redis (Cache)
```

### 2. Webhook Processing Flow

```
External Service → Webhook → Traefik → n8n-webhook → Redis (Queue)
                                                    ↓
                                               n8n-worker → Workflow Execution
                                                    ↓
                                               PostgreSQL (Results)
```

### 3. Data Persistence Flow

```
Workflow Execution → n8n-worker → PostgreSQL
                                     ↓
                                 Redis (Cache)
                                     ↓
                              n8n-main (UI)
```

## Security Architecture

### 1. Network Security
```yaml
Network Policies:
  Ingress Rules:
    - HTTPS only
    - Specific host restrictions
    - Path-based routing
  Egress Rules:
    - Database access (PostgreSQL)
    - Cache access (Redis)
    - External API calls
    - Backup services
```

### 2. Data Security
```yaml
Encryption:
  In-Transit: SSL/TLS (HTTPS)
  At-Rest:
    - PostgreSQL: TDE (if available)
    - Redis: AES-256
    - Files: AES-256
  Data Encryption:
    - Database: AES-256
    - Redis: AES-256
    - Files: AES-256
```

### 3. Access Security
```yaml
Authentication:
  - JWT-based authentication
  - Session management
  - Role-based access control
Authorization:
  - User permissions
  - Workflow access control
  - API rate limiting
```

## High Availability Architecture

### 1. Service Redundancy
- **n8n-main:** 1 replica (stateless, can be scaled)
- **n8n-webhook:** 2-8 replicas (auto-scaled)
- **n8n-worker:** 2-6 replicas (auto-scaled)
- **Database:** Multi-replica PostgreSQL
- **Cache:** Multi-replica Redis

### 2. Failover Strategy
```yaml
Failover Mechanisms:
  Database: Automatic failover with replication
  Cache: Sentinel-based automatic failover
  Services: Kubernetes pod restart and auto-scaling
  Ingress: Traefik health checks and automatic rerouting
```

### 3. Disaster Recovery
```yaml
Recovery Strategy:
  Backup: Daily automated backups
  Restore: Point-in-time recovery
  Failover: Automatic failover for critical services
  Testing: Regular disaster recovery drills
```

## Performance Architecture

### 1. Resource Optimization
```yaml
Resource Allocation:
  - Main Service: Balanced (1Gi/4Gi)
  - Webhook Service: Optimized (512Mi/2Gi)
  - Worker Service: Optimized (512Mi/2Gi)
  - Database: Connection pooling optimized
  - Cache: Dedicated databases for different use cases
```

### 2. Caching Strategy
```yaml
Caching Layers:
  - Redis: Session storage (DB 0)
  - Redis: Queue storage (DB 1)
  - Redis: Cache storage (DB 2)
  - n8n: Built-in caching
  - Browser: Cache headers
```

### 3. Load Balancing
```yaml
Load Distribution:
  - Traefik: HTTP/HTTPS traffic
  - Kubernetes Service: Internal traffic
  - Database: Connection pooling
  - Cache: Multiple databases
```

## Monitoring Architecture

### 1. Metrics Collection
```yaml
Monitoring Stack:
  - n8n: Built-in metrics
  - Kubernetes: Resource metrics
  - Database: PostgreSQL metrics
  - Cache: Redis metrics
  - Network: Traefik metrics
```

### 2. Alerting
```yaml
Alerting Rules:
  - High CPU usage
  - High memory usage
  - Database connection issues
  - Service unavailability
  - Slow response times
```

### 3. Logging
```yaml
Logging Strategy:
  - Application logs: JSON format
  - Kubernetes logs: Structured logging
  - Database logs: PostgreSQL logs
  - Cache logs: Redis logs
  - Audit logs: Security and compliance
```

## Backup Architecture

### 1. Backup Strategy
```yaml
Backup Components:
  PostgreSQL:
    - Daily full backups
    - Binary dumps
    - SQL dumps
    - 30-day retention
  Redis:
    - Daily RDB snapshots
    - 30-day retention
  Configuration:
    - Helm charts
    - Secrets
    - Ingress rules
```

### 2. Backup Verification
```yaml
Verification Process:
  - Automated backup verification
  - Backup integrity checks
  - Restore testing
  - Backup alerting
```

### 3. Backup Storage
```yaml
Storage Strategy:
  - On-cluster: PVC-based storage
  - Off-cluster: Object storage (if available)
  - Encryption: Backup encryption
  - Retention: Configurable retention periods
```

## Deployment Architecture

### 1. Deployment Strategy
```yaml
Deployment Strategy:
  - Rolling updates: Zero downtime
  - Canary deployments: For major updates
  - Blue-green deployments: For critical changes
  - Automated rollbacks: For failed deployments
```

### 2. Configuration Management
```yaml
Configuration Strategy:
  - Helm charts: Infrastructure as code
  - Values.yaml: Configuration values
  - Secrets: Secure configuration
  - ConfigMaps: Non-sensitive configuration
```

### 3. Version Management
```yaml
Version Strategy:
  - Semantic versioning: Chart versions
  - App versions: n8n versions
  - Git tags: Release management
  - Change logs: Version tracking
```

## Scalability Architecture

### 1. Horizontal Scaling
```yaml
Scaling Strategy:
  - Main Service: Manual scaling (stateless)
  - Webhook Service: Auto-scaling (2-8 replicas)
  - Worker Service: Auto-scaling (2-6 replicas)
  - Database: Read replicas for scaling
  - Cache: Multi-master scaling
```

### 2. Vertical Scaling
```yaml
Vertical Scaling:
  - Resource limits: CPU and memory
  - Storage scaling: PVC resizing
  - Database scaling: Vertical scaling
  - Cache scaling: Memory optimization
```

### 3. Load Testing
```yaml
Testing Strategy:
  - Load testing: For peak loads
  - Stress testing: For limits
  - Capacity planning: For growth
  - Performance monitoring: For optimization
```

## Architecture Principles

### 1. Design Principles
- **Scalability:** Horizontal scaling for all services
- **Availability:** Multi-replica deployment
- **Security:** Zero-trust security model
- **Performance:** Optimized resource allocation
- **Maintainability:** Infrastructure as code
- **Observability:** Comprehensive monitoring

### 2. Operational Principles
- **Automation:** Automated deployments and scaling
- **Monitoring:** Real-time monitoring and alerting
- **Backup:** Automated backups and recovery
- **Security:** Regular security updates and patches
- **Documentation:** Comprehensive documentation

### 3. Business Principles
- **Reliability:** High availability for business continuity
- **Performance:** Fast response times for user experience
- **Security:** Data protection and compliance
- **Cost:** Optimized resource usage
- **Growth:** Scalable architecture for future growth

## Conclusion

The n8n Kubernetes deployment architecture is designed to be highly available, secure, scalable, and performant. The architecture leverages Kubernetes-native features, Helm charts for configuration management, and best practices for containerized applications. The recent upgrade to n8n 1.123.1 has further enhanced the security posture and performance of the system.

The architecture is well-suited for production environments with demanding requirements for uptime, performance, and security. The combination of auto-scaling services, high-availability databases, and comprehensive monitoring ensures that the system can handle production workloads effectively.

**Architecture Review Date:** December 3, 2025
**Next Architecture Review:** March 3, 2026
**Contact:** hieudc for architecture questions or changes