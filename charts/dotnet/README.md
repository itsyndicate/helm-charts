# dotnet

![Version: 0.3.0](https://img.shields.io/badge/Version-0.3.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 0.0.1](https://img.shields.io/badge/AppVersion-0.0.1-informational?style=flat-square)

## Values

### Dotnet APP Settings

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| dotnet | object | A complex object. Please check values below | Dotnet APP Specific Configurations |
| dotnet.env.envFromSecretsManager | object | `{"enabled":false,"refreshInterval":"1m","secretPath":"","secretPaths":[],"secretStoreKind":"ClusterSecretStore","secretStoreName":"global-secret-store"}` | Use AWS secrets manager ref. Works with external-secrets operator. Each path renders its own ExternalSecret, mounted as env after `existingSecretName`. |
| dotnet.env.envFromSecretsManager.enabled | bool | `false` | Render the ExternalSecrets and mount them as env |
| dotnet.env.envFromSecretsManager.refreshInterval | string | `"1m"` | How often External Secrets Operator refreshes the secrets |
| dotnet.env.envFromSecretsManager.secretPath | string | `""` | Single secret path, e.g. `dev/example-com/env-secrets`. Set either this or `secretPaths`; setting both fails the render, and so does setting neither while `enabled` is true. |
| dotnet.env.envFromSecretsManager.secretPaths | list | `[]` | Secret paths mounted in list order. On key collisions a later path wins over an earlier one. Set either this or `secretPath`. |
| dotnet.env.envFromSecretsManager.secretStoreKind | string | `"ClusterSecretStore"` | Kind of the secret store: ClusterSecretStore or SecretStore |
| dotnet.env.envFromSecretsManager.secretStoreName | string | `"global-secret-store"` | Name of the secret store the ExternalSecrets reference |
| dotnet.env.existingSecretName | string | `""` | Name of an existing Secret to mount as env (e.g. one managed by External Secrets Operator). Mounted additively alongside `variables` and `envFromSecretsManager` — it does NOT disable `variables`. On key collisions the existing Secret wins over `variables`, and `envFromSecretsManager` wins over both. |
| dotnet.env.variables | object | `{}` | Extra plain (non-secret) env variables. Always injected, even when existingSecretName is set. |
| dotnet.image | object | `{"pullPolicy":"IfNotPresent","repository":"mcr.microsoft.com/dotnet/samples","tag":""}` | Dotnet APP image settings |
| dotnet.image.tag | string | `""` | Overrides the image tag whose default is the chart appVersion |
| dotnet.livenessProbe | object | `{}` | Dotnet APP container liveness probe. Not rendered unless set. |
| dotnet.port | object | `{"name":"http","number":5001,"protocol":"TCP"}` | Dotnet APP environment variables |
| dotnet.readinessProbe | object | `{}` | Dotnet APP container readiness probe. Not rendered unless set. |
| dotnet.resources | object | `{}` | Dotnet APP container resources |
| dotnet.securityContext | object | `{}` | Dotnet APP container security context |
| dotnet.startupProbe | object | `{}` | Dotnet APP container startup probe. Not rendered unless set. |
| dotnet.volumeMounts | list | `[]` | Dotnet APP container additional volumes mounts |
| dotnet.volumes | list | `[]` | Dotnet APP container additional volumes |

### Networking Settings

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| ingress | object | `{"annotations":{},"className":"","enabled":false,"hosts":[{"host":"chart-example.local","paths":[{"path":"/","pathType":"ImplementationSpecific"}]}],"tls":[]}` | Ingress settings |
| service | object | `{"appProtocol":"http","extraPorts":[],"name":"http","port":5001,"protocol":"TCP","targetPort":"http","type":"ClusterIP"}` | Service settings service:  type: ClusterIP  port: 5001  ## @param service.extraPorts Extra ports to expose  ##  extraPorts: [] |

### PDB Settings

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| pdb | object | `{"create":false}` | Pod Disruption Budget settings |

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

`dotnet.env.envFromSecretsManager.secretPaths` renders one ExternalSecret per path, named `<fullname>-env-ext-secrets-<index>`, and mounts them with `envFrom` in list order after `existingSecretName`. Kubernetes gives the last `envFrom` source precedence for a duplicate key, so a later path overrides an earlier one. This lets a release take shared defaults from one secret and override some of them from another.

```yaml
dotnet:
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

Each of `dotnet.startupProbe`, `dotnet.readinessProbe` and `dotnet.livenessProbe` is rendered only when set. Earlier versions emitted `livenessProbe: null` and `readinessProbe: null` on the container whenever they were left unset.

```yaml
dotnet:
  startupProbe:
    httpGet:
      path: /
      port: http
    periodSeconds: 5
    failureThreshold: 30
```

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
