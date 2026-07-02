# django

![Version: 0.2.4](https://img.shields.io/badge/Version-0.2.4-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 1.27.4](https://img.shields.io/badge/AppVersion-1.27.4-informational?style=flat-square)

## Values

### Django Settings

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| django | object | A complex object. Please check values below | Django Specific Configurations |
| django.args | list | `[]` | Override the default container arguments |
| django.command | list | `[]` | Override the default container command |
| django.cronJobs | list | [ ] | Enables cron jobs |
| django.env | object | `{"envFromSecretsManager":{"enabled":false,"secretPath":"dev/example-com/env-secrets"},"variables":{"DEBUG":"True","PYTHONDONTWRITEBYTECODE":"1","PYTHONUNBUFFERED":"1"}}` | Django environment variables |
| django.env.envFromSecretsManager | object | `{"enabled":false,"secretPath":"dev/example-com/env-secrets"}` | Use AWS secrets manager ref. Works with external-secrets operator |
| django.env.variables | object | `{"DEBUG":"True","PYTHONDONTWRITEBYTECODE":"1","PYTHONUNBUFFERED":"1"}` | Extra env variables |
| django.image | object | `{"pullPolicy":"IfNotPresent","repository":"django","tag":""}` | Django image settings |
| django.image.tag | string | `""` | Overrides the image tag whose default is the chart appVersion |
| django.migrationJob | object | `{"enabled":false}` | Enables migration job before rolling the update |
| django.port | int | `8000` | Port the app binds to (and the container/probe port) when the NginX sidecar is disabled (nginx.enabled=false). Keep it above 1024 so the container can bind without root / NET_BIND_SERVICE. When the NginX sidecar is enabled the app listens on a UNIX socket and this value is unused. |
| django.readinessProbe | object | `{}` | Django container readiness probe. Leave empty to use the chart's mode-aware default: a UNIX socket check (ls /tmp/uvicorn.sock) when the NginX sidecar is enabled, or a TCP check on the app port when it is disabled. Set a value here to override the default. |
| django.resources | object | `{}` | Django container resources |
| django.securityContext | object | `{}` | Django container security context |
| django.volumeMounts | list | `[]` | Django container additional volumes mounts |
| django.volumes | list | `[]` | Django container additional volumes |
| django.workers | list | [ ] | Enables Django Workers |

### Networking Settings

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| ingress | object | `{"annotations":{},"className":"","enabled":false,"hosts":[{"host":"chart-example.local","paths":[{"path":"/","pathType":"ImplementationSpecific"}]}],"tls":[]}` | Ingress settings. Each path optionally accepts a `backend` field to override the default service backend — see [Per-path custom backend](#per-path-custom-backend). |
| service | object | `{"port":80,"type":"ClusterIP"}` | Service settings |

### NginX Settings

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| nginx | object | A complex object. Please check values below | NginX Specific Configurations |
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
