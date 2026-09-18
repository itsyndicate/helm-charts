# fastapi

![Version: 0.5.0](https://img.shields.io/badge/Version-0.5.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 1.16.0](https://img.shields.io/badge/AppVersion-1.16.0-informational?style=flat-square)

A Helm chart for Kubernetes

## Values

### FastAPI Settings

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| fastapi | object | A complex object. Please check values below | FastAPI-specific configurations |
| fastapi.args | list | `[]` | Override the default container arguments |
| fastapi.command | list | `[]` | Override the default container command |
| fastapi.env.envFromSecretsManager | object | `{"enabled":false,"refreshInterval":"1m","secretPath":"","secretPaths":[],"secretStoreKind":"ClusterSecretStore","secretStoreName":"global-secret-store"}` | Use AWS secrets manager ref. Works with external-secrets operator. Each path renders its own ExternalSecret, mounted as env after `existingSecretName`. |
| fastapi.env.envFromSecretsManager.enabled | bool | `false` | Render the ExternalSecrets and mount them as env |
| fastapi.env.envFromSecretsManager.refreshInterval | string | `"1m"` | How often External Secrets Operator refreshes the secrets |
| fastapi.env.envFromSecretsManager.secretPath | string | `""` | Single secret path, e.g. `dev/example-com/env-secrets`. Set either this or `secretPaths`; setting both fails the render, and so does setting neither while `enabled` is true. |
| fastapi.env.envFromSecretsManager.secretPaths | list | `[]` | Secret paths mounted in list order. On key collisions a later path wins over an earlier one. Set either this or `secretPath`. |
| fastapi.env.envFromSecretsManager.secretStoreKind | string | `"ClusterSecretStore"` | Kind of the secret store: ClusterSecretStore or SecretStore |
| fastapi.env.envFromSecretsManager.secretStoreName | string | `"global-secret-store"` | Name of the secret store the ExternalSecrets reference |
| fastapi.env.existingSecretName | string | `""` | Name of an existing Secret to mount as env (e.g. one managed by External Secrets Operator). Mounted additively alongside `variables` and `envFromSecretsManager` on the deployment and workers — it does NOT disable `variables`. On key collisions the existing Secret wins over `variables`, and `envFromSecretsManager` wins over both. |
| fastapi.env.variables | object | `{}` | Extra plain (non-secret) env variables. Always injected, even when existingSecretName is set. |
| fastapi.image | object | `{"pullPolicy":"IfNotPresent","repository":"my-fastapi-image","tag":"latest"}` | FastAPI image settings |
| fastapi.image.tag | string | `"latest"` | Tag of the FastAPI image |
| fastapi.livenessProbe | object | `{}` | Liveness probe for FastAPI. Leave empty to use the chart's mode-aware default: no liveness probe when the NginX sidecar is enabled (app on a UNIX socket), or an HTTP check on /health at the app port when it is disabled. Set a value here to override. |
| fastapi.port | int | `8000` | Port the app binds to (and the container/probe port) when the NginX sidecar is disabled (nginx.enabled=false). Keep it above 1024 so the container can bind without root / NET_BIND_SERVICE. When the NginX sidecar is enabled the app listens on a UNIX socket and this value is unused. |
| fastapi.readinessProbe | object | `{}` | Readiness probe for FastAPI. Leave empty to use the chart's mode-aware default: a UNIX socket check (ls /tmp/uvicorn.sock) when the NginX sidecar is enabled, or an HTTP check on /health at the app port when it is disabled. Set a value here to override. |
| fastapi.resources | object | `{}` | Resource limits and requests for the FastAPI container |
| fastapi.securityContext | object | `{}` | Security context for the FastAPI container |
| fastapi.startupProbe | object | `{}` | Startup probe for FastAPI. Not rendered unless set. |
| fastapi.volumeMounts | list | `[]` | Additional volume mounts for FastAPI container |
| fastapi.volumes | list | `[]` | Additional volumes for FastAPI pods |
| fastapi.workers | list | `[]` | Configuration for FastAPI workers |

### Networking Settings

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| ingress | object | `{"annotations":{},"className":"","enabled":false,"hosts":[{"host":"chart-example.local","paths":[{"path":"/","pathType":"ImplementationSpecific"}]}],"tls":[]}` | Ingress settings |
| service | object | `{"port":80,"type":"ClusterIP"}` | Service configuration |

### NginX Settings

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| nginx | object | A complex object. Please check values below | NginX Specific Configurations |
| nginx.enabled | bool | `true` | Enable NginX sidecar |
| nginx.keepalive_timeout | int | `65` | Timeout during which a keep-alive client connection will stay open on the server side |
| nginx.proxy_read_timeout | string | `"60s"` | Timeout for reading a response from the proxied server |
| nginx.proxy_send_timeout | string | `"60s"` | Timeout for transmitting a request to the proxied server |
| nginx.resources | object | `{}` | Resource limits and requests for NginX container |
| nginx.securityContext | object | `{}` | Security context for the NginX container |
| nginx.send_timeout | string | `"60s"` | Timeout for transmitting a response to the client |
| nginx.volumeMounts | list | `[]` | Additional volume mounts for the NginX container |
| nginx.volumes | list | `[]` | Additional volumes for the NginX pods |

### PDB Settings

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| pdb | object | `{"create":false,"minAvailable":1}` | Pod Disruption Budget settings |

### Other Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| affinity | object | `{}` | Affinity rules for pod placement |
| autoscaling | object | `{"enabled":false,"maxReplicas":100,"minReplicas":1,"targetCPUUtilizationPercentage":80}` | Autoscaling configuration |
| fastapi.image.pullPolicy | string | `"IfNotPresent"` | Image pull policy (Always, IfNotPresent, Never) |
| fastapi.image.repository | string | `"my-fastapi-image"` | FastAPI Docker image repository |
| fullnameOverride | string | `""` | Overrides full release name |
| imagePullSecrets | list | `[]` | Secret used to store Docker registry credentials |
| ingress.enabled | bool | `false` | Enables ingress when true |
| nameOverride | string | `""` | Overrides release name |
| nginx.image.pullPolicy | string | `"IfNotPresent"` | Image pull policy (Always, IfNotPresent, Never) |
| nginx.image.repository | string | `"nginx"` | NginX Docker image repository |
| nginx.image.tag | string | `"alpine"` | Tag of the NginX image |
| nodeSelector | object | `{}` | Node selector for pod placement |
| podAnnotations | object | `{}` | Annotations to add to the pods |
| podLabels | object | `{}` | Labels to add to the pods |
| podSecurityContext | object | `{}` | Security context for the pod |
| replicaCount | int | `1` | Number of replicas to spin up |
| revisionHistoryLimit | int | `3` | Old ReplicaSets retained for rollback (set null to fall back to the Kubernetes default of 10) |
| service.port | int | `80` | Port exposed by the service |
| service.type | string | `"ClusterIP"` | Type of Kubernetes service (ClusterIP, NodePort, LoadBalancer) |
| serviceAccount | object | `{"annotations":{},"automount":true,"create":true,"name":""}` | Service Account configuration |
| serviceAccount.annotations | object | `{}` | Annotations to add to the service account |
| serviceAccount.automount | bool | `true` | Automatically mount a ServiceAccount's API credentials? |
| serviceAccount.create | bool | `true` | Specifies whether a service account should be created |
| serviceAccount.name | string | `""` | The name of the service account to use |
| tolerations | list | `[]` | Tolerations for pod placement |

## Per-path custom backend

By default every path in `ingress.hosts[].paths[]` routes to the chart's own service. You can override the backend per path by adding a `backend` field. This is useful for ALB fixed-response actions (e.g. returning 403 for a path on a public ALB while exposing it on an internal ALB).

```yaml
ingress:
  enabled: true
  annotations:
    alb.ingress.kubernetes.io/actions.response-403: '{"type":"fixed-response","fixedResponseConfig":{"contentType":"text/plain","statusCode":"403","messageBody":"Forbidden"}}'
  hosts:
    - host: example.com
      paths:
        - path: /private
          pathType: Prefix
          backend:
            service:
              name: response-403
              port:
                name: use-annotation   # triggers the ALB fixed-response action above
        - path: /
          pathType: Prefix             # falls back to the chart's own service
```

If `backend` is omitted on a path, the chart's own service name and port are used — identical behaviour to previous versions.

## Several Secrets Manager paths

`fastapi.env.envFromSecretsManager.secretPaths` renders one ExternalSecret per path, named `<fullname>-env-ext-secrets-<index>`, and mounts them with `envFrom` in list order after `existingSecretName`. Kubernetes gives the last `envFrom` source precedence for a duplicate key, so a later path overrides an earlier one. This lets a release take shared defaults from one secret and override some of them from another.

```yaml
fastapi:
  env:
    envFromSecretsManager:
      enabled: true
      secretStoreName: global-secret-store
      refreshInterval: 5m
      secretPaths:
        - dev/example-com/shared-env
        - dev/example-com/env-secrets
```

`secretPath` renders a single ExternalSecret named `<fullname>-env-ext-secrets`, as in previous versions. Set either `secretPath` or `secretPaths`: setting both fails the render, and so does setting neither while `enabled` is true. `secretPath` defaults to empty, so a release that enables Secrets Manager must set one of them.

## Probes

`fastapi.startupProbe` is rendered only when set. The mode-aware liveness and readiness defaults are unchanged: with the NginX sidecar enabled the app container gets no liveness probe and a UNIX socket readiness check, and with it disabled both are HTTP checks on `/health` at the app port.

```yaml
fastapi:
  startupProbe:
    httpGet:
      path: /health
      port: http
    periodSeconds: 5
    failureThreshold: 30
```

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
