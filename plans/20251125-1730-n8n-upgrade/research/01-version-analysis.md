# n8n Version Analysis: 1.119.0 → 1.120.4

## Current State
- **Current Version**: 1.119.0
- **Target Version**: 1.120.4
- **Deployment**: Kubernetes (custom Helm chart)
- **Namespace**: n8n
- **Components**:
  - n8n-main (2 replicas) - UI/API
  - n8n-webhook (2 replicas, HPA enabled) - Webhook handler
  - n8n-worker (2 replicas, HPA enabled) - Queue worker

## Version Gap Analysis

### 1.120.0
- No critical breaking changes documented
- General improvements and bug fixes

### 1.120.1
- CI fixes only
- No user-facing changes

### 1.120.2 (November 14, 2025)
- **Security Fix**: Patched expr-eval dependency for CVE-2025-12735
- Fixed MCP Client Tool Node DCR functionality
- No breaking changes

### 1.120.3 (November 14, 2025)
- Community node installation validates package versions
- Git Node disables hooks by default
- No breaking changes

### 1.120.4 (November 19, 2025)
- Version bumps and changelog updates
- No breaking changes

## Breaking Changes Assessment
**Result**: No breaking changes between 1.119.0 and 1.120.4

## Security Considerations
- CVE-2025-12735 patched in 1.120.2
- Upgrade recommended for security compliance

## Compatibility Check
- PostgreSQL HA: Compatible ✓
- Redis HA: Compatible ✓
- Queue mode: Compatible ✓
- Webhook service: Compatible ✓
- Metrics: Compatible ✓

## Risk Level: LOW
- Patch release series
- No breaking changes
- No migration required
- Rolling update safe
