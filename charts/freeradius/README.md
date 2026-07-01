# freeradius

![Version: 0.7.0](https://img.shields.io/badge/Version-0.7.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 3.2.8](https://img.shields.io/badge/AppVersion-3.2.8-informational?style=flat-square)

FreeRADIUS Helm chart with HA, topology spread, and zero-downtime NLB draining support.

Designed for AWS EKS with an NLB (Network Load Balancer) in IP target mode. Ships with:

- **PodDisruptionBudget** — prevents voluntary evictions from taking the last pod
- **Topology spread constraints** — keeps replicas on separate physical nodes
- **Lifecycle `preStop` hook** — delays SIGTERM so the NLB can finish deregistering the pod before traffic stops
- **ExternalSecret integration** — pulls all runtime credentials from AWS Secrets Manager via ESO
- **ConfigMap-based config injection** — base and env-specific FreeRADIUS config files injected by an initContainer

## Values

### Core

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| replicaCount | int | `2` | Number of FreeRADIUS pod replicas |
| nameOverride | string | `""` | Override chart name |
| fullnameOverride | string | `""` | Override fully qualified app name |
| imagePullSecrets | list | `[]` | Image pull secrets for private registries |

### Image

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| image.repository | string | `"freeradius/freeradius-server"` | Container image repository |
| image.pullPolicy | string | `"IfNotPresent"` | Image pull policy |
| image.tag | string | `""` | Image tag (defaults to `.Chart.AppVersion`) |

### Service Account

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| serviceAccount.create | bool | `true` | Create a dedicated ServiceAccount |
| serviceAccount.annotations | object | `{}` | Annotations for the ServiceAccount (e.g. IRSA role ARN) |
| serviceAccount.name | string | `""` | ServiceAccount name override (generated from fullname if empty) |

### Pod

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| podAnnotations | object | `{"reloader.stakater.com/auto": "true"}` | Pod annotations |
| podLabels | object | `{}` | Additional pod labels |
| podSecurityContext | object | `{"fsGroup": 101}` | Pod-level security context. FreeRADIUS starts as root then drops to freerad (UID 101) |
| securityContext | object | see values.yaml | Container-level security context |

### Service

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| service.type | string | `"LoadBalancer"` | Service type. `LoadBalancer` with AWS NLB is required for UDP traffic |
| service.externalTrafficPolicy | string | `"Local"` | Preserve client source IP through NLB; required for per-AP RADIUS client matching |
| service.annotations | object | see values.yaml | Service annotations. Defaults configure an internet-facing AWS NLB with IP target mode |
| service.authPort | int | `1812` | RADIUS authentication port (UDP) |
| service.acctPort | int | `1813` | RADIUS accounting port (UDP) |

### Resources

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| resources.requests.cpu | string | `"100m"` | CPU request |
| resources.requests.memory | string | `"128Mi"` | Memory request |
| resources.limits.cpu | string | `"500m"` | CPU limit |
| resources.limits.memory | string | `"256Mi"` | Memory limit |

### Health Probes

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| livenessProbe | object | `exec: pgrep -x freeradius` | Liveness probe. Uses process check because FreeRADIUS exposes no HTTP endpoint |
| readinessProbe | object | `exec: pgrep -x freeradius` | Readiness probe |

### High Availability

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| pdb.create | bool | `true` | Enable PodDisruptionBudget. Meaningful only with `replicaCount > 1` |
| pdb.minAvailable | int | `1` | Minimum available pods during voluntary disruptions |
| pdb.maxUnavailable | string | `""` | Maximum unavailable pods during voluntary disruptions. Mutually exclusive with `minAvailable` |
| terminationGracePeriodSeconds | int | `null` | Seconds the kubelet waits after SIGTERM before sending SIGKILL. Unset by default (Kubernetes default of 30 s applies). Pair with `lifecycle.preStop` for zero-downtime NLB draining |
| lifecycle | object | `{}` | Lifecycle hooks for the freeradius container. Use `preStop` to delay SIGTERM and allow NLB target deregistration to complete. See [Zero-Downtime NLB Draining](#zero-downtime-nlb-draining) |
| topologySpreadConstraints | list | `[]` | Topology spread constraints for scheduling pods across nodes or zones. See [example below](#topology-spread) |

### Scheduling

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| nodeSelector | object | `{"kubernetes.io/arch": "amd64"}` | Node selector constraints |
| tolerations | list | `[]` | Tolerations for pod scheduling |
| affinity | object | `{}` | Affinity rules for pod scheduling |

### Network Policy

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| networkPolicy.enabled | bool | `false` | Enable NetworkPolicy restricting ingress to RADIUS ports only |
| networkPolicy.additionalIngress | list | `[]` | Extra ingress rules appended to the generated policy |

### External Secrets

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| externalSecret.enabled | bool | `true` | Create an ExternalSecret resource. Disable only if managing the credentials Secret manually |
| externalSecret.secretStoreName | string | `"global-secret-store"` | ClusterSecretStore name that already exists in the cluster |
| externalSecret.refreshInterval | string | `"1h"` | How often ESO syncs the secret from Secrets Manager |
| externalSecret.secretName | string | `""` | Name of the resulting Kubernetes Secret (defaults to `<fullname>-credentials`) |
| externalSecret.dataFrom.enabled | bool | `false` | Pull all fields from a single JSON secret automatically. When `true`, every field in the remote secret is injected into the pod via `envFrom` |
| externalSecret.dataFrom.key | string | `""` | AWS Secrets Manager secret path (e.g. `project/env/freeradius`) |
| externalSecret.remoteRefs | object | see values.yaml | Per-key remote references. Used only when `dataFrom.enabled` is `false` |

### MariaDB

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| mariadb.enabled | bool | `false` | Deploy MariaDB inside the cluster. Set `false` when pointing to an external database (AWS RDS) |
| mariadb.auth.database | string | `"radius"` | Database name |
| mariadb.auth.username | string | `"radius"` | Application username |
| mariadb.auth.password | string | `""` | Application user password. Use `externalSecret` in production |
| mariadb.auth.rootPassword | string | `""` | MariaDB root password |
| mariadb.primary.resources | object | see values.yaml | MariaDB primary resource requests and limits |

### Extra Config

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| extraBaseConfigsConfigMapName | string | `""` | Name of an existing ConfigMap with universal (base) FreeRADIUS configs. Applied by the initContainer before `extraConfigsConfigMapName`, so env configs take precedence |
| extraConfigsConfigMapName | string | `""` | Name of an existing ConfigMap whose keys (using `--` as path separator) are copied into `/etc/freeradius` by the initContainer |
| extraVolumes | list | `[]` | Additional volumes to mount into the pod |
| extraVolumeMounts | list | `[]` | Additional volume mounts for the freeradius container |
| extraContainers | list | `[]` | Additional sidecar containers |
| args | list | `["freeradius", "-f", "-l", "stdout"]` | Container args. Defaults to foreground mode with stdout logging |

### Migration Job

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| migrationJob.enabled | bool | `false` | Run a pre-upgrade Helm hook job before new pods roll out |
| migrationJob.image | string | `""` | Image for the migration job (defaults to the freeradius image; use `mysql:8.0` for SQL migrations) |
| migrationJob.imagePullPolicy | string | `""` | Image pull policy for the migration job |
| migrationJob.command | list | `[]` | Command to run in the migration job |
| migrationJob.backoffLimit | int | `3` | Number of retries before the job is considered failed |
| migrationJob.resources | object | `{}` | Resource requests and limits for the migration job |

---

## Zero-Downtime NLB Draining

When running behind an AWS NLB, a pod replacement without care causes a brief outage: the NLB
continues routing new UDP connections to a pod that has already received SIGTERM. The solution
requires coordinating four settings:

```yaml
# 1. Delay SIGTERM by 15 s — gives the NLB time to deregister the pod IP
lifecycle:
  preStop:
    exec:
      command: [/bin/sh, -c, sleep 15]

# 2. Total grace period = preStop duration + time for FreeRADIUS to shut down cleanly
terminationGracePeriodSeconds: 30

# 3. Tell the NLB target group to match the same drain window
service:
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-target-group-attributes: "deregistration_delay.timeout_seconds=30"

# 4. Block voluntary evictions until a replacement pod is Running
pdb:
  create: true
  minAvailable: 1
```

**Sequence of events during a pod eviction:**

1. Pod enters `Terminating` — Kubernetes removes the pod IP from the EndpointSlice.
2. AWS Load Balancer Controller calls the ELB API to begin NLB deregistration.
3. `preStop` hook fires **before** SIGTERM — `sleep 15` keeps the process alive while the NLB drains existing connections and stops routing new ones.
4. After 15 s, SIGTERM is delivered to FreeRADIUS, which begins graceful shutdown.
5. FreeRADIUS has the remaining ~15 s (30 s grace − 15 s preStop) to flush accounting records and exit.
6. If it has not exited by `terminationGracePeriodSeconds`, Kubernetes sends SIGKILL.

---

## Topology Spread

Keep replicas on separate physical nodes so a single spot-instance reclamation cannot take out all pods:

```yaml
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: kubernetes.io/hostname
    whenUnsatisfiable: DoNotSchedule
    labelSelector:
      matchLabels:
        app.kubernetes.io/name: freeradius
        app.kubernetes.io/instance: <release-name>
```

`whenUnsatisfiable: DoNotSchedule` keeps a pod `Pending` rather than co-locating — Karpenter
sees the pending pod and provisions a new node to satisfy the constraint.

---

## Config Injection

FreeRADIUS configuration is injected at startup by an initContainer that copies files from two optional ConfigMaps into `/etc/freeradius`:

1. **`extraBaseConfigsConfigMapName`** — base config (common across environments). Copied first.
2. **`extraConfigsConfigMapName`** — environment-specific overrides. Copied second, so they win.

ConfigMap keys use `--` as a path separator to encode subdirectory structure:

```
clients-env.conf            → /etc/freeradius/clients-env.conf
mods-enabled--sql           → /etc/freeradius/mods-enabled/sql
sites-enabled--default      → /etc/freeradius/sites-enabled/default
mods-config--files--authorize → /etc/freeradius/mods-config/files/authorize
```

Create the ConfigMap via Kustomize `configMapGenerator` with `disableNameSuffixHash: true`.

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
