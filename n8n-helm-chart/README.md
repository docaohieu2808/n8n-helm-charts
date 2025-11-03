# n8n Helm Chart

A Helm chart for deploying n8n workflow automation platform with separate webhook service for optimal scalability.

## Features

- ✅ Separate webhook service for high-performance webhook handling
- ✅ Auto-scaling for webhook and worker pods
- ✅ PostgreSQL HA support
- ✅ Redis HA support for queue and cache
- ✅ Persistent storage for main instance
- ✅ Pod anti-affinity for high availability
- ✅ Health checks (startup, liveness, readiness probes)
- ✅ Metrics support

## Architecture

```
┌─────────────────────────────────────┐
│         Ingress (Traefik)           │
└──────────┬──────────────────────────┘
           │
           ├──► /webhook* ──────► n8n-webhook-service (2-8 pods)
           │                      ↓
           │                  Queue (Redis)
           │
           └──► /* ────────────► n8n-main-service (1 pod - UI)
                                 ↓
                            Queue (Redis)
                                 ↓
                        n8n-worker-service (2-6 pods)
```

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- PostgreSQL database (external or in-cluster)
- Redis (external or in-cluster)
- Storage class for persistent volumes (optional)

## Installation

### Quick Start

```bash
# Add repository (if using helm repo)
helm repo add n8n https://your-repo-url
helm repo update

# Install with default values
helm install n8n n8n/n8n -n n8n --create-namespace

# Install with custom values
helm install n8n n8n/n8n -n n8n --create-namespace -f custom-values.yaml
```

### Install from local chart

```bash
# Install from local directory
helm install n8n ./n8n-helm-chart -n n8n --create-namespace

# Upgrade existing installation
helm upgrade n8n ./n8n-helm-chart -n n8n
```

## Configuration

### Key Configuration Values

| Parameter | Description | Default |
|-----------|-------------|---------|
| `global.namespace` | Kubernetes namespace | `n8n` |
| `main.replicaCount` | Number of main pods | `1` |
| `webhook.enabled` | Enable separate webhook service | `true` |
| `webhook.replicaCount` | Initial webhook pods | `2` |
| `webhook.autoscaling.maxReplicas` | Max webhook pods | `8` |
| `worker.replicaCount` | Initial worker pods | `2` |
| `worker.autoscaling.maxReplicas` | Max worker pods | `6` |
| `config.host` | n8n hostname | `auto.docaohieu.com` |
| `config.database.host` | PostgreSQL host | `postgres-ha.database.svc.cluster.local` |
| `config.redis.host` | Redis host | `redis-ha-haproxy.database.svc.cluster.local` |
| `ingress.enabled` | Enable ingress | `true` |
| `persistence.enabled` | Enable persistent storage | `true` |
| `persistence.size` | Storage size | `10Gi` |

### Example: Custom Values

Create a `custom-values.yaml` file:

```yaml
# Use your own domain
config:
  host: "n8n.example.com"
  webhookUrl: "https://n8n.example.com"

# Use your own database
config:
  database:
    host: "my-postgres.example.com"
    name: "n8n_db"
    user: "n8n_user"

# Custom secrets
secrets:
  postgresPassword: "your-secure-password"
  encryptionKey: "your-encryption-key"
  redisPassword: "your-redis-password"

# Scale webhook for high traffic
webhook:
  autoscaling:
    minReplicas: 4
    maxReplicas: 20
```

Then install:
```bash
helm install n8n ./n8n-helm-chart -n n8n -f custom-values.yaml
```

## Upgrading

```bash
# Upgrade to new version
helm upgrade n8n ./n8n-helm-chart -n n8n

# Upgrade with new values
helm upgrade n8n ./n8n-helm-chart -n n8n -f custom-values.yaml
```

## Uninstalling

```bash
# Uninstall release
helm uninstall n8n -n n8n

# Delete namespace (if needed)
kubectl delete namespace n8n
```

## Monitoring

### Check Status

```bash
# Get all resources
kubectl get all -n n8n

# Check HPA status
kubectl get hpa -n n8n

# View pod logs
kubectl logs -n n8n -l app=n8n-main -f
kubectl logs -n n8n -l app=n8n-webhook -f
kubectl logs -n n8n -l app=n8n-worker -f
```

### Metrics

Metrics are exposed on port 9090 of the main service if `N8N_METRICS=true`:

```bash
# Port-forward to access metrics
kubectl port-forward -n n8n svc/n8n-main-service 9090:9090

# View metrics
curl http://localhost:9090/metrics
```

## Troubleshooting

### Pods not starting

Check pod logs:
```bash
kubectl logs -n n8n <pod-name>
```

Check events:
```bash
kubectl get events -n n8n --sort-by='.lastTimestamp'
```

### Database connection issues

Verify database credentials and connectivity:
```bash
kubectl exec -it -n n8n <pod-name> -- sh
# Inside pod:
nc -zv postgres-host 5432
```

### Webhook not working

Verify ingress configuration:
```bash
kubectl describe ingress -n n8n n8n-ingress
```

Check webhook pod logs:
```bash
kubectl logs -n n8n -l app=n8n-webhook --tail=50
```

## Security Notes

⚠️ **IMPORTANT**: The default values include sample secrets. You **MUST** change these in production:

- `secrets.postgresPassword`
- `secrets.encryptionKey`
- `secrets.redisPassword`

Generate secure random keys:
```bash
# Generate encryption key
openssl rand -hex 32

# Generate strong password
openssl rand -base64 32
```

## License

This Helm chart is provided as-is. n8n itself is licensed under the [Sustainable Use License](https://github.com/n8n-io/n8n/blob/master/LICENSE.md).

## Support

- n8n Documentation: https://docs.n8n.io/
- n8n Community: https://community.n8n.io/
