# Code Standards and Implementation Guidelines

## Overview

This document establishes the coding standards, architecture patterns, and implementation guidelines for the n8n Kubernetes deployment. All contributions must adhere to these standards to ensure code quality, security, and maintainability.

## Repository Structure

```
/home/hieudc/n8n/
├── n8n-helm-chart/           # Main Helm chart
│   ├── Chart.yaml           # Chart metadata and version
│   ├── values.yaml          # Default configuration values
│   ├── templates/           # Kubernetes manifests
│   │   ├── configmap.yaml   # Configuration data
│   │   ├── deployment.yaml  # Service deployments
│   │   ├── hpa.yaml         # Horizontal Pod Autoscalers
│   │   ├── ingress.yaml     # Ingress configuration
│   │   ├── secret.yaml      # Secret management
│   │   ├── service.yaml     # Service definitions
│   │   └── ...              # Additional templates
│   └── charts/              # Dependency charts
├── backups/                 # Backup artifacts
│   └── 251203-2118-pre-upgrade/  # Pre-upgrade snapshot
├── docs/                    # Documentation
│   ├── project-overview-pdr.md
│   ├── code-standards.md
│   ├── codebase-summary.md
│   ├── design-guidelines.md
│   ├── deployment-guide.md
│   ├── system-architecture.md
│   └── project-roadmap.md
├── .repomixignore          # Repomix ignore patterns
├── CLAUDE.md               # Claude Code instructions
└── repomix-output.xml      # Codebase compaction
```

## Helm Chart Standards

### Version Management
- **Chart Version:** Follows semantic versioning (1.0.4)
- **App Version:** Matches n8n version (1.123.1)
- **Version Bumping:** Chart version increments on configuration changes
- **App Version:** Updates only with n8n version changes

### Chart.yaml Standards
```yaml
apiVersion: v2
name: n8n
description: A Helm chart for n8n workflow automation with separate webhook service
type: application
version: 1.0.4                    # Chart version (SemVer)
appVersion: "1.123.1"             # n8n version (string)
keywords:
  - n8n
  - workflow
  - automation
  - webhook
home: https://n8n.io
sources:
  - https://github.com/n8n-io/n8n
maintainers:
  - name: hieudc
```

### values.yaml Standards
```yaml
# Global configuration
global:
  namespace: n8n  # Fixed namespace

# Resource allocation standards
resources:
  requests:       # Minimum guaranteed resources
    memory: "1Gi"
    cpu: "1000m"
  limits:         # Maximum allowed resources
    memory: "4Gi"
    cpu: "2000m"

# Image tag standards
image:
  repository: n8nio/n8n    # Official n8n image
  tag: "1.123.1"           # Specific version tag
  pullPolicy: IfNotPresent  # Avoid unnecessary pulls
```

## Configuration Standards

### n8n Configuration Guidelines
```yaml
# Database configuration (PostgreSQL HA)
database:
  type: "postgresdb"
  host: "postgres-ha.database.svc.cluster.local"
  port: "5432"
  name: "n8n_postgres_db"
  user: "n8n_postgres_user"
  schema: "public"
  poolSize: "20"                    # Connection pooling
  sslEnabled: "true"                # SSL required
  sslRejectUnauthorized: "true"     # Strict SSL verification

# Redis configuration (Redis HA)
redis:
  host: "redis-ha-haproxy.database.svc.cluster.local"
  port: "6379"
  queueDb: "1"                     # Queue database
  cacheDb: "2"                     # Cache database

# Execution configuration
executions:
  mode: "queue"                    # Queue-based execution
  dataPrune: "true"                # Data cleanup (FIXED typo: dataPresne)
  dataMaxAge: "336"                # 14 days retention

# Security configuration
trustProxy: "1"                   # Trust proxy headers
nodeTlsRejectUnauthorized: "1"    # TLS verification
```

### Security Configuration Requirements

#### SSL/TLS Settings
```yaml
# SSL configuration (MANDATORY)
config:
  protocol: "https"               # HTTPS only
  host: "auto.docaohieu.com"     # Production domain
  port: "5678"

# SSL verification (MANDATORY)
database:
  sslEnabled: "true"              # SSL required
  sslRejectUnauthorized: "true"   # Strict certificate verification

# Redis SSL (when available)
redis:
  ssl: "true"                     # Future enhancement
```

#### Data Protection
```yaml
# Encryption keys (rotate regularly)
secrets:
  encryptionKey: "32-character-hex-key"  # AES-256 encryption
  postgresEncryptionKey: "32-char-key"  # Database encryption
  redisEncryptionKey: "32-char-key"     # Redis encryption

# Data retention
executions:
  dataPrune: "true"               # Enable data cleanup
  dataMaxAge: "336"               # 14 days retention
```

## Kubernetes Manifest Standards

### Deployment Configuration
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "n8n.fullname" . }}-main
  labels:
    {{- include "n8n.labels" . | nindent 4 }}
spec:
  replicas: 1
  selector:
    matchLabels:
      {{- include "n8n.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "n8n.selectorLabels" . | nindent 8 }}
    spec:
      {{- with .Values.affinity }}
      affinity:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      containers:
        - name: {{ .Chart.Name }}
          image: "{{ .Values.main.image.repository }}:{{ .Values.main.image.tag }}"
          imagePullPolicy: {{ .Values.main.image.pullPolicy }}
          ports:
            - name: http
              containerPort: 5678
              protocol: TCP
          resources:
            {{- toYaml .Values.main.resources | nindent 12 }}
          livenessProbe:
            httpGet:
              path: /
              port: http
            initialDelaySeconds: 30
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /
              port: http
            initialDelaySeconds: 5
            periodSeconds: 5
```

### Service Standards
```yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ include "n8n.fullname" . }}-main
  labels:
    {{- include "n8n.labels" . | nindent 4 }}
spec:
  type: {{ .Values.main.service.type }}
  ports:
    - port: {{ .Values.main.service.port }}
      targetPort: http
      protocol: TCP
      name: http
  selector:
    {{- include "n8n.selectorLabels" . | nindent 4 }}
```

### Horizontal Pod Autoscaler (HPA)
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: {{ include "n8n.fullname" . }}-webhook
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: {{ include "n8n.fullname" . }}-webhook
  minReplicas: {{ .Values.webhook.autoscaling.minReplicas }}
  maxReplicas: {{ .Values.webhook.autoscaling.maxReplicas }}
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: {{ .Values.webhook.autoscaling.targetCPUUtilizationPercentage }}
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: {{ .Values.webhook.autoscaling.targetMemoryUtilizationPercentage }}
```

## Code Quality Standards

### YAML Formatting
- Use spaces for indentation (2 spaces per level)
- Keep lines under 120 characters
- Use quotes for string values
- Follow Kubernetes YAML best practices

### Template Standards
```yaml
# Good practice: Use Helm functions
name: {{ include "n8n.fullname" . }}-main
labels:
  {{- include "n8n.labels" . | nindent 4 }}
  {{- with .Values.commonLabels }}
  {{- toYaml . | nindent 4 }}
  {{- end }}

# Use ranges for repetitive elements
{{- range $key, $value := .Values.extraEnv }}
  - name: {{ $key }}
    value: {{ $value | quote }}
{{- end }}
```

### Configuration Validation
- Use `helm lint` to validate charts
- Test deployments in staging environment
- Validate configuration values
- Check for resource conflicts

## Security Standards

### Secret Management
```yaml
# Use Kubernetes Secrets for sensitive data
apiVersion: v1
kind: Secret
metadata:
  name: {{ include "n8n.fullname" . }}-secrets
type: Opaque
data:
  postgres-password: {{ .Values.secrets.postgresPassword | b64enc }}
  postgres-user: {{ .Values.secrets.postgresUser | b64enc }}
  postgres-db: {{ .Values.secrets.postgresDb | b64enc }}
  encryption-key: {{ .Values.secrets.encryptionKey | b64enc }}
```

### Network Security
```yaml
# Network policies (when available)
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "n8n.fullname" . }}-network-policy
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
  egress:
    - to:
        - namespaceSelector: {}
      ports:
        - protocol: TCP
          port: 443
        - protocol: TCP
          port: 5432
        - protocol: TCP
          port: 6379
```

## Performance Standards

### Resource Allocation
- **Main Service:** 1Gi/4Gi (balanced between cost and performance)
- **Webhook Service:** 512Mi/2Gi (optimized for webhook handling)
- **Worker Service:** 512Mi/2Gi (optimized for batch processing)
- **Database:** 20GB storage, connection pooling enabled

### Optimization Guidelines
```yaml
# Database optimization
database:
  poolSize: "20"                    # Connection pool
  minPoolSize: "5"                  # Minimum connections
  acquireTimeoutMillis: "10000"     # Connection timeout
  connectionTimeoutMillis: "5000"   # Query timeout
  idleTimeoutMillis: "30000"        # Idle connection timeout
  maxUses: "7500"                   # Connection lifecycle

# Redis optimization
redis:
  queueDb: "1"                      # Dedicated queue database
  cacheDb: "2"                      # Dedicated cache database
```

## Testing Standards

### Helm Chart Testing
```bash
# Chart linting
helm lint ./n8n-helm-chart

# Dry run deployment
helm upgrade --install n8n-test ./n8n-helm-chart --dry-run

# Template validation
helm template n8n-test ./n8n-helm-chart > /dev/null
```

### Configuration Validation
- Validate values.yaml syntax
- Test configuration rendering
- Verify resource limits
- Check service connectivity

## Deployment Standards

### Version Control
- Use git tags for releases
- Maintain changelog in README.md
- Follow semantic versioning
- Document breaking changes

### Rollback Strategy
```bash
# Upgrade command
helm upgrade --install n8n ./n8n-helm-chart \
  --namespace n8n \
  --create-namespace \
  --wait

# Rollback command
helm rollback n8n <previous-version>
```

### Backup Standards
- Daily PostgreSQL backups
- Daily Redis backups
- Regular configuration backups
- Version-controlled release management

## Documentation Standards

### Code Comments
- Add comments for complex configurations
- Document templating logic
- Explain security considerations
- Note performance implications

### README Updates
- Keep installation instructions current
- Document configuration options
- Include troubleshooting guide
- Update version information

## Monitoring Standards

### Metrics Collection
```yaml
# Enable metrics
metrics:
  enabled: "true"
  includeDefaultMetrics: "true"
  includeWorkflowIdLabel: "true"
  includeNodeTypeLabel: "true"
```

### Health Checks
```yaml
# Liveness probe
livenessProbe:
  httpGet:
    path: /
    port: http
  initialDelaySeconds: 30
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 3

# Readiness probe
readinessProbe:
  httpGet:
    path: /
    port: http
  initialDelaySeconds: 5
  periodSeconds: 5
  timeoutSeconds: 3
  failureThreshold: 3
```

---

**Compliance Note:** All configurations must comply with Kubernetes best practices, security standards, and n8n documentation requirements.

**Review Cycle:** Standards reviewed quarterly or as needed.

**Contact:** hieudc for configuration exceptions or questions.