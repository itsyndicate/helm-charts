# django

![Version: 0.0.1](https://img.shields.io/badge/Version-0.0.1-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 1.27.4](https://img.shields.io/badge/AppVersion-1.27.4-informational?style=flat-square)

## Values

### Django Settings

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| django | object | A complex object. Please check values below | Django Specific Configurations |
| django.cronJobs | list | [ ] | Enables cron jobs |
| django.env | object | `{"envFromSecretsManager":{"enabled":false,"secretPath":"dev/example-com/env-secrets"},"variables":{"DEBUG":"True","PYTHONDONTWRITEBYTECODE":"1","PYTHONUNBUFFERED":"1"}}` | Django environment variables |
| django.env.envFromSecretsManager | object | `{"enabled":false,"secretPath":"dev/example-com/env-secrets"}` | Use AWS secrets manager ref. Works with external-secrets operator |
| django.env.variables | object | `{"DEBUG":"True","PYTHONDONTWRITEBYTECODE":"1","PYTHONUNBUFFERED":"1"}` | Extra env variables |
| django.image | object | `{"pullPolicy":"IfNotPresent","repository":"django","tag":""}` | Django image settings |
| django.image.tag | string | `""` | Overrides the image tag whose default is the chart appVersion |
| django.migrationJob | object | `{"enabled":false}` | Enables migration job before rolling the update |
| django.readinessProbe | object | `{"exec":{"command":["ls","/tmp/uvicorn.sock"]},"initialDelaySeconds":5,"periodSeconds":5}` | Django container readiness probe |
| django.resources | object | `{}` | Django container resources |
| django.securityContext | object | `{}` | Django container security context |
| django.volumeMounts | list | `[]` | Django container additional volumes mounts |
| django.volumes | list | `[]` | Django container additional volumes |
| django.workers | list | [ ] | Enables Django Workers |

### Networking Settings

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| ingress | object | `{"annotations":{},"className":"","enabled":false,"hosts":[{"host":"chart-example.local","paths":[{"path":"/","pathType":"ImplementationSpecific"}]}],"tls":[]}` | Ingress settings |
| service | object | `{"port":80,"type":"ClusterIP"}` | Service settings |

### NginX Settings

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| nginx | object | A complex object. Please check values below | NginX Specific Configurations |
| nginx.image | object | `{"pullPolicy":"IfNotPresent","repository":"nginx","tag":""}` | NginX image settings |
| nginx.image.tag | string | `""` | Overrides the image tag whose default is the chart appVersion |
| nginx.resources | object | `{}` | NginX container resources |
| nginx.securityContext | object | `{}` | NginX container security context |
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
