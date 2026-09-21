# nextjs

![Version: 0.7.0](https://img.shields.io/badge/Version-0.7.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 1.16.0](https://img.shields.io/badge/AppVersion-1.16.0-informational?style=flat-square)

A Helm chart for Kubernetes

## Values

### Networking Settings

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| ingress | object | `{"annotations":{},"className":"","enabled":false,"hosts":[{"host":"chart-example.local","paths":[{"path":"/","pathType":"ImplementationSpecific"}]}],"tls":[]}` | Ingress settings. Each path optionally accepts a `backend` field to override the default service backend — see [Per-path custom backend](#per-path-custom-backend). |
| service | object | `{"port":80,"type":"ClusterIP"}` | Service settings |

### Next.js Settings

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| nextjs | object | A complex object. Please check values below | Next.js Specific Configurations |
| nextjs.env.envFromSecretsManager | object | `{"enabled":false,"refreshInterval":"1m","secretPath":"","secretPaths":[],"secretStoreKind":"ClusterSecretStore","secretStoreName":"global-secret-store"}` | Use AWS secrets manager ref. Works with external-secrets operator. Each path renders its own ExternalSecret, mounted as env after `existingSecretName`. |
| nextjs.env.envFromSecretsManager.enabled | bool | `false` | Render the ExternalSecrets and mount them as env |
| nextjs.env.envFromSecretsManager.refreshInterval | string | `"1m"` | How often External Secrets Operator refreshes the secrets |
| nextjs.env.envFromSecretsManager.secretPath | string | `""` | Single secret path, e.g. `dev/example-com/env-secrets`. Set either this or `secretPaths`; setting both fails the render, and so does setting neither while `enabled` is true. |
| nextjs.env.envFromSecretsManager.secretPaths | list | `[]` | Secret paths mounted in list order. On key collisions a later path wins over an earlier one. Set either this or `secretPath`. |
| nextjs.env.envFromSecretsManager.secretStoreKind | string | `"ClusterSecretStore"` | Kind of the secret store: ClusterSecretStore or SecretStore |
| nextjs.env.envFromSecretsManager.secretStoreName | string | `"global-secret-store"` | Name of the secret store the ExternalSecrets reference |
| nextjs.env.existingSecretName | string | `""` | Name of an existing Secret to mount as env (e.g. one managed by External Secrets Operator). Mounted additively alongside `variables` and `envFromSecretsManager` on the deployment and the pre-deploy job — it does NOT disable `variables`. On key collisions the existing Secret wins over `variables` (it is mounted after), and `envFromSecretsManager` wins over both. |
| nextjs.env.variables | object | `{}` | Extra plain (non-secret) env variables. Always injected, even when existingSecretName is set. |
| nextjs.image | object | `{"pullPolicy":"IfNotPresent","repository":"nextjs","tag":""}` | Next.js image settings |
| nextjs.image.tag | string | `""` | Overrides the image tag whose default is the chart appVersion |
| nextjs.livenessProbe | object | `{}` | Next.js container liveness probe. Not rendered unless set. |
| nextjs.port | int | `3000` | Next.js environment variables |
| nextjs.preDeployJob | object | `{"args":[],"backoffLimit":6,"command":[],"enabled":false}` | Enables pre-deploy job with Helm hook before rolling the update |
| nextjs.preDeployJob.args | list | `[]` | Arguments to pass to the command |
| nextjs.preDeployJob.backoffLimit | int | `6` | Number of retries before marking the job as failed |
| nextjs.preDeployJob.command | list | `[]` | Command to run in the job container |
| nextjs.readinessProbe | object | `{}` | Next.js container readiness probe. Not rendered unless set. |
| nextjs.resources | object | `{}` | Next.js container resources |
| nextjs.securityContext | object | `{}` | Next.js container security context |
| nextjs.startupProbe | object | `{}` | Next.js container startup probe. Not rendered unless set. |
| nextjs.volumeMounts | list | `[]` | Next.js container additional volumes mounts |
| nextjs.volumes | list | `[]` | Next.js container additional volumes |

### NginX Settings

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| nginx | object | A complex object. Please check values below | NginX Specific Configurations |
| nginx.config | string | `""` | Whole `nginx.conf`, rendered through `tpl`, so it may reference any value, e.g. `{{ .Values.nginx.send_timeout }}`. When set, it replaces the built-in config and the four timeout keys above apply only where it references them. It must not include `/etc/nginx/conf.d/*.conf` — see [Custom nginx.conf](#custom-nginxconf). |
| nginx.enabled | bool | `true` | Enable NginX sidecar |
| nginx.image | object | `{"pullPolicy":"IfNotPresent","repository":"nginx","tag":""}` | NginX image settings |
| nginx.image.tag | string | `""` | Overrides the image tag whose default is the chart appVersion |
| nginx.keepalive_timeout | int | `65` | Timeout during which a keep-alive client connection will stay open on the server side |
| nginx.proxy_read_timeout | string | `"60s"` | Timeout for reading a response from the proxied server |
| nginx.proxy_send_timeout | string | `"60s"` | Timeout for transmitting a request to the proxied server |
| nginx.resources | object | `{}` | NginX container resources |
| nginx.securityContext | object | `{}` | NginX container security context |
| nginx.send_timeout | string | `"60s"` | Timeout for transmitting a response to the client |
| nginx.volumeMounts | list | `[]` | NginX container additional volumes mounts |
| nginx.volumes | list | `[]` | NginX container additional volumes |

### PDB Settings

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| pdb | object | `{"create":false,"minAvailable":1}` | Pod Disruption Budget settings |

### Other Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| affinity | object | `{}` | Affinity settings |
| autoscaling | object | `{"enabled":false,"maxReplicas":100,"minReplicas":1,"targetCPUUtilizationPercentage":80}` | Autoscaling settings |
| fullnameOverride | string | `""` | Overrides full release name |
| imagePullSecrets | list | `[]` | Secret that used to store docker registry credentials |
| ingress.enabled | bool | `false` | Enables ingress when true |
| nameOverride | string | `""` | Overrides release name |
| nodeSelector | object | `{}` | Node selector settings |
| podAnnotations | object | `{}` | Annotations to add to the pod |
| podLabels | object | `{}` | Labels to add to the pod |
| podSecurityContext | object | `{}` | Security context of the pod |
| replicaCount | int | `1` | Number of replicas to sping up |
| revisionHistoryLimit | int | `3` | Old ReplicaSets retained for rollback (set null to fall back to the Kubernetes default of 10) |
| serviceAccount | object | `{"annotations":{},"automount":true,"create":true,"name":""}` | Service Account |
| serviceAccount.annotations | object | `{}` | Annotations to add to the service account |
| serviceAccount.automount | bool | `true` | Automatically mount a ServiceAccount's API credentials? |
| serviceAccount.create | bool | `true` | Specifies whether a service account should be created |
| serviceAccount.name | string | `""` | The name of the service account to use. |
| tolerations | list | `[]` | Tolerations settings |

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

`nextjs.env.envFromSecretsManager.secretPaths` renders one ExternalSecret per path, named `<fullname>-env-ext-secrets-<index>`, and mounts them with `envFrom` in list order after `existingSecretName`. Kubernetes gives the last `envFrom` source precedence for a duplicate key, so a later path overrides an earlier one. This lets a release take shared defaults from one secret and override some of them from another.

```yaml
nextjs:
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

The chart renders no probes on the Next.js container by default. Each of `nextjs.startupProbe`, `nextjs.readinessProbe` and `nextjs.livenessProbe` is rendered only when set.

```yaml
nextjs:
  startupProbe:
    httpGet:
      path: /
      port: http
    periodSeconds: 5
    failureThreshold: 30
  readinessProbe:
    httpGet:
      path: /
      port: http
    periodSeconds: 10
```

## Custom nginx.conf

`nginx.config` replaces the whole `nginx.conf` of the NginX sidecar. Leave it empty and the chart renders its built-in config, unchanged from 0.6.0. The chart renders the string through `tpl`, so it can reference other values, as the example does with `service.port` and `nextjs.port`.

```yaml
nginx:
  enabled: true
  config: |
    worker_processes auto;
    events {}
    http {
      server {
        listen {{ .Values.service.port }};
        location / {
          proxy_pass http://localhost:{{ .Values.nextjs.port }};
        }
      }
    }
```

- **The Service targets the sidecar's `nginx` port, and nginx proxies to the Next.js container in the same pod** over `localhost`. The chart sets the `nginx` container port to `service.port`, so the config must `listen` on that number.
- **Don't include `/etc/nginx/conf.d/*.conf`.** The official `nginx` image ships `conf.d/default.conf`, a server on port 80. If the container runs as non-root with capabilities dropped, nginx can't bind port 80 and exits at startup. As root, that server can take requests meant for your own server block.
- **The four timeout keys** (`keepalive_timeout`, `proxy_read_timeout`, `proxy_send_timeout`, `send_timeout`) apply only where your config references them.
- **A config change rolls the pods.** The file is mounted with `subPath`, and a `subPath` mount never receives ConfigMap updates. So when `nginx.config` is set, the pod template carries a `checksum/nginx-config` annotation of the rendered config.

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
