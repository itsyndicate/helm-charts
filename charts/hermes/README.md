# hermes

Hermes Agent (Nous Research) as a single stateful pod with a persistent HERMES_HOME

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: v0.23.1](https://img.shields.io/badge/AppVersion-v0.23.1-informational?style=flat-square)

## Why one pod

Hermes Agent keeps all its state (chats, memory, skills, config.yaml) in `HERMES_HOME`, in several SQLite databases. SQLite allows one writer, so the chart always runs exactly one pod with the `Recreate` strategy: the old pod stops before the new one starts, and the `ReadWriteOnce` volume is never mounted twice. That is also why there is no `replicaCount`, HPA or PodDisruptionBudget. A deploy or a node drain means a short downtime.

The PVC is kept on `helm uninstall` (`persistence.keepOnUninstall`), so the agent data is not lost by accident. Delete it by hand when it is really not needed.

## Image

`hermes.image.digest` takes precedence over `hermes.image.tag`, so a pipeline can deploy exactly the image it pushed:

```yaml
hermes:
  image:
    repository: 123456789012.dkr.ecr.eu-west-1.amazonaws.com/hermes-agent
    digest: sha256:0123...
```

The container must keep the image entrypoint: the official image starts s6-overlay, which runs the gateway and the dashboard and only works as PID 1. Do not override `hermes.command`.

## Secrets

`API_SERVER_KEY` (the bearer key of the API), the LLM provider keys and, with the dashboard, `HERMES_DASHBOARD_BASIC_AUTH_USERNAME` / `HERMES_DASHBOARD_BASIC_AUTH_PASSWORD` have to come from a secret, usually from AWS Secrets Manager through External Secrets:

```yaml
hermes:
  env:
    envFromSecretsManager:
      enabled: true
      secretPath: myapp/staging/hermes_env_vars
```

The chart sets `HERMES_HOME`, `API_SERVER_ENABLED`, `API_SERVER_HOST`, `API_SERVER_PORT` and the dashboard variables itself.

## Ingress

The API and the dashboard have separate ingresses, so they can get different hosts, load balancers or access rules. Anyone with `API_SERVER_KEY` can make the agent run shell commands, so put the API behind an access layer (for example Cloudflare Access with a service token) and keep the dashboard internal. Example for the AWS Load Balancer Controller:

```yaml
ingress:
  api:
    enabled: true
    className: alb
    annotations:
      alb.ingress.kubernetes.io/scheme: internet-facing
      alb.ingress.kubernetes.io/target-type: ip
      alb.ingress.kubernetes.io/healthcheck-path: /health
    hosts:
      - host: hermes-api.example.com
        paths:
          - path: /v1
            pathType: Prefix
          - path: /api/sessions
            pathType: Prefix
          - path: /health
            pathType: Exact
```

## First start

On a new volume the image creates `config.yaml` with its example values (model `anthropic/claude-opus-4.6`, provider `auto`, an OpenRouter `base_url`). The model and provider are read only from `config.yaml`, so set them once in the running pod, as the `hermes` user so the file keeps its owner, and restart the pod:

```bash
kubectl -n <namespace> exec deploy/<fullname> -- su hermes -s /bin/sh -c '
  export HERMES_HOME=/opt/data; H=/opt/hermes/bin/hermes
  $H config set model.provider anthropic
  $H config set model.default <model>
  $H config set model.base_url https://api.anthropic.com'
kubectl -n <namespace> rollout restart deploy/<fullname>
```

`config.yaml` stays on the volume, so later deploys keep these settings. On EBS (`ReadWriteOnce`) SQLite can stay in its default WAL mode. On NFS-based storage such as EFS also set `database.journal_mode delete` before the databases are created.

## Values

### Hermes Settings

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| hermes | object | A complex object. Please check values below | Hermes container settings |
| hermes.api | object | `{"port":8642}` | OpenAI-compatible API server. The container listens on 0.0.0.0 so the Service can reach it; requests still need the bearer key API_SERVER_KEY, which has to come from a secret (see `hermes.env`). |
| hermes.args | list | `["gateway","run"]` | Container args. Empty keeps the image CMD. |
| hermes.command | list | `[]` | Container command. Empty keeps the image entrypoint, which must stay PID 1 for s6-overlay. |
| hermes.dashboard | object | `{"enabled":false,"port":9119}` | Web dashboard. A non-loopback bind needs basic auth: set HERMES_DASHBOARD_BASIC_AUTH_USERNAME and HERMES_DASHBOARD_BASIC_AUTH_PASSWORD through `hermes.env`. |
| hermes.env.envFromSecretsManager | object | `{"enabled":false,"refreshInterval":"1m","secretPath":"","secretPaths":[],"secretStoreKind":"ClusterSecretStore","secretStoreName":"global-secret-store"}` | Use AWS secrets manager ref. Works with external-secrets operator. Each path renders its own ExternalSecret, mounted as env after `existingSecretName`. |
| hermes.env.envFromSecretsManager.enabled | bool | `false` | Render the ExternalSecrets and mount them as env |
| hermes.env.envFromSecretsManager.refreshInterval | string | `"1m"` | How often External Secrets Operator refreshes the secrets |
| hermes.env.envFromSecretsManager.secretPath | string | `""` | Single secret path, e.g. `myapp/staging/hermes_env_vars`. Set either this or `secretPaths`; setting both fails the render, and so does setting neither while `enabled` is true. |
| hermes.env.envFromSecretsManager.secretPaths | list | `[]` | Secret paths mounted in list order. On key collisions a later path wins over an earlier one. Set either this or `secretPath`. |
| hermes.env.envFromSecretsManager.secretStoreKind | string | `"ClusterSecretStore"` | Kind of the secret store: ClusterSecretStore or SecretStore |
| hermes.env.envFromSecretsManager.secretStoreName | string | `"global-secret-store"` | Name of the secret store the ExternalSecrets reference |
| hermes.env.existingSecretName | string | `""` | Name of an existing Secret to mount as env (e.g. one managed by External Secrets Operator). Mounted additively alongside `variables` and `envFromSecretsManager`. On key collisions the existing Secret wins over `variables`, and `envFromSecretsManager` wins over both. |
| hermes.env.variables | object | `{}` | Extra plain (non-secret) env variables. Always injected, even when existingSecretName is set. |
| hermes.home | string | `"/opt/data"` | HERMES_HOME inside the container. The persistent volume is mounted here. |
| hermes.image | object | `{"digest":"","pullPolicy":"IfNotPresent","repository":"nousresearch/hermes-agent","tag":""}` | Hermes image settings. When `digest` is set it is used instead of `tag`, e.g. the digest a pipeline pushed. |
| hermes.image.digest | string | `""` | Image digest (sha256:...). Takes precedence over `tag`. |
| hermes.image.tag | string | `""` | Overrides the image tag whose default is the chart appVersion |
| hermes.livenessProbe | object | `{"failureThreshold":3,"httpGet":{"path":"/health","port":"api"},"periodSeconds":30,"timeoutSeconds":5}` | Hermes container liveness probe. Not rendered unless set. |
| hermes.readinessProbe | object | `{"httpGet":{"path":"/health","port":"api"},"periodSeconds":10}` | Hermes container readiness probe. Not rendered unless set. |
| hermes.resources | object | `{}` | Hermes container resources |
| hermes.securityContext | object | `{}` | Hermes container security context |
| hermes.startupProbe | object | `{"failureThreshold":30,"httpGet":{"path":"/health","port":"api"},"periodSeconds":10}` | Hermes container startup probe. Not rendered unless set. |
| hermes.volumeMounts | list | `[]` | Hermes container additional volume mounts |
| hermes.volumes | list | `[]` | Hermes container additional volumes |

### Networking Settings

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| ingress | object | `{"api":{"annotations":{},"className":"","enabled":false,"hosts":[{"host":"hermes-api.example.com","paths":[{"path":"/","pathType":"Prefix"}]}],"tls":[]},"dashboard":{"annotations":{},"className":"","enabled":false,"hosts":[{"host":"hermes.example.com","paths":[{"path":"/","pathType":"Prefix"}]}],"tls":[]}}` | Ingress for the API (port 8642) |
| ingress.api.enabled | bool | `false` | Enables the API ingress when true |
| ingress.dashboard | object | `{"annotations":{},"className":"","enabled":false,"hosts":[{"host":"hermes.example.com","paths":[{"path":"/","pathType":"Prefix"}]}],"tls":[]}` | Ingress for the dashboard (port 9119). Rendered only when `hermes.dashboard.enabled` is also true. |
| service | object | `{"annotations":{},"type":"ClusterIP"}` | Service settings. Exposes the API port, and the dashboard port when the dashboard is enabled. |

### Persistence Settings

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| persistence | object | `{"accessMode":"ReadWriteOnce","annotations":{},"enabled":true,"existingClaim":"","keepOnUninstall":true,"size":"10Gi","storageClass":""}` | Persistent volume for HERMES_HOME: config.yaml, memory, skills and the SQLite databases |
| persistence.accessMode | string | `"ReadWriteOnce"` | Access mode. ReadWriteOnce (EBS) is the safe choice for SQLite: only one pod can mount it. |
| persistence.annotations | object | `{}` | Annotations to add to the PVC |
| persistence.enabled | bool | `true` | Create a PersistentVolumeClaim (or use `existingClaim`). Without it the agent loses all state on restart. |
| persistence.existingClaim | string | `""` | Use an existing PVC instead of creating one |
| persistence.keepOnUninstall | bool | `true` | Keep the PVC when the release is uninstalled, so the agent data is not lost by accident |
| persistence.size | string | `"10Gi"` | Size of the PVC |
| persistence.storageClass | string | `""` | StorageClass of the PVC. Empty uses the cluster default. |

### Other Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| affinity | object | `{}` | Affinity settings |
| fullnameOverride | string | `""` | Overrides full release name |
| imagePullSecrets | list | `[]` | Secret that used to store docker registry credentials |
| nameOverride | string | `""` | Overrides release name |
| nodeSelector | object | `{}` | Node selector settings |
| podAnnotations | object | `{}` | Annotations to add to the pod |
| podLabels | object | `{}` | Labels to add to the pod |
| podSecurityContext | object | `{"fsGroup":10000,"fsGroupChangePolicy":"OnRootMismatch"}` | Security context of the pod. fsGroup 10000 is the hermes user of the official image, so the volume is writable by it. The container itself starts as root: the image's s6-overlay init needs PID 1 as root and drops to the hermes user for the agent. |
| revisionHistoryLimit | int | `3` | Old ReplicaSets retained for rollback (set null to fall back to the Kubernetes default of 10) |
| serviceAccount | object | `{"annotations":{},"automount":false,"create":true,"name":""}` | Service Account |
| serviceAccount.annotations | object | `{}` | Annotations to add to the service account (e.g. an IRSA role ARN) |
| serviceAccount.automount | bool | `false` | Automatically mount a ServiceAccount's API credentials? Off by default: the agent runs shell commands and does not need the Kubernetes API. |
| serviceAccount.create | bool | `true` | Specifies whether a service account should be created |
| serviceAccount.name | string | `""` | The name of the service account to use. |
| terminationGracePeriodSeconds | int | `60` | Seconds Kubernetes waits after SIGTERM before killing the pod, so Hermes can finish writes to SQLite |
| tolerations | list | `[]` | Tolerations settings |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
