# fastapi

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 1.16.0](https://img.shields.io/badge/AppVersion-1.16.0-informational?style=flat-square)

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| affinity | object | `{}` | Affinity rules for pod placement |
| autoscaling | object | `{"enabled":false,"maxReplicas":100,"minReplicas":1,"targetCPUUtilizationPercentage":80}` | Autoscaling configuration |
| fastapi | object | `{"env":{"envFromSecretsManager":{"enabled":false,"secretPath":"path/to/secret"},"variables":{}},"image":{"pullPolicy":"IfNotPresent","repository":"my-fastapi-image","tag":"latest"},"livenessProbe":{"httpGet":{"path":"/health","port":8000},"initialDelaySeconds":10,"periodSeconds":10},"readinessProbe":{"httpGet":{"path":"/health","port":8000},"initialDelaySeconds":10,"periodSeconds":10},"resources":{},"securityContext":{},"volumeMounts":[],"volumes":[],"workers":[]}` | FastAPI-specific configurations |
| fastapi.env | object | `{"envFromSecretsManager":{"enabled":false,"secretPath":"path/to/secret"},"variables":{}}` | Environment variables configuration |
| fastapi.env.envFromSecretsManager.enabled | bool | `false` | Enable fetching secrets from an external secrets manager (e.g., AWS) |
| fastapi.env.envFromSecretsManager.secretPath | string | `"path/to/secret"` | Path to the secret in the external secrets manager |
| fastapi.env.variables | object | `{}` | Key-value pairs of environment variables (will be base64 encoded in the secret) |
| fastapi.image.pullPolicy | string | `"IfNotPresent"` | Image pull policy (Always, IfNotPresent, Never) |
| fastapi.image.repository | string | `"my-fastapi-image"` | FastAPI Docker image repository |
| fastapi.image.tag | string | `"latest"` | Tag of the FastAPI image |
| fastapi.livenessProbe | object | `{"httpGet":{"path":"/health","port":8000},"initialDelaySeconds":10,"periodSeconds":10}` | Liveness probe configuration for FastAPI |
| fastapi.readinessProbe | object | `{"httpGet":{"path":"/health","port":8000},"initialDelaySeconds":10,"periodSeconds":10}` | Readiness probe configuration for FastAPI |
| fastapi.resources | object | `{}` | Resource limits and requests for the FastAPI container |
| fastapi.securityContext | object | `{}` | Security context for the FastAPI container |
| fastapi.volumeMounts | list | `[]` | Additional volume mounts for FastAPI container |
| fastapi.volumes | list | `[]` | Additional volumes for FastAPI pods |
| fastapi.workers | list | `[]` | Configuration for FastAPI workers |
| fullnameOverride | string | `""` | Overrides full release name |
| imagePullSecrets | list | `[]` | Secret used to store Docker registry credentials |
| ingress.annotations | object | `{}` |  |
| ingress.className | string | `""` |  |
| ingress.enabled | bool | `false` | Enables ingress when true |
| ingress.hosts[0].host | string | `"chart-example.local"` |  |
| ingress.hosts[0].paths[0].path | string | `"/"` |  |
| ingress.hosts[0].paths[0].pathType | string | `"ImplementationSpecific"` |  |
| ingress.tls | list | `[]` |  |
| nameOverride | string | `""` | Overrides release name |
| nginx | object | `{"image":{"pullPolicy":"IfNotPresent","repository":"nginx","tag":"alpine"},"livenessProbe":{"httpGet":{"path":"/","port":80},"initialDelaySeconds":10,"periodSeconds":10},"readinessProbe":{"httpGet":{"path":"/","port":80},"initialDelaySeconds":10,"periodSeconds":10},"resources":{},"securityContext":{},"volumeMounts":[],"volumes":[]}` | NginX-specific configurations |
| nginx.image.pullPolicy | string | `"IfNotPresent"` | Image pull policy (Always, IfNotPresent, Never) |
| nginx.image.repository | string | `"nginx"` | NginX Docker image repository |
| nginx.image.tag | string | `"alpine"` | Tag of the NginX image |
| nginx.livenessProbe | object | `{"httpGet":{"path":"/","port":80},"initialDelaySeconds":10,"periodSeconds":10}` | Liveness probe configuration for NginX |
| nginx.readinessProbe | object | `{"httpGet":{"path":"/","port":80},"initialDelaySeconds":10,"periodSeconds":10}` | Readiness probe configuration for NginX |
| nginx.resources | object | `{}` | Resource limits and requests for NginX container |
| nginx.securityContext | object | `{}` | Security context for the NginX container |
| nginx.volumeMounts | list | `[]` | Additional volume mounts for the NginX container |
| nginx.volumes | list | `[]` | Additional volumes for the NginX pods |
| nodeSelector | object | `{}` | Node selector for pod placement |
| podAnnotations | object | `{}` | Annotations to add to the pods |
| podLabels | object | `{}` | Labels to add to the pods |
| podSecurityContext | object | `{}` | Security context for the pod |
| replicaCount | int | `1` | Number of replicas to spin up |
| service | object | `{"port":80,"type":"ClusterIP"}` | Service configuration |
| service.port | int | `80` | Port exposed by the service |
| service.type | string | `"ClusterIP"` | Type of Kubernetes service (ClusterIP, NodePort, LoadBalancer) |
| serviceAccount | object | `{"annotations":{},"automount":true,"create":true,"name":""}` | Service Account configuration |
| serviceAccount.annotations | object | `{}` | Annotations to add to the service account |
| serviceAccount.automount | bool | `true` | Automatically mount a ServiceAccount's API credentials? |
| serviceAccount.create | bool | `true` | Specifies whether a service account should be created |
| serviceAccount.name | string | `""` | The name of the service account to use |
| tolerations | list | `[]` | Tolerations for pod placement |
