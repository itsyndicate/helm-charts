# fastapi

![Version: 0.3.4](https://img.shields.io/badge/Version-0.3.4-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 1.16.0](https://img.shields.io/badge/AppVersion-1.16.0-informational?style=flat-square)

A Helm chart for Kubernetes

## Values

### FastAPI Settings

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| fastapi | object | A complex object. Please check values below | FastAPI-specific configurations |
| fastapi.args | list | `[]` | Override the default container arguments |
| fastapi.command | list | `[]` | Override the default container command |
| fastapi.env.envFromSecretsManager | object | `{"enabled":false,"secretPath":"path/to/secret"}` | Use AWS secrets manager ref. Works with external-secrets operator |
| fastapi.env.variables | object | `{}` | Key-value pairs of environment variables (will be base64 encoded in the secret) |
| fastapi.image | object | `{"pullPolicy":"IfNotPresent","repository":"my-fastapi-image","tag":"latest"}` | FastAPI image settings |
| fastapi.image.tag | string | `"latest"` | Tag of the FastAPI image |
| fastapi.livenessProbe | object | `{}` | Liveness probe for FastAPI. Leave empty to use the chart's mode-aware default: no liveness probe when the NginX sidecar is enabled (app on a UNIX socket), or an HTTP check on /health at the app port when it is disabled. Set a value here to override. |
| fastapi.port | int | `8000` | Port the app binds to (and the container/probe port) when the NginX sidecar is disabled (nginx.enabled=false). Keep it above 1024 so the container can bind without root / NET_BIND_SERVICE. When the NginX sidecar is enabled the app listens on a UNIX socket and this value is unused. |
| fastapi.readinessProbe | object | `{}` | Readiness probe for FastAPI. Leave empty to use the chart's mode-aware default: a UNIX socket check (ls /tmp/uvicorn.sock) when the NginX sidecar is enabled, or an HTTP check on /health at the app port when it is disabled. Set a value here to override. |
| fastapi.resources | object | `{}` | Resource limits and requests for the FastAPI container |
| fastapi.securityContext | object | `{}` | Security context for the FastAPI container |
| fastapi.volumeMounts | list | `[]` | Additional volume mounts for FastAPI container |
| fastapi.volumes | list | `[]` | Additional volumes for FastAPI pods |
| fastapi.workers | list | `[]` | Configuration for FastAPI workers |

### Networking Settings

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| ingress | object | `{"annotations":{},"className":"","enabled":false,"hosts":[{"host":"chart-example.local","paths":[{"path":"/","pathType":"ImplementationSpecific"}]}],"tls":[]}` | Ingress settings. Each path optionally accepts a `backend` field to override the default service backend — see [Per-path custom backend](#per-path-custom-backend). |
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

### Other Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| affinity | object | `{}` | Affinity rules for pod placement |
| autoscaling | object | `{"enabled":false,"maxReplicas":100,"minReplicas":1,"targetCPUUtilizationPercentage":80}` | Autoscaling configuration |
| fastapi.env.envFromSecretsManager.enabled | bool | `false` | Enable fetching secrets from an external secrets manager (e.g., AWS) |
| fastapi.env.envFromSecretsManager.secretPath | string | `"path/to/secret"` | Path to the secret in the external secrets manager |
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

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
