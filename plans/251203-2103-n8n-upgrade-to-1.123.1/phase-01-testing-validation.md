# Phase 1: Testing & Validation Procedures

## Pre-Upgrade Validation Checklist

### 1. Environment Health Check
- [ ] Cluster resources availability (CPU, Memory, Storage)
- [ ] PostgreSQL HA cluster connectivity
- [ ] Redis HA cluster connectivity
- [ ] Current n8n deployment health status
- [ ] Backup systems operational

### 2. Current Functionality Baseline
- [ ] Core workflow execution tests
- [ ] Webhook processing verification
- [ ] Database query performance baseline
- [ ] Memory usage baseline recording
- [ ] Response time benchmarks

### 3. Backup Creation & Verification
```bash
# PostgreSQL backup
kubectl exec -n database postgres-ha-0 -- pg_dump n8n_postgres_db > pre-upgrade-backup.sql

# Redis backup
kubectl exec -n database redis-ha-server-0 -- redis-cli BGSAVE

# Helm values backup
helm get values n8n -n n8n > pre-upgrade-helm-values.yaml

# Current deployment backup
kubectl get deployment,service,ingress -n n8n -o yaml > pre-upgrade-k8s-manifests.yaml
```

## Staging Environment Setup

### 1. Environment Creation
```bash
# Create staging namespace
kubectl create namespace n8n-staging

# Copy secrets from production
kubectl get secrets -n n8n -o yaml | sed 's/namespace: n8n/namespace: n8n-staging/g' | kubectl apply -f -

# Deploy staging environment
helm install n8n-staging ./n8n-helm-chart \
  --namespace n8n-staging \
  --values pre-upgrade-helm-values.yaml \
  --set global.namespace=n8n-staging \
  --set ingress.host=staging-auto.docaohieu.com
```

### 2. Sample Data Import
- [ ] Import representative workflows
- [ ] Create test webhook endpoints
- [ ] Set up monitoring dashboards
- [ ] Configure alerting rules

## Sequential Version Testing

### v1.120.4 → v1.121.0 Testing
**Focus Areas:**
- Email node compatibility verification
- Database migration success
- Workflow execution preservation

**Test Cases:**
1. **Email Node Validation**
   ```yaml
   # Test email workflow
   - node: Email
     type: n8n-nodes-base.emailSend
     parameters:
       # Verify new authentication format works
       authentication: 'basicAuth'
       host: 'smtp.example.com'
       port: 587
       secureConnection: false
   ```

2. **Database Migration Check**
   ```bash
   # Check migration logs
   kubectl logs -n n8n-staging deployment/n8n-staging-main | grep -i migration

   # Verify database schema
   kubectl exec -n n8n-staging deployment/n8n-staging-main -- \
     npx n8n db:migrate:status
   ```

### v1.121.0 → v1.122.0 Testing
**Focus Areas:**
- HTTP authentication methods
- Database connection optimizations
- Performance baseline establishment

**Test Cases:**
1. **HTTP Request Node Validation**
   ```yaml
   # Test HTTP authentication changes
   - node: HTTP Request
     type: n8n-nodes-base.httpRequest
     parameters:
       # Verify updated authentication methods
       authentication: 'headerAuth'
       headerAuth:
         name: 'Authorization'
         value: 'Bearer {{ $credentials.token }}'
   ```

2. **Performance Metrics**
   ```bash
   # Monitor memory usage
   kubectl top pods -n n8n-staging

   # Check database connection pooling
   kubectl exec -n n8n-staging deployment/n8n-staging-main -- \
     npx n8n db:pool:status
   ```

### v1.122.0 → v1.123.1 Testing
**Focus Areas:**
- Performance improvements validation
- Workflow execution speed
- Memory usage optimization

**Performance Benchmarks:**
```bash
# Memory usage comparison
kubectl exec -n n8n-staging deployment/n8n-staging-main -- \
  ps aux | grep n8n | awk '{print $6}' | sort -n

# Workflow execution timing
time curl -X POST http://staging-auto.docaohieu.com/api/v1/workflows \
  -H "Authorization: Bearer $API_TOKEN" \
  -d '{"name": "test-workflow", "nodes": []}'
```

## Integration Testing

### 1. Workflow Execution Tests
- [ ] Simple sequential workflows
- [ ] Complex branching workflows
- [ ] Error handling scenarios
- [ ] Long-running workflows
- [ ] High-frequency execution workflows

### 2. Webhook Processing Tests
```bash
# Test webhook functionality
curl -X POST http://staging-auto.docaohieu.com/webhook/test-webhook \
  -H "Content-Type: application/json" \
  -d '{"test": "data", "timestamp": "'$(date -Iseconds)'"}'

# Verify webhook processing
kubectl logs -n n8n-staging deployment/n8n-staging-webhook --tail=20
```

### 3. Database Operations Tests
- [ ] Workflow creation and retrieval
- [ ] Execution history queries
- [ ] Credential storage and retrieval
- [ ] User management operations

### 4. API Endpoint Tests
```bash
# Core API endpoints validation
ENDPOINTS=(
  "/api/v1/workflows"
  "/api/v1/credentials"
  "/api/v1/users"
  "/api/v1/executions"
)

for endpoint in "${ENDPOINTS[@]}"; do
  curl -w "\nStatus: %{http_code}\nTime: %{time_total}s\n" \
    -H "Authorization: Bearer $API_TOKEN" \
    http://staging-auto.docaohieu.com$endpoint
done
```

## Performance Validation

### 1. Memory Usage Validation
```bash
# Expected: 30% reduction in memory usage
CURRENT_MEMORY=$(kubectl exec -n n8n deployment/n8n-main -- \
  ps aux | grep n8n | awk '{sum+=$6} END {print sum}')

STAGING_MEMORY=$(kubectl exec -n n8n-staging deployment/n8n-staging-main -- \
  ps aux | grep n8n | awk '{sum+=$6} END {print sum}')

IMPROVEMENT=$(( (CURRENT_MEMORY - STAGING_MEMORY) * 100 / CURRENT_MEMORY ))
echo "Memory improvement: ${IMPROVEMENT}%"
```

### 2. Workflow Loading Speed
```bash
# Expected: 40% faster workflow loading
time curl -X GET http://staging-auto.docaohieu.com/api/v1/workflows \
  -H "Authorization: Bearer $API_TOKEN"
```

### 3. Redis Memory Footprint
```bash
# Expected: 25% reduction in Redis memory
kubectl exec -n database redis-ha-server-0 -- redis-cli info memory | grep used_memory:
```

## Rollback Testing

### 1. Application Rollback Test
```bash
# Test Helm rollback
helm rollback n8n-staging 1 -n n8n-staging

# Verify service restoration
curl -f http://staging-auto.docaohieu.com/healthz
```

### 2. Database Rollback Test
```bash
# Test database restoration (in staging only)
kubectl exec -n n8n-staging deployment/n8n-staging-main -- \
  npx n8n db:restore --file pre-upgrade-backup.sql
```

## Production Readiness Checklist

### Pre-Deployment Gates
- [ ] All staging tests passed
- [ ] Performance improvements verified
- [ ] Security issues resolved
- [ ] Rollback procedures tested
- [ ] Monitoring dashboards configured
- [ ] Alert thresholds set
- [ ] Team availability confirmed

### Deployment Window Requirements
- [ ] Low traffic period selected
- [ ] Stakeholder notification sent
- [ ] Emergency contacts verified
- [ ] Communication channels prepared

## Success Criteria Validation

### Functional Requirements
- [ ] All existing workflows execute without errors
- [ ] Webhook processing latency < 100ms
- [ ] API response times < 500ms
- [ ] UI/UX fully operational

### Performance Requirements
- [ ] Memory usage reduction ≥ 25%
- [ ] Workflow loading speed improvement ≥ 30%
- [ ] Error rate ≤ 0.1%
- [ ] Database query time improvement ≥ 20%

### Security Requirements
- [ ] SSL/TLS properly configured
- [ ] No new security vulnerabilities
- [ ] Access controls maintained
- [ ] Data encryption verified

## Documentation Updates

### Post-Testing Documentation
- [ ] Update runbook with new procedures
- [ ] Document configuration changes
- [ ] Update monitoring dashboards
- [ ] Record performance baselines
- [ ] Update disaster recovery procedures

---

**Validation Phase Duration**: 4-6 hours
**Required Team Members**: DevOps Engineer, Database Administrator, QA Engineer
**Critical Success Factor**: Complete staging environment validation before production deployment