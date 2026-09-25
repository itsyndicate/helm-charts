# fastapi

![Version: 0.7.0](https://img.shields.io/badge/Version-0.7.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 1.16.0](https://img.shields.io/badge/AppVersion-1.16.0-informational?style=flat-square)

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
| fastapi.preDeployJob | object | `{"args":[],"backoffLimit":6,"command":[],"enabled":false}` | Enables pre-deploy job with Helm hook before rolling the update |
| fastapi.preDeployJob.args | list | `[]` | Arguments to pass to the command |
| fastapi.preDeployJob.backoffLimit | int | `6` | Number of retries before marking the job as failed |
| fastapi.preDeployJob.command | list | `[]` | Command to run in the job container |
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
| nginx.config | string | `""` | Whole `nginx.conf`, rendered through `tpl`, so it may reference any value, e.g. `{{ .Values.nginx.send_timeout }}`. When set, it replaces the built-in config and the four timeout keys above apply only where it references them. It must not include `/etc/nginx/conf.d/*.conf` — see [Custom nginx.conf](#custom-nginxconf). |
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

## Custom nginx.conf

`nginx.config` replaces the whole `nginx.conf` of the NginX sidecar. Leave it empty and the chart renders its built-in config, unchanged from 0.5.0. The chart renders the string through `tpl`, so it can reference other values, as the example does with `service.port`.

```yaml
nginx:
  enabled: true
  config: |
    worker_processes auto;
    events {}
    http {
      upstream app {
        server unix:/tmp/uvicorn.sock;
      }
      server {
        listen {{ .Values.service.port }};
        location / {
          proxy_pass http://app;
        }
      }
    }
```

- **The Service targets the sidecar's `http` port, and nginx proxies to the app over the unix socket `/tmp/uvicorn.sock`**, which the app container creates in the shared `socket` volume. The chart sets the `http` container port to `service.port`, so the config must `listen` on that number.
- **Don't include `/etc/nginx/conf.d/*.conf`.** The official `nginx` image ships `conf.d/default.conf`, a server on port 80. If the container runs as non-root with capabilities dropped, nginx can't bind port 80 and exits at startup. As root, that server can take requests meant for your own server block.
- **The four timeout keys** (`keepalive_timeout`, `proxy_read_timeout`, `proxy_send_timeout`, `send_timeout`) apply only where your config references them.
- **A config change rolls the pods.** The file is mounted with `subPath`, and a `subPath` mount never receives ConfigMap updates. So when `nginx.config` is set, the Deployment's pod template carries a `checksum/nginx-config` annotation of the rendered config.

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)

## Pre-deploy job

`fastapi.preDeployJob` runs one Job before every install and upgrade, for example a database migration. It is a Helm `pre-install,pre-upgrade` hook, so Argo CD runs it as a PreSync hook. The Job uses the release image and the chart's ServiceAccount, and it receives the same environment as the application: `env.variables`, `existingSecretName` and every `envFromSecretsManager` path.

```yaml
fastapi:
  preDeployJob:
    enabled: true
    command: ["alembic"]
    args: ["upgrade", "head"]
```

Do not enable the Job on the first install of a release. The ExternalSecrets and the Secrets they create are ordinary resources, and they do not exist yet when the hook runs. Install the release with the Job disabled, then enable it.

## Component labels

The chart adds `app.kubernetes.io/component` to every pod it creates:

| Pod | Label value |
|---|---|
| The application Deployment | `web` |
| A worker from `fastapi.workers[]` | `worker-<name>` |
| The pre-deploy Job | `pre-deploy-job` |

The Service selects `app.kubernetes.io/component: web`, so it sends traffic to application pods only. Before 0.7.0 the Service also selected worker pods.

**Upgrading from 0.6.x.** The Service selector changes before the new application pods are ready. The Service has no endpoints until the first new pod passes its readiness probe. The Deployment selectors do not change.
