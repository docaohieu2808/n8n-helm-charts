# n8n Upgrade Plan: 1.119.0 → 1.120.4

**Plan ID**: 20251125-1730-n8n-upgrade
**Created**: 2025-11-25 17:30
**Risk Level**: LOW
**Estimated Duration**: 30-45 minutes
**Downtime**: None (rolling update)

---

## Executive Summary

Upgrade n8n from version 1.119.0 to 1.120.4 on Kubernetes cluster. This is a low-risk patch upgrade with no breaking changes, focused on bug fixes and security patches (CVE-2025-12735).

**Key Points**:
- No breaking changes
- No database migration required
- Rolling update strategy (zero downtime)
- Security patch included (CVE-2025-12735)
- Simple image tag update

---

## Pre-Upgrade Checklist

### 1. Backup Critical Data
```bash
# Backup PostgreSQL database
kubectl exec -n database postgres-ha-0 -- \
  pg_dump -U n8n_postgres_user n8n_postgres_db > \
  n8n-backup-$(date +%Y%m%d-%H%M).sql

# Verify backup
ls -lh n8n-backup-*.sql
```

### 2. Document Current State
```bash
# Capture current deployment state
kubectl get deployment -n n8n -o yaml > deployment-backup-$(date +%Y%m%d-%H%M).yaml

# Capture current image versions
kubectl get deployments -n n8n -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.template.spec.containers[0].image}{"\n"}{end}'

# Check pod health
kubectl get pods -n n8n
kubectl get hpa -n n8n
```

### 3. Health Check
```bash
# Verify all pods running
kubectl get pods -n n8n | grep -v Running

# Check logs for errors
kubectl logs -n n8n deployment/n8n-main --tail=50
kubectl logs -n n8n deployment/n8n-webhook --tail=50
kubectl logs -n n8n deployment/n8n-worker --tail=50

# Test application access
curl -I https://auto.docaohieu.com/healthz
```

---

## Upgrade Strategy

### Option 1: Rolling Update (RECOMMENDED)
**Pros**: Zero downtime, gradual rollout, auto-rollback on failure
**Cons**: Mixed version state during update (acceptable for patch releases)
**Duration**: 15-20 minutes

### Option 2: Blue-Green Deployment
**Pros**: Instant rollback, testing before cutover
**Cons**: Requires duplicate resources, more complex
**Duration**: 30-45 minutes
**Use When**: Critical production environment, want maximum safety

### Option 3: Recreate Strategy
**Pros**: Simple, clean state
**Cons**: Downtime (5-10 minutes)
**Duration**: 10-15 minutes
**Use When**: Maintenance window available

**Selected Strategy**: Option 1 - Rolling Update

---

## Implementation Steps

### Phase 1: Preparation (5 min)

#### Step 1.1: Update Helm Chart
```bash
cd /home/hieudc/n8n/n8n-helm-chart

# Update values.yaml
# Change image.tag from "latest" to "1.120.4" for all components
```

Edit `values.yaml`:
```yaml
main:
  image:
    tag: "1.120.4"  # Change from "latest"

webhook:
  image:
    tag: "1.120.4"  # Change from "latest"

worker:
  image:
    tag: "1.120.4"  # Change from "latest"
```

#### Step 1.2: Update Chart Metadata
Edit `Chart.yaml`:
```yaml
version: 1.0.1  # Bump chart version
appVersion: "1.120.4"  # Update app version
```

#### Step 1.3: Validate Configuration
```bash
# Lint the chart
helm lint ./n8n-helm-chart

# Dry-run to preview changes
helm template n8n ./n8n-helm-chart \
  --namespace n8n \
  --values ./n8n-helm-chart/values.yaml \
  > /tmp/n8n-upgrade-preview.yaml

# Review changes
diff <(kubectl get deployment n8n-main -n n8n -o yaml) \
     <(grep -A 100 "kind: Deployment" /tmp/n8n-upgrade-preview.yaml | head -100)
```

### Phase 2: Execute Rolling Update (15-20 min)

#### Step 2.1: Update Main Deployment
```bash
# Update n8n-main
kubectl set image deployment/n8n-main \
  n8n-main=n8nio/n8n:1.120.4 \
  -n n8n

# Monitor rollout
kubectl rollout status deployment/n8n-main -n n8n --timeout=10m

# Check pod status
kubectl get pods -n n8n -l app=n8n-main
```

**Expected Output**:
```
deployment "n8n-main" successfully rolled out
NAME                        READY   STATUS    RESTARTS   AGE
n8n-main-xxxxxxxxxx-xxxxx   1/1     Running   0          2m
n8n-main-xxxxxxxxxx-xxxxx   1/1     Running   0          1m
```

#### Step 2.2: Verify Main Component
```bash
# Check logs
kubectl logs -n n8n deployment/n8n-main --tail=50

# Verify version
kubectl exec -n n8n deployment/n8n-main -- n8n --version

# Test health endpoint
curl https://auto.docaohieu.com/healthz
```

#### Step 2.3: Update Webhook Deployment
```bash
# Update n8n-webhook
kubectl set image deployment/n8n-webhook \
  n8n-webhook=n8nio/n8n:1.120.4 \
  -n n8n

# Monitor rollout
kubectl rollout status deployment/n8n-webhook -n n8n --timeout=10m

# Verify HPA still functioning
kubectl get hpa n8n-webhook-hpa -n n8n
```

#### Step 2.4: Update Worker Deployment
```bash
# Update n8n-worker
kubectl set image deployment/n8n-worker \
  n8n-worker=n8nio/n8n:1.120.4 \
  -n n8n

# Monitor rollout
kubectl rollout status deployment/n8n-worker -n n8n --timeout=10m

# Verify HPA still functioning
kubectl get hpa n8n-worker-hpa -n n8n
```

### Phase 3: Validation (5-10 min)

#### Step 3.1: Component Health Check
```bash
# Verify all deployments
kubectl get deployments -n n8n

# Check all pods running
kubectl get pods -n n8n

# Verify image versions
kubectl get deployments -n n8n \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.template.spec.containers[0].image}{"\n"}{end}'
```

**Expected Output**:
```
n8n-main     n8nio/n8n:1.120.4
n8n-webhook  n8nio/n8n:1.120.4
n8n-worker   n8nio/n8n:1.120.4
```

#### Step 3.2: Functional Testing
```bash
# Test UI access
curl -I https://auto.docaohieu.com

# Test webhook endpoint
curl -I https://auto.docaohieu.com/webhook

# Check metrics
curl https://auto.docaohieu.com:9090/metrics
```

#### Step 3.3: Database Connectivity
```bash
# Check main pod logs for DB connection
kubectl logs -n n8n deployment/n8n-main --tail=100 | grep -i database

# Check worker pod logs for queue
kubectl logs -n n8n deployment/n8n-worker --tail=100 | grep -i redis
```

#### Step 3.4: Execute Test Workflow
1. Log in to n8n UI: https://auto.docaohieu.com
2. Create simple test workflow
3. Execute manually
4. Verify webhook execution
5. Check worker processes queue

### Phase 4: Cleanup (5 min)

#### Step 4.1: Clean Old ReplicaSets
```bash
# List old ReplicaSets
kubectl get rs -n n8n

# Delete old ReplicaSets (keep last 3 per deployment)
kubectl get rs -n n8n --sort-by=.metadata.creationTimestamp | \
  grep "0         0         0" | \
  awk '{print $1}' | \
  head -n -9 | \
  xargs -I {} kubectl delete rs {} -n n8n
```

#### Step 4.2: Update Chart Record
```bash
# Optional: Apply full Helm chart for consistency
helm upgrade n8n ./n8n-helm-chart \
  --namespace n8n \
  --install \
  --create-namespace
```

**Note**: Since Helm wasn't used for initial deployment, this step creates a Helm release for future management.

---

## Rollback Plan

### Quick Rollback (2-5 min)
If issues detected immediately after upgrade:

```bash
# Rollback main
kubectl rollout undo deployment/n8n-main -n n8n
kubectl rollout status deployment/n8n-main -n n8n

# Rollback webhook
kubectl rollout undo deployment/n8n-webhook -n n8n
kubectl rollout status deployment/n8n-webhook -n n8n

# Rollback worker
kubectl rollout undo deployment/n8n-worker -n n8n
kubectl rollout status deployment/n8n-worker -n n8n

# Verify rollback
kubectl get deployments -n n8n \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.template.spec.containers[0].image}{"\n"}{end}'
```

### Full Rollback (5-10 min)
If quick rollback fails:

```bash
# Restore from backup YAML
kubectl apply -f deployment-backup-YYYYMMDD-HHMM.yaml

# Verify restoration
kubectl get pods -n n8n
kubectl get deployments -n n8n
```

### Database Rollback (Last Resort)
Only if database corruption detected:

```bash
# Restore PostgreSQL backup
kubectl exec -n database postgres-ha-0 -- \
  psql -U n8n_postgres_user -d postgres \
  -c "DROP DATABASE n8n_postgres_db;"

kubectl exec -n database postgres-ha-0 -- \
  psql -U n8n_postgres_user -d postgres \
  -c "CREATE DATABASE n8n_postgres_db OWNER n8n_postgres_user;"

cat n8n-backup-YYYYMMDD-HHMM.sql | \
  kubectl exec -i -n database postgres-ha-0 -- \
  psql -U n8n_postgres_user -d n8n_postgres_db
```

---

## Monitoring During Upgrade

### Key Metrics to Watch

#### 1. Pod Status
```bash
# Real-time pod monitoring
watch -n 2 'kubectl get pods -n n8n'
```

#### 2. Resource Utilization
```bash
# CPU/Memory usage
kubectl top pods -n n8n
```

#### 3. HPA Behavior
```bash
# Watch autoscaling
watch -n 5 'kubectl get hpa -n n8n'
```

#### 4. Application Logs
```bash
# Follow logs during upgrade
kubectl logs -n n8n deployment/n8n-main -f
```

### Alert Conditions
Monitor for:
- ❌ Pod CrashLoopBackOff
- ❌ ImagePullBackOff
- ❌ Readiness probe failures
- ❌ Error rate spike in logs
- ❌ Database connection errors
- ❌ Redis connection errors
- ⚠️ Increased restart count
- ⚠️ Memory/CPU spikes

---

## Post-Upgrade Tasks

### 1. Update Documentation
```bash
# Update Chart.yaml metadata (already done in Phase 1)
# Update any deployment docs with new version
```

### 2. Performance Baseline
```bash
# Capture new baseline metrics
kubectl top pods -n n8n > metrics-post-upgrade-$(date +%Y%m%d).txt

# Monitor for 24-48 hours
```

### 3. Security Verification
Verify CVE-2025-12735 is patched:
```bash
# Check n8n version
kubectl exec -n n8n deployment/n8n-main -- n8n --version

# Check for expr-eval version in logs/dependencies
kubectl exec -n n8n deployment/n8n-main -- npm list expr-eval
```

### 4. Communication
- ✅ Notify team of successful upgrade
- ✅ Update change log
- ✅ Document any issues encountered
- ✅ Update monitoring dashboards with new version

---

## Risk Mitigation

### Identified Risks

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Pod startup failure | High | Low | Rolling update allows auto-rollback |
| Database connection issues | High | Very Low | No DB schema changes in patch release |
| Redis queue disruption | Medium | Very Low | Workers reconnect automatically |
| HPA misconfiguration | Low | Very Low | HPA config unchanged |
| Image pull failure | Medium | Very Low | Use imagePullPolicy: IfNotPresent |
| Performance regression | Medium | Low | Monitor metrics, ready to rollback |

### Contingency Plans

1. **If main deployment fails**: Rollback immediately, investigate logs
2. **If webhook fails**: Workers continue processing, rollback webhook only
3. **If worker fails**: Main UI still accessible, rollback workers only
4. **If all fail**: Full rollback + restore from backup

---

## Success Criteria

✅ All deployments rolled out successfully
✅ All pods in Running state
✅ Version verified as 1.120.4
✅ Health checks passing
✅ UI accessible via HTTPS
✅ Webhooks responding
✅ Workers processing queue
✅ Database connectivity confirmed
✅ Redis connectivity confirmed
✅ HPA functioning correctly
✅ No error spikes in logs
✅ Test workflow executes successfully
✅ Metrics endpoint accessible

---

## Timeline

| Phase | Duration | Activities |
|-------|----------|------------|
| Preparation | 5 min | Backup, health check, chart update |
| Main Update | 5 min | Rolling update n8n-main |
| Webhook Update | 5 min | Rolling update n8n-webhook |
| Worker Update | 5 min | Rolling update n8n-worker |
| Validation | 10 min | Health checks, functional tests |
| Cleanup | 5 min | Remove old ReplicaSets |
| **Total** | **30-35 min** | **Full upgrade cycle** |

---

## Alternative Approach: Helm-Based Upgrade

If you want to manage with Helm going forward:

### Step 1: Install Helm Release (One-Time)
```bash
# Create Helm release from existing deployment
helm upgrade n8n ./n8n-helm-chart \
  --namespace n8n \
  --install \
  --create-namespace \
  --values ./n8n-helm-chart/values.yaml
```

### Step 2: Future Upgrades via Helm
```bash
# Update values.yaml with new version
# Then run:
helm upgrade n8n ./n8n-helm-chart \
  --namespace n8n \
  --values ./n8n-helm-chart/values.yaml \
  --wait \
  --timeout 10m

# Rollback via Helm if needed
helm rollback n8n -n n8n
```

**Recommendation**: Adopt Helm management for easier future upgrades.

---

## Notes & Considerations

### Image Tag Strategy
**Current**: `tag: latest` in values.yaml, but deployments use specific versions
**Recommended**: Use explicit version tags in values.yaml
**Reason**: Prevents unexpected updates, ensures version consistency

### Chart Version Management
**Current**: Chart version 1.0.0, appVersion 1.117.3 (outdated)
**Action**: Update both in Chart.yaml
**Future**: Bump chart version on config changes, appVersion on n8n upgrades

### Storage Persistence
**Current**: PVC only for n8n-main
**Consideration**: Webhook and worker are stateless (queue/DB backed)
**Action**: No storage changes needed

### Security Best Practices
1. Keep secrets in Kubernetes Secrets (already done ✓)
2. Use SSL for database connections (enabled ✓)
3. Regular backups before upgrades (in plan ✓)
4. Monitor CVE announcements (ongoing)

---

## References

- [n8n Release Notes](https://github.com/n8n-io/n8n/releases)
- [n8n Documentation](https://docs.n8n.io/release-notes/)
- [Update self-hosted n8n](https://docs.n8n.io/hosting/installation/updating/)
- [CVE-2025-12735 Details](https://github.com/n8n-io/n8n/releases/tag/n8n%401.120.2)

---

## Appendix A: Quick Command Reference

```bash
# Pre-upgrade
kubectl get all -n n8n
kubectl get deployments -n n8n -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.template.spec.containers[0].image}{"\n"}{end}'

# Upgrade
kubectl set image deployment/n8n-main n8n-main=n8nio/n8n:1.120.4 -n n8n
kubectl set image deployment/n8n-webhook n8n-webhook=n8nio/n8n:1.120.4 -n n8n
kubectl set image deployment/n8n-worker n8n-worker=n8nio/n8n:1.120.4 -n n8n

# Monitor
kubectl rollout status deployment/n8n-main -n n8n
kubectl get pods -n n8n -w

# Verify
kubectl exec -n n8n deployment/n8n-main -- n8n --version
curl https://auto.docaohieu.com/healthz

# Rollback
kubectl rollout undo deployment/n8n-main -n n8n
kubectl rollout undo deployment/n8n-webhook -n n8n
kubectl rollout undo deployment/n8n-worker -n n8n
```

---

## Appendix B: Troubleshooting Guide

### Issue: ImagePullBackOff
**Cause**: Image doesn't exist or network issue
**Solution**:
```bash
# Verify image exists
docker pull n8nio/n8n:1.120.4

# Check pod events
kubectl describe pod <pod-name> -n n8n
```

### Issue: CrashLoopBackOff
**Cause**: Application startup failure
**Solution**:
```bash
# Check logs
kubectl logs <pod-name> -n n8n --previous

# Check config
kubectl get configmap n8n-config -n n8n -o yaml
```

### Issue: Database Connection Errors
**Cause**: DB credentials or connectivity issue
**Solution**:
```bash
# Test DB connectivity
kubectl run -it --rm --image=postgres:15 psql-test -n database -- \
  psql -h postgres-ha.database.svc.cluster.local \
       -U n8n_postgres_user \
       -d n8n_postgres_db

# Verify secrets
kubectl get secret n8n-secrets -n n8n -o yaml
```

### Issue: Redis Connection Errors
**Cause**: Redis credentials or connectivity issue
**Solution**:
```bash
# Test Redis connectivity
kubectl run -it --rm --image=redis:7 redis-test -n database -- \
  redis-cli -h redis-ha-haproxy.database.svc.cluster.local -p 6379 -a <password> ping

# Verify queue status
kubectl exec -n n8n deployment/n8n-worker -- env | grep REDIS
```

---

**Plan Status**: Ready for Execution
**Approval Required**: Yes
**Next Step**: Review plan, approve, execute Phase 1
