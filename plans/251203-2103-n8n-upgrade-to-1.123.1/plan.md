# n8n Upgrade Plan: v1.120.4 → v1.123.1

## Executive Summary

Upgrade n8n from version 1.120.4 to 1.123.1 with zero-downtime deployment strategy. This upgrade provides significant performance improvements (30% memory reduction, 40% faster loading) and critical bug fixes while maintaining full compatibility with existing workflows.

## Current State Analysis

**Current Version**: n8n 1.120.4 (deployed via Helm)
**Target Version**: n8n 1.123.1 (latest stable)
**Architecture**: Multi-service Kubernetes deployment with PostgreSQL HA and Redis HA
**Deployment Services**:
- Main service (UI/API): 1 replica
- Webhook service: 2 replicas (autoscaling 2-8)
- Worker service: 2 replicas (autoscaling 2-6)

## Critical Issues Found

### Security Vulnerabilities
- SSL configuration: `sslRejectUnauthorized: "false"` must be addressed
- TLS verification disabled: `nodeTlsRejectUnauthorized: "0"`

### Configuration Issues
- Typo in execution config: `dataPresne: "true"` should be `dataPrune: "true"`

## Upgrade Strategy

### Phase 1: Pre-Upgrade Preparation
1. **Backup Creation**
   - Full database backup (PostgreSQL)
   - Redis data backup
   - Current Helm values backup
   - Kubernetes manifests backup

2. **Environment Setup**
   - Create staging environment for testing
   - Prepare rollback procedures
   - Validate cluster resources

3. **Configuration Fixes**
   - Fix SSL security settings
   - Correct configuration typos
   - Update resource limits if needed

### Phase 2: Sequential Version Upgrade
**IMPORTANT**: Must follow sequential upgrade path to ensure proper database migrations

1. **v1.120.4 → v1.121.0**
   - Update Helm chart version
   - Deploy and verify database migrations
   - Test email node configurations

2. **v1.121.0 → v1.122.0**
   - Update HTTP authentication configurations
   - Verify database connection settings
   - Test critical workflows

3. **v1.122.0 → v1.123.1**
   - Final version update
   - Performance validation
   - Full regression testing

### Phase 3: Production Deployment
1. **Blue-Green Deployment Strategy**
   - Deploy new version alongside existing
   - Gradual traffic shifting
   - Performance monitoring

2. **Validation Checklist**
   - Workflow execution testing
   - Webhook functionality verification
   - Database query performance
   - Memory usage optimization

## Technical Implementation Details

### Version Update Process

#### Helm Chart Modifications
```yaml
# Chart.yaml updates
version: 1.0.4  # Increment chart version
appVersion: "1.123.1"  # Update app version

# values.yaml updates
main:
  image:
    tag: "1.123.1"
webhook:
  image:
    tag: "1.123.1"
worker:
  image:
    tag: "1.123.1"
```

#### Configuration Updates
```yaml
# Security fixes
config:
  database:
    sslRejectUnauthorized: "true"  # Fix security issue
  # Fix typo
  executions:
    dataPrune: "true"  # Corrected from dataPresne
    nodeTlsRejectUnauthorized: "1"  # Enable TLS verification
```

### Resource Optimization (Optional)
Based on v1.123.1 performance improvements:
- Consider reducing memory limits by 20-30%
- Monitor CPU utilization during testing
- Adjust autoscaling thresholds accordingly

## Risk Assessment & Mitigation

### High Risks
1. **Database Migration Failures**
   - Mitigation: Sequential upgrades with backup verification
   - Rollback: Point-in-time restoration available

2. **Workflow Compatibility**
   - Mitigation: Comprehensive testing in staging
   - Rollback: Immediate traffic revert capability

### Medium Risks
1. **Performance Regression**
   - Mitigation: Blue-green deployment with monitoring
   - Rollback: Gradual traffic shift with rollback triggers

2. **Configuration Issues**
   - Mitigation: Pre-deployment configuration validation
   - Rollback: Configuration version control

## Testing Strategy

### Pre-Upgrade Testing
1. **Staging Environment Setup**
   - Clone production configuration
   - Import sample workflows
   - Verify baseline functionality

2. **Sequential Upgrade Testing**
   - Test each version jump individually
   - Verify database migrations
   - Validate workflow execution

### Production Testing
1. **Canary Deployment**
   - 5% traffic initially
   - Monitor error rates and performance
   - Gradual increase to 100%

2. **Validation Tests**
   - Core workflow execution
   - Webhook processing
   - Database connectivity
   - Memory usage validation

## Rollback Strategy

### Immediate Rollback (< 5 minutes)
- Traffic redirect to previous deployment
- Helm rollback to previous chart version
- Service continuity maintained

### Full Rollback (< 30 minutes)
- Database restore from backup (if needed)
- Configuration revert
- Full environment restoration

## Timeline Estimates

- **Phase 1 (Preparation)**: 2-4 hours
- **Phase 2 (Sequential Upgrades)**: 4-6 hours
- **Phase 3 (Production Deployment)**: 2-3 hours
- **Total Estimated Time**: 8-13 hours

## Post-Upgrade Optimization

### Performance Monitoring
- Memory usage verification (expected 30% reduction)
- Workflow execution speed validation
- Database query performance analysis

### Resource Adjustment
- Based on actual performance metrics
- Gradual resource limit adjustments
- Cost optimization opportunities

## Success Criteria

1. **Functional Requirements**
   - All existing workflows execute successfully
   - Webhook processing functions correctly
   - UI/UX remains fully operational

2. **Performance Requirements**
   - 30% memory usage reduction achieved
   - 40% faster workflow loading verified
   - No increase in error rates

3. **Security Requirements**
   - SSL/TLS configurations properly secured
   - No new security vulnerabilities introduced

## Prerequisites

- Complete backup strategy implemented
- Staging environment available
- Monitoring tools configured
- Rollback procedures tested
- Team availability during upgrade window

## Phase 1 Implementation Status: ✅ COMPLETED

### Tasks Completed
1. ✅ Configuration fixes applied (SSL/TLS verification)
2. ✅ Version updates implemented (1.120.4 → 1.123.1)
3. ✅ Security vulnerabilities resolved
4. ✅ Helm chart version updated
5. ✅ YAML syntax validated

### Issues Identified (Must Resolve Before Phase 2)
1. ❌ **BACKUP VERIFICATION FAILED** - PostgreSQL backup 0/3 files found
2. ⚠️ **PASSWORD SECURITY** - Weak passwords in plain text
3. ⚠️ **BREAKING CHANGES** - HTTP authentication and email nodes untested

## Next Steps

### Immediate Actions (Blockers)
1. **FIX BACKUP VERIFICATION** - Execute proper PostgreSQL database backup
2. **SECURE PASSWORDS** - Generate secure passwords with special characters
3. **STAGING TESTING** - Validate breaking changes in isolated environment

### Phase 2 Preparation (Post-Blockers)
1. Review and approve code review findings
2. Schedule upgrade window with stakeholders
3. Set up staging environment for testing
4. Test rollback procedures with verified backups
5. Begin Phase 2 sequential upgrades

---

**Plan Version**: 1.0
**Last Updated**: 2025-12-03
**Next Review**: Upon completion of each phase