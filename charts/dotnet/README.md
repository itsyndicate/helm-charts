# dotnet

![Version: 0.0.1](https://img.shields.io/badge/Version-0.0.1-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 0.0.1](https://img.shields.io/badge/AppVersion-0.0.1-informational?style=flat-square)

## Values

### Dotnet APP Settings

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| dotnet | object | A complex object. Please check values below | Dotnet APP Specific Configurations |
| dotnet.env.envFromSecretsManager | object | `{"enabled":false,"secretPath":"dev/example-com/env-secrets"}` | Use AWS secrets manager ref. Works with external-secrets operator |
| dotnet.env.variables | object | `{"APP_DOMAIN":"example.com"}` | Extra env variables |
| dotnet.image | object | `{"pullPolicy":"IfNotPresent","repository":"mcr.microsoft.com/dotnet/samples","tag":""}` | Dotnet APP image settings |
| dotnet.image.tag | string | `""` | Overrides the image tag whose default is the chart appVersion |
| dotnet.port | int | `5001` | Dotnet APP environment variables |
| dotnet.resources | object | `{}` | Dotnet APP container resources |
| dotnet.securityContext | object | `{}` | Dotnet APP container security context |
| dotnet.volumeMounts | list | `[]` | Dotnet APP container additional volumes mounts |
| dotnet.volumes | list | `[]` | Dotnet APP container additional volumes |

### Networking Settings

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| ingress | object | `{"annotations":{},"className":"","enabled":false,"hosts":[{"host":"chart-example.local","paths":[{"path":"/","pathType":"ImplementationSpecific"}]}],"tls":[]}` | Ingress settings |
| service | object | `{"port":5001,"type":"ClusterIP"}` | Service settings |

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
