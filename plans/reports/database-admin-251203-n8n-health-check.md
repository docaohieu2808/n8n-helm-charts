# n8n Kubernetes Environment Health Check Report
**Date:** 2025-12-03
**Current n8n Version:** 1.120.4
**Target:** Pre-upgrade health assessment

## Executive Summary

Overall cluster health is **OPERATIONAL** with minor connectivity issues identified. The environment is suitable for n8n upgrade with recommended pre-upgrade actions for Redis connection stability.

## Cluster Resources Status ✅

### Node Resources
- **Nodes:** 3 control-plane nodes (k8s-master-1, -2, -3)
- **Status:** All nodes healthy and ready
- **CPU Utilization:** 6-15% (well within safe limits)
- **Memory Utilization:** 21-40% (healthy)

### Resource Allocation
- **CPU Requests:** 38-78% across nodes (acceptable)
- **CPU Limits:** 85-254% (overcommitted but typical)
- **Memory Requests:** 16-46% (healthy)
- **Memory Limits:** 64-145% (acceptable with overcommit)

### Storage Status
- **Root Filesystem:** 63GB total, 31GB used (49% utilization)
- **PV Storage:** 10 PVCs active, total ~170GB provisioned
- **Storage Class:** NFS-client with expansion enabled

## Database Connectivity Status

### PostgreSQL HA Cluster ✅
- **Pods:** 3 PostgreSQL instances + 6 poolers (all Running)
- **Service:** `postgres-ha.database.svc.cluster.local:5432`
- **Connectivity:** ✅ Port accessible from n8n namespace
- **Leader:** postgres-ha-0 (stable leadership)
- **Replication:** HA cluster operational with poolers

### Redis HA Cluster ⚠️
- **Pods:** 3 Redis servers (9/9 containers) + 1 HAProxy (all Running)
- **Service:** `redis-ha-haproxy.database.svc.cluster.local:6379`
- **Connectivity:** ✅ Port accessible from n8n namespace
- **Issue:** Redis connection instability detected in n8n logs
- **Authentication:** Requires authentication (expected for secure setup)

## n8n Deployment Health Status

### Pod Status ✅
- **Total Pods:** 6 pods (2 main, 2 webhook, 2 workers)
- **Health:** All pods Running and Ready
- **Distribution:** Well distributed across all 3 nodes
- **Restarts:** Some restarts observed (7-15 per pod, ~3-5 days ago)

### Horizontal Pod Autoscalers ✅
- **n8n-webhook-hpa:** 1% CPU, 32% memory (well below 70%/80% thresholds)
- **n8n-worker-hpa:** 1% CPU, 30% memory (well below 70%/80% thresholds)
- **Current Replicas:** 2 each (within 2-10 range)

### Persistent Storage ✅
- **n8n-main-pvc:** 10Gi bound via NFS-client storage class
- **Status:** Healthy, bound to PVC-ff173d79-d377-4879-98b5-0a27fca2af40
- **Storage Backend:** NFS server at 213.35.108.172

## Backup Systems Status ❓

### Automated Backups
- **CronJobs:** No backup cronjobs found in cluster
- **Backup Jobs:** No recent backup jobs detected
- **Recommendation:** Implement automated backup strategy before upgrade

### Data Persistence
- **NFS Storage:** Configured with `archiveOnDelete=true`
- **Volume Expansion:** Enabled for storage scaling
- **Location:** External NFS server provides data persistence

## Critical Findings & Recommendations

### High Priority
1. **Redis Connection Stability**: Address intermittent Redis connection drops
   - Monitor Redis HAProxy health
   - Consider increasing Redis connection timeouts in n8n config
   - Review Redis server memory and connection limits

2. **Missing Backup Strategy**: Implement automated backup solution
   - Set up PostgreSQL database backups
   - Configure n8n data volume backups
   - Test restore procedures before upgrade

### Medium Priority
3. **Pod Restart Pattern**: Investigate historical restarts
   - Review resource limits and requests
   - Monitor memory usage patterns
   - Consider increasing memory requests if needed

### Low Priority
4. **Resource Overcommitment**: Monitor CPU limits overcommitment
   - Current 254% on k8s-master-3 requires monitoring
   - Ensure sufficient headroom during upgrade process

## Pre-Upgrade Action Items

### Immediate (Required)
- [ ] Implement automated backup strategy
- [ ] Address Redis connection stability issues
- [ ] Verify backup restore procedures

### Recommended
- [ ] Monitor resource utilization during upgrade window
- [ ] Prepare rollback plan with previous n8n version
- [ ] Schedule maintenance window with minimal workflow activity

### Post-Upgrade Verification
- [ ] Verify all n8n workflows execute correctly
- [ ] Confirm database connectivity and performance
- [ ] Validate webhook processing functionality
- [ ] Check worker queue processing

## Upgrade Readiness Assessment

**Status:** ✅ **READY FOR UPGRADE** (with pre-conditions)

The n8n Kubernetes environment demonstrates operational readiness for upgrade with the following conditions:
- Cluster resources are healthy with adequate capacity
- Database connectivity is functional (with minor Redis issues)
- All n8n components are running and distributed properly
- Storage systems are operational

**Proceed with upgrade after implementing backup strategy and addressing Redis connection stability.**

---
*Report generated using kubectl diagnostics and cluster health checks*
*Next health check recommended: Post-upgrade validation*