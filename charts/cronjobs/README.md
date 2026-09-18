# cronjobs

![Version: 0.5.0](https://img.shields.io/badge/Version-0.5.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 1.16.0](https://img.shields.io/badge/AppVersion-1.16.0-informational?style=flat-square)

A Helm chart for Kubernetes

## Values

### Cron Settings

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| env | object | `{"envFromSecretsManager":{"enabled":false,"refreshInterval":"1m","secretPath":"","secretPaths":[],"secretStoreKind":"ClusterSecretStore","secretStoreName":"global-secret-store"},"existingSecretName":"","variables":{}}` | Cron environment variables |
| env.envFromSecretsManager | object | `{"enabled":false,"refreshInterval":"1m","secretPath":"","secretPaths":[],"secretStoreKind":"ClusterSecretStore","secretStoreName":"global-secret-store"}` | Use AWS secrets manager ref. Works with external-secrets operator. Each path renders its own ExternalSecret, mounted as env after `existingSecretName`. |
| env.envFromSecretsManager.enabled | bool | `false` | Render the ExternalSecrets and mount them as env |
| env.envFromSecretsManager.refreshInterval | string | `"1m"` | How often External Secrets Operator refreshes the secrets |
| env.envFromSecretsManager.secretPath | string | `""` | Single secret path, e.g. `dev/example-com/env-secrets`. Set either this or `secretPaths`; setting both fails the render, and so does setting neither while `enabled` is true. |
| env.envFromSecretsManager.secretPaths | list | `[]` | Secret paths mounted in list order. On key collisions a later path wins over an earlier one. Set either this or `secretPath`. |
| env.envFromSecretsManager.secretStoreKind | string | `"ClusterSecretStore"` | Kind of the secret store: ClusterSecretStore or SecretStore |
| env.envFromSecretsManager.secretStoreName | string | `"global-secret-store"` | Name of the secret store the ExternalSecrets reference |
| env.existingSecretName | string | `""` | Name of an existing Secret to mount as env (e.g. one managed by External Secrets Operator). Mounted additively alongside `variables` and `envFromSecretsManager` — it does NOT disable `variables`. On key collisions the existing Secret wins over `variables`, and `envFromSecretsManager` wins over both. |
| env.variables | object | `{}` | Extra plain (non-secret) env variables. Always injected, even when existingSecretName is set. |

### Other Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| cronJobs | list | `[{"affinity":{},"concurrencyPolicy":"Forbid","containerCommand":["bash","-c","echo $(date)"],"cronSchedule":"*/1 * * * *","enabled":true,"extraVolumeMounts":[],"extraVolumes":[],"failedJobsHistoryLimit":1,"image":{"imagePullPolicy":"Always","repository":"ubuntu","tag":"latest"},"name":"my_awesome_django_cron","nodeSelector":[],"resources":{},"restartPolicy":"OnFailure","securityContext":{},"successfulJobsHistoryLimit":3,"tolerations":[]}]` | Cron Job List |
| fullnameOverride | string | `""` | Override full release name |
| imagePullSecrets | list | `[]` | Image pull secrets |
| nameOverride | string | `""` | Override release name |
| serviceAccount | object | `{"annotations":{},"automount":true,"create":true,"name":""}` | Service account configuration |
| serviceAccount.annotations | object | `{}` | Annotations to add to the service account |
| serviceAccount.automount | bool | `true` | Automatically mount a ServiceAccount's API credentials? |
| serviceAccount.create | bool | `true` | Specifies whether a service account should be created |
| serviceAccount.name | string | `""` | The name of the service account to use. If not set and create is true, a name is generated using the fullname template |

## Several Secrets Manager paths

`env.envFromSecretsManager.secretPaths` renders one ExternalSecret per path, named `<fullname>-env-ext-secrets-<index>`, and mounts them with `envFrom` in list order after `existingSecretName`. Kubernetes gives the last `envFrom` source precedence for a duplicate key, so a later path overrides an earlier one. This lets a release take shared defaults from one secret and override some of them from another.

```yaml
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

`enabled` now defaults to `false` and `secretPath` to empty. Earlier versions shipped `enabled: true` with a default path, so a release that mounted Secrets Manager through the chart defaults alone must now set `enabled` and one of the two path settings itself.

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
