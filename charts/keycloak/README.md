# keycloak

Keycloak (Quarkus) on the official image as a StatefulSet with an external database

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 26.8.2](https://img.shields.io/badge/AppVersion-26.8.2-informational?style=flat-square)

Keycloak on the official `quay.io/keycloak/keycloak` image, run with `kc.sh start` as a StatefulSet against an external database. Clustering uses `jdbc-ping`, so the pods find each other through the database without Kubernetes API access. Ready-made values are in [`examples/`](examples):

| File | Shows |
|---|---|
| `values-production-ha.yaml` | 3 replicas, Ingress with the admin console on an internal host, NetworkPolicy, ServiceMonitor, HPA, PDB, realm import |
| `values-gateway-api-eso.yaml` | Gateway API HTTPRoute, credentials from an ExternalSecret, Reloader |
| `values-aws-alb.yaml` | AWS ALB with TLS at the load balancer, an existing Secret, a theme JAR from an image, a JVM flag |

## Image

Pin the digest. `image.digest` renders as `repository:tag@digest`, so the digest is what runs and the tag stays readable:

```yaml
image:
  tag: "26.8.2"
  digest: sha256:7e66a96e4739239070aeaf72e4c5decf0f7f682cfc725b9f7ea2b336eaba38b3
```

The chart passes `start`, never `start-dev`. The stock image is not pre-built, so `start` re-augments at every boot (about 10-20 s). With an image built by `kc.sh build`, set `optimized: true`; the image then ignores every build-time option the chart sets (cache, database vendor, health, metrics, features).

## Read-only root filesystem

The containers run with `readOnlyRootFilesystem: true` under the restricted Pod Security Standard (uid 1000, no capabilities, `RuntimeDefault` seccomp). Keycloak writes to three emptyDirs: `/tmp`, `/opt/keycloak/data` (transaction logs) and `/opt/keycloak/lib/quarkus`. The re-augmentation of a non-optimized `start` needs the image's own `lib/quarkus` in place, and an empty directory fails with `quarkus-application.dat` missing. So the init container `seed-quarkus`, from the Keycloak image itself, copies it into the emptyDir first. With `optimized: true` the seed and that emptyDir are left out.

## Database and secrets

Each database field and the bootstrap admin take either a plain `value` or a `secretKeyRef`. The Secret reference wins when both are set. `database.password` and `bootstrapAdmin.password` accept only a Secret reference.

```yaml
database:
  vendor: postgres
  host:
    secretKeyRef: {name: keycloak-secrets, key: KEYCLOAK_DB_HOST}
  database:
    value: keycloak
  username:
    secretKeyRef: {name: keycloak-secrets, key: KEYCLOAK_DB_USER}
  password:
    secretKeyRef: {name: keycloak-secrets, key: KEYCLOAK_DB_PASSWORD}
  schema:
    value: public
```

A `secretKeyRef` without `name` points to the Secret of the chart's own ExternalSecret (`externalSecret.enabled`, `external-secrets.io/v1`). Keycloak reads the database password only from env, CLI or a config file, so the secrets reach the container as `secretKeyRef` env vars.

Plain Keycloak options go in `config` as `option-name: value`, rendered as `KC_OPTION_NAME` into the env ConfigMap. `extraEnv` wins over everything the chart sets. The pods carry `checksum/config` and, with the ExternalSecret, `checksum/secret`. Changes to the data of an existing Secret need Reloader (`reloader.enabled`), which annotates the StatefulSet with every Secret and ConfigMap the pod references.

JVM flags go in `jvm.jdkJavaOptions` (`JDK_JAVA_OPTIONS`, read by the java launcher) or `jvm.javaOptsAppend` (`JAVA_OPTS_APPEND`, appended by kc.sh). Never set `JAVA_OPTS`: it replaces the kc.sh defaults, including the heap `-XX:MaxRAMPercentage=70`.

## Values layering (Flux valuesFrom, several -f files)

Maps merge key by key and lists are replaced whole. Everything an environment overlay usually changes is a map or a scalar: `hostname.url`, `config`, `providers`, `podAnnotations`, `nodeSelector`, `ingress.annotations`, `resources`. `providers` is a map keyed by name, so a base can set `source` and an overlay only `image`, where a Flux `# {"$imagepolicy": "..."}` marker on the plain `image:` line keeps working:

```yaml
providers:
  example-theme:
    image: 123456789012.dkr.ecr.us-east-1.amazonaws.com/keycloak-themes:42 # {"$imagepolicy": "flux-system:keycloak-themes"}
    source: /usr/theme/example-theme
```

Each provider becomes an init container that copies `<source>/.` into an emptyDir mounted at `/opt/keycloak/providers` (or `/opt/keycloak/themes` with `target: themes`). It runs as uid 1000, so the files in the image must be readable by that user.

`hostname.url`, `hostname.adminUrl`, `ingress.host`, `ingress.admin.host`, `httpRoute.hostnames` and `extraObjects` are rendered with `tpl`, so `adminUrl: "{{ .Values.hostname.url }}"` works.

## Clustering

`cache.stack` defaults to `jdbc-ping`, Keycloak's default since 26.1. `kubernetes` (DNS_PING on the headless Service, deprecated since 26.3) also works: the chart adds the JGroups DNS query to `JAVA_OPTS_APPEND`. From 26.8 set `cache.nodeNameFromPod: true` (`KC_CACHE_EMBEDDED_NODE_NAME` from the pod name); Keycloak 26.1 has no such option.

## Networking

The Service carries http (and https). The headless Service, which governs the StatefulSet, adds the management port 9000 with `/health/*` and `/metrics`; it is never on the Ingress or HTTPRoute. Probes and the ServiceMonitor follow `http.managementRelativePath`, which inherits `http.relativePath`.

**Keep the admin console off the public entry point.** List only the public paths on the main Ingress (`/realms/`, `/resources/`, `/robots.txt`) and serve the admin console through `ingress.admin`: a second Ingress with its own class, annotations (an internal load balancer, a source-IP allow list) and host. On a separate admin host, also set `hostname.adminUrl` to it and add `/realms/master/` and `/resources/` to `ingress.admin.paths`. With Gateway API, list only the public paths in `httpRoute.rules` and attach a second route on an internal Gateway through `extraObjects`.

`httpRoute.rules` are Gateway API `HTTPRouteRule`s. A rule without `backendRefs` goes to the chart's Service, except a `RequestRedirect` rule, which must not have any.

`networkPolicy.enabled` denies everything except DNS to kube-system and traffic between the pods of the release (clustering on 7800/57800, the hook and the test pod). Allow the ingress controller, gateway or ALB subnets (`ingressFrom`), Prometheus (`metricsFrom`) and the database (`databaseTo`, on `database.port.value`). Outbound calls such as SMTP, identity brokering or social login need `extraEgress`.

## Upgrading Keycloak

A configuration change on the same Keycloak version rolls pod by pod (`updateStrategy.type: RollingUpdate`).

**A new Keycloak version is different.** The first node of the new version migrates the database schema, one way. Old nodes cannot run against the migrated schema, and the versions must not run side by side, even between 26.8.x patch releases. A change of `cache.stack` also needs every node stopped. So:

1. Back up the database right before.
2. Size the startup probe for the migration: `startupProbe.failureThreshold` x `periodSeconds` must cover it. For example, the 26.6 `REALM_ID` backfill took about 22 min per 10M offline client sessions. Raise the Helm (or Flux) timeout to match.
3. Turn off automatic rollback for this upgrade (Flux: `upgrade.remediation.retries: 0`). A rollback would start the old version against the migrated schema.
4. Stop every node: `replicaCount: 0` (and `autoscaling.enabled: false`). Then deploy the new image with `replicaCount: 1`, wait until the pod is Ready, and scale back up. Alternatively, set `updateStrategy.type: OnDelete` and delete all pods at once.

Rollback means restoring the database backup and deploying the old image. Everything written since the backup is lost.

## Selector labels

The StatefulSet selects `app.kubernetes.io/name`, `app.kubernetes.io/instance` and `app.kubernetes.io/component: keycloak`. A StatefulSet selector is immutable: changing `nameOverride` or the release name, or moving from another Keycloak chart with the same StatefulSet name, means deleting the StatefulSet first (logins fail until the new pods are Ready) or picking another `fullnameOverride`.

## Hooks

`realmImport.enabled` adds a post-install/post-upgrade Job that applies `realmImport.realms` with [keycloak-config-cli](https://github.com/adorsys/keycloak-config-cli), idempotently. It logs in with the bootstrap admin, so it needs `bootstrapAdmin.password`. Set `realmImport.image.tag` to the keycloak-config-cli build for your Keycloak version. Secrets in realm files can be referenced as `$(env:NAME)` and passed with `realmImport.extraEnv`.

`helm test <release>` runs a pod that checks `/health/ready` and `/realms/master/.well-known/openid-configuration`.

## Values

### Scheduling

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| affinity | object | `{}` | Affinity |
| autoscaling | object | `{"behavior":{"scaleDown":{"policies":[{"periodSeconds":60,"type":"Percent","value":50}],"stabilizationWindowSeconds":300},"scaleUp":{"policies":[{"periodSeconds":30,"type":"Percent","value":100}],"stabilizationWindowSeconds":0}},"enabled":false,"maxReplicas":5,"minReplicas":3,"targetCPUUtilizationPercentage":80}` | HorizontalPodAutoscaler (autoscaling/v2) on CPU. Memory is no signal for a JVM. |
| autoscaling.behavior | object | `{"scaleDown":{"policies":[{"periodSeconds":60,"type":"Percent","value":50}],"stabilizationWindowSeconds":300},"scaleUp":{"policies":[{"periodSeconds":30,"type":"Percent","value":100}],"stabilizationWindowSeconds":0}}` | HPA behavior. Default: scale down slowly (300 s window, 50 % per minute), up fast. |
| nodeSelector | object | `{}` | Node selector |
| podDisruptionBudget | object | `{"enabled":true,"maxUnavailable":1,"minAvailable":null}` | PodDisruptionBudget (policy/v1). Set exactly one of `maxUnavailable` and `minAvailable` (null the other). |
| priorityClassName | string | `""` | PriorityClass of the pods |
| tolerations | list | `[]` | Tolerations |
| topologySpreadConstraints | list | `[{"maxSkew":1,"topologyKey":"topology.kubernetes.io/zone","whenUnsatisfiable":"ScheduleAnyway"},{"maxSkew":1,"topologyKey":"kubernetes.io/hostname","whenUnsatisfiable":"ScheduleAnyway"}]` | Topology spread. A constraint without `labelSelector` gets the chart's selector labels. The defaults spread over zones and nodes but never block scheduling (`ScheduleAnyway`), like a preferred anti-affinity. |

### Database

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| bootstrapAdmin | object | `{"password":{"secretKeyRef":{}},"username":{"secretKeyRef":{},"value":"admin"}}` | Temporary admin created on the first start against an empty database (KC_BOOTSTRAP_ADMIN_USERNAME / KC_BOOTSTRAP_ADMIN_PASSWORD; `KEYCLOAK_ADMIN` is deprecated). Same `value` / `secretKeyRef` shape as `database`. Not rendered while the password is unset. The realm-import hook uses these credentials too. |
| database | object | `{"database":{"secretKeyRef":{},"value":""},"host":{"secretKeyRef":{},"value":""},"password":{"secretKeyRef":{}},"port":{"secretKeyRef":{},"value":"5432"},"schema":{"secretKeyRef":{},"value":""},"url":{"secretKeyRef":{},"value":""},"urlProperties":"","username":{"secretKeyRef":{},"value":""},"vendor":"postgres"}` | External database. Each field takes either `value` (goes to the env ConfigMap) or `secretKeyRef: {name, key}` (goes to the container env and wins over `value`). An empty `secretKeyRef.name` means the Secret of the chart's own ExternalSecret. |
| database.database | object | `{"secretKeyRef":{},"value":""}` | KC_DB_URL_DATABASE |
| database.host | object | `{"secretKeyRef":{},"value":""}` | KC_DB_URL_HOST |
| database.password | object | `{"secretKeyRef":{}}` | KC_DB_PASSWORD. Secret only: the schema rejects `value`. |
| database.port | object | `{"secretKeyRef":{},"value":"5432"}` | KC_DB_URL_PORT. Also the egress port of the NetworkPolicy. |
| database.schema | object | `{"secretKeyRef":{},"value":""}` | KC_DB_SCHEMA |
| database.url | object | `{"secretKeyRef":{},"value":""}` | KC_DB_URL, a full JDBC URL. Overrides host, port and database. |
| database.urlProperties | string | `""` | KC_DB_URL_PROPERTIES, e.g. `?sslmode=require` |
| database.username | object | `{"secretKeyRef":{},"value":""}` | KC_DB_USERNAME |
| database.vendor | string | `"postgres"` | KC_DB: postgres, mysql, mariadb, mssql, oracle |

### Cache

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| cache | object | `{"nodeNameFromPod":false,"stack":"jdbc-ping","type":"ispn"}` | Infinispan clustering |
| cache.nodeNameFromPod | bool | `false` | Set KC_CACHE_EMBEDDED_NODE_NAME from the pod name, as the 26.8 upgrade guide recommends for non-operator setups. Keycloak 26.1 has no such option: keep it off there. |
| cache.stack | string | `"jdbc-ping"` | KC_CACHE_STACK: `jdbc-ping` (default since 26.1, nodes find each other through the database) or `kubernetes` (DNS_PING on the headless Service, deprecated since 26.3). Changing it needs every node stopped. |
| cache.type | string | `"ispn"` | KC_CACHE: `ispn` (clustered) or `local` (single node only) |

### Keycloak

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| config | object | `{}` | Plain Keycloak options as `<option-name>: <value>`, rendered into the env ConfigMap as `KC_<OPTION_NAME>`. A map, so values layers (e.g. Flux valuesFrom) merge key by key. Secrets go through the `database`, `bootstrapAdmin` or `extraEnv` secret references, never here. |
| extraArgs | list | `[]` | Extra arguments after `start [--optimized]`. The chart always runs `start`, never `start-dev`. |
| hostname | object | `{"adminUrl":"","strict":true,"url":""}` | Public URL of Keycloak (KC_HOSTNAME), e.g. `https://id.example.com/`. Rendered with tpl. Required unless `hostname.strict` is false. Its host is also the default Ingress and HTTPRoute host. |
| hostname.adminUrl | string | `""` | Admin console URL (KC_HOSTNAME_ADMIN). Rendered with tpl, so `"{{ .Values.hostname.url }}"` works. |
| hostname.strict | bool | `true` | KC_HOSTNAME_STRICT |
| http | object | `{"enabled":true,"managementPort":9000,"managementRelativePath":"","port":8080,"relativePath":"/"}` | HTTP listener. TLS usually ends at the load balancer, so plain HTTP is on (KC_HTTP_ENABLED). |
| http.managementPort | int | `9000` | Management port: `/health/*` and `/metrics` (KC_HTTP_MANAGEMENT_PORT). Never exposed on the Ingress. |
| http.managementRelativePath | string | `""` | KC_HTTP_MANAGEMENT_RELATIVE_PATH. Empty inherits `relativePath`, as Keycloak does. Probes and the ServiceMonitor follow it. |
| http.relativePath | string | `"/"` | KC_HTTP_RELATIVE_PATH. `/` keeps every URL and the token issuer at the root. |
| https | object | `{"certificateSecret":"","enabled":false,"port":8443}` | HTTPS listener on 8443 with a `kubernetes.io/tls` Secret mounted as files (KC_HTTPS_CERTIFICATE_FILE / KC_HTTPS_CERTIFICATE_KEY_FILE) |
| jvm | object | `{"javaOptsAppend":"","jdkJavaOptions":""}` | JVM options. Never set JAVA_OPTS: it replaces the kc.sh defaults, including the heap `-XX:MaxRAMPercentage=70`. |
| jvm.javaOptsAppend | string | `""` | JAVA_OPTS_APPEND, appended by kc.sh after its defaults. With `cache.stack: kubernetes` the chart prepends `-Djgroups.dns.query=<headless>.<namespace>.svc.cluster.local`; another `-Djgroups.dns.query` here wins. |
| jvm.jdkJavaOptions | string | `""` | JDK_JAVA_OPTIONS, read by the java launcher itself (log line `NOTE: Picked up JDK_JAVA_OPTIONS`). E.g. `-XX:-UseBASE64Intrinsics` (CVE-2026-114938). |
| metrics | object | `{"enabled":true}` | Expose `/metrics` on the management port (KC_METRICS_ENABLED). Health (KC_HEALTH_ENABLED) is always on: the probes need it. |
| optimized | bool | `false` | Pass `--optimized` to `kc.sh start`. Only for images pre-built with `kc.sh build`: the stock image is not, and with `--optimized` it ignores every build-time option set here (cache, db, health, metrics, features). |
| proxy | object | `{"headers":""}` | Which proxy headers to trust (KC_PROXY_HEADERS): `xforwarded`, `forwarded` or empty for none. Set it only when every request comes through the proxy, otherwise clients can spoof their address and scheme. |

### Security

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| emptyDirSizeLimits | object | `{"data":"256Mi","providers":"256Mi","quarkus":"64Mi","tmp":"256Mi"}` | Size limits of the emptyDirs behind the read-only root: `/tmp`, `/opt/keycloak/data` (transaction logs) and, unless `optimized`, `/opt/keycloak/lib/quarkus`. A non-optimized `start` re-augments into lib/quarkus at boot, and an empty dir there fails (`quarkus-application.dat` missing), so an init container from the Keycloak image first copies the image's lib/quarkus into it (2-5 MiB). |
| emptyDirSizeLimits.providers | string | `"256Mi"` | Each of the `providers` and `themes` emptyDirs |
| podSecurityContext | object | `{"fsGroup":1000,"fsGroupChangePolicy":"OnRootMismatch","runAsNonRoot":true,"runAsUser":1000,"seccompProfile":{"type":"RuntimeDefault"}}` | Pod security context (restricted Pod Security Standard). uid 1000 is the keycloak user of the official image. |
| securityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true,"runAsNonRoot":true}` | Security context of every container the chart renders (Keycloak, init containers, hooks) |
| serviceAccount | object | `{"annotations":{},"automountServiceAccountToken":false,"create":true,"name":""}` | ServiceAccount. Keycloak does not call the Kubernetes API with either cache stack. |
| serviceAccount.annotations | object | `{}` | Annotations, e.g. `eks.amazonaws.com/role-arn` |
| serviceAccount.automountServiceAccountToken | bool | `false` | Mount the API token into the pod |
| serviceAccount.name | string | `""` | Name. Empty uses the full name. Keep it stable when an IRSA trust policy references it. |

### Secrets

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| externalSecret | object | `{"data":[],"dataFrom":[],"enabled":false,"name":"","refreshInterval":"1m","secretStoreRef":{"kind":"ClusterSecretStore","name":"global-secret-store"}}` | ExternalSecret (external-secrets.io/v1) whose Secret the `secretKeyRef`s with an empty name point to |
| externalSecret.data | list | `[]` | Single keys, e.g. `[{secretKey: db-password, remoteRef: {key: myapp/prod/keycloak, property: password}}]` |
| externalSecret.dataFrom | list | `[]` | Whole secrets to extract, e.g. `[{extract: {key: myapp/prod/keycloak}}]`. Set this or `data`. |
| externalSecret.name | string | `""` | Name of the ExternalSecret and its Secret. Empty: `<fullname>-secrets`. |
| reloader | object | `{"enabled":false,"mode":"targeted"}` | Stakater Reloader annotations on the StatefulSet |
| reloader.mode | string | `"targeted"` | `targeted`: `secret.reloader.stakater.com/reload` / `configmap.reloader.stakater.com/reload` with every Secret and ConfigMap the pod references; `auto`: `reloader.stakater.com/auto: "true"` |

### Extras

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| extraContainers | list | `[]` | Sidecar containers |
| extraEnv | list | `[]` | Extra env vars of the Keycloak container (EnvVar list). They win over everything the chart sets. |
| extraEnvFrom | list | `[]` | Extra envFrom sources of the Keycloak container |
| extraObjects | list | `[]` | Extra manifests, rendered with tpl |
| extraVolumeMounts | list | `[]` | Extra volume mounts of the Keycloak container |
| extraVolumes | list | `[]` | Extra pod volumes |
| initContainers | list | `[]` | Extra init containers, run after the provider init containers |
| podAnnotations | object | `{}` | Annotations of the pods, e.g. `karpenter.sh/do-not-disrupt: "true"` |
| podLabels | object | `{}` | Labels of the pods (not part of the selector) |

### Networking

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| httpRoute | object | `{"annotations":{},"enabled":false,"hostnames":[],"labels":{},"parentRefs":[],"rules":[{"matches":[{"path":{"type":"PathPrefix","value":"/"}}]}]}` | Gateway API HTTPRoute (gateway.networking.k8s.io/v1) |
| httpRoute.hostnames | list | `[]` | Hostnames. Rendered with tpl. Empty takes the host of `hostname.url`. |
| httpRoute.parentRefs | list | `[]` | Gateways to attach to, e.g. `[{name: public, namespace: gateway, sectionName: https}]`. Required when enabled. |
| httpRoute.rules | list | `[{"matches":[{"path":{"type":"PathPrefix","value":"/"}}]}]` | HTTPRouteRules (matches, filters, backendRefs, timeouts). A rule without `backendRefs` goes to the chart's Service on the http port. |
| ingress | object | `{"admin":{"annotations":{},"className":"","enabled":false,"host":"","paths":[],"tls":[]},"annotations":{},"className":"","enabled":false,"host":"","paths":[{"path":"/","pathType":"Prefix"}],"tls":[]}` | Ingress (networking.k8s.io/v1) to the http port |
| ingress.admin | object | `{"annotations":{},"className":"","enabled":false,"host":"","paths":[],"tls":[]}` | A second Ingress `<fullname>-admin` with its own class, annotations and host, e.g. an internal load balancer or a source-IP allow list. Independent of `ingress.enabled`. Empty `host` takes the main Ingress host. |
| ingress.admin.paths | list | `[]` | Paths. Empty: `<relativePath>admin/`. On a separate admin host (with `hostname.adminUrl` pointing at it) also add `/realms/master/` and `/resources/`. |
| ingress.host | string | `""` | Host. Rendered with tpl. Empty takes the host of `hostname.url`. |
| ingress.paths | list | `[{"path":"/","pathType":"Prefix"}]` | Paths to the http port. To keep the admin console off the public Ingress, list only the public paths (`/realms/`, `/resources/`, `/robots.txt`) and serve `/admin/` through `ingress.admin`. |
| ingress.tls | list | `[]` | TLS entries (`[{secretName, hosts}]`). Empty `hosts` take `host`. Leave empty when TLS ends at the load balancer. |
| networkPolicy | object | `{"databaseTo":[],"enabled":false,"extraEgress":[],"extraIngress":[],"ingressFrom":[],"metricsFrom":[]}` | NetworkPolicy, default deny. Always allowed: DNS to kube-system, and all traffic between this release's pods (clustering on 7800/57800, the hook and test pods). |
| networkPolicy.databaseTo | list | `[]` | Egress peers of the database (`ipBlock` of the RDS subnets), on `database.port.value` |
| networkPolicy.extraEgress | list | `[]` | Extra egress rules |
| networkPolicy.extraIngress | list | `[]` | Extra ingress rules. Identity brokering, SMTP and other outbound calls need `extraEgress`. |
| networkPolicy.ingressFrom | list | `[]` | Peers allowed to the http(s) port: ingress controller or gateway pods, or the load balancer subnets (`ipBlock`) for ALB `target-type: ip` |
| networkPolicy.metricsFrom | list | `[]` | Peers allowed to the management port, e.g. Prometheus |
| service | object | `{"annotations":{},"labels":{},"type":"ClusterIP"}` | Service for HTTP(S). The management port is only on the headless Service. |
| service.annotations | object | `{}` | Annotations, e.g. ALB health-check settings for `target-type: ip` |

### Image

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| image | object | `{"digest":"","pullPolicy":"IfNotPresent","repository":"quay.io/keycloak/keycloak","tag":""}` | Keycloak image. `tag` defaults to the chart appVersion. With `digest` set the image renders as `repository:tag@digest`, so the digest is what runs and the tag stays readable. |
| imagePullSecrets | list | `[]` | Registry credentials for private images (list of `{name: <secret>}`) |

### Providers

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| initContainerResources | object | `{"limits":{"memory":"64Mi"},"requests":{"cpu":"10m","memory":"32Mi"}}` | Resources of the init containers the chart renders (the lib/quarkus seed and the providers) |
| providers | object | `{}` | Provider JARs and themes copied from images. A map, so values layers merge per entry: a base can set `source` and an env overlay only `image` (where a Flux `$imagepolicy` marker works on the plain `image:` line). Each entry renders an init container `provider-<name>` that runs `cp -R <source>/. /target/`, where `/target` is an emptyDir mounted in Keycloak at `/opt/keycloak/providers` (`target: providers`, the default) or `/opt/keycloak/themes` (`target: themes`). The image needs `sh` and `cp`, and its files must be readable by uid 1000. `command` replaces the copy command and must write to `/target`. |

### Probes

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| livenessProbe | object | `{"enabled":true,"failureThreshold":5,"periodSeconds":30,"timeoutSeconds":5}` | Liveness probe on `<management path>/health/live`. Kept loose: a restart never fixes a slow database. |
| readinessProbe | object | `{"enabled":true,"failureThreshold":3,"periodSeconds":10,"timeoutSeconds":2}` | Readiness probe on `<management path>/health/ready` (HTTP, not TCP: since 26.6 the ports open before init ends) |
| startupProbe | object | `{"enabled":true,"failureThreshold":90,"initialDelaySeconds":15,"periodSeconds":10,"timeoutSeconds":2}` | Startup probe on `<management path>/health/started`. The chart sets `httpGet`; only timings live here. Size `failureThreshold` x `periodSeconds` for the first start of a new version: the schema migration runs before the probe passes (the 26.6 REALM_ID backfill took about 22 min per 10M offline client sessions). |

### Workload

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| podManagementPolicy | string | `"Parallel"` | `Parallel` starts and stops all pods at once; `OrderedReady` one by one |
| replicaCount | int | `1` | Pod replicas. Ignored while `autoscaling.enabled`. |
| resources | object | `{"limits":{"memory":"1Gi"},"requests":{"cpu":"500m","memory":"1Gi"}}` | Container resources. No CPU limit: the boot-time re-augmentation and JIT warm-up are CPU-heavy and a limit only throttles them. kc.sh sizes the heap at 70% of the memory limit. |
| revisionHistoryLimit | int | `3` | Old controller revisions kept for rollback (null falls back to the Kubernetes default of 10) |
| terminationGracePeriodSeconds | int | `60` | Seconds between SIGTERM and SIGKILL |
| updateStrategy | object | `{"type":"RollingUpdate"}` | StatefulSet update strategy. `RollingUpdate` is safe for config changes on the same version only. A Keycloak minor or patch upgrade migrates the schema one way and must not run next to the old version: see README "Upgrading Keycloak" (scale to 0, or `type: OnDelete`). |

### Hooks

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| realmImport | object | `{"activeDeadlineSeconds":900,"backoffLimit":1,"deletePolicy":"before-hook-creation,hook-succeeded","enabled":false,"existingConfigMap":"","extraEnv":[],"hooks":"post-install,post-upgrade","image":{"digest":"","pullPolicy":"IfNotPresent","repository":"adorsys/keycloak-config-cli","tag":""},"realms":{},"resources":{"limits":{"memory":"512Mi"},"requests":{"cpu":"100m","memory":"256Mi"}}}` | Post-install / post-upgrade Job that applies realm files with keycloak-config-cli (idempotent). Off by default. It logs in with `bootstrapAdmin` and reaches Keycloak through the chart's Service. |
| realmImport.deletePolicy | string | `"before-hook-creation,hook-succeeded"` | `helm.sh/hook-delete-policy` |
| realmImport.existingConfigMap | string | `""` | Use an existing ConfigMap of realm files instead of `realms` |
| realmImport.extraEnv | list | `[]` | Extra env, e.g. secrets referenced from realm files with `$(env:NAME)` (IMPORT_VARSUBSTITUTION_ENABLED is on) |
| realmImport.hooks | string | `"post-install,post-upgrade"` | Hook events |
| realmImport.image | object | `{"digest":"","pullPolicy":"IfNotPresent","repository":"adorsys/keycloak-config-cli","tag":""}` | keycloak-config-cli image. Its tag carries the Keycloak version it was built for (e.g. `6.5.1-26.1.0`): pick the one closest to `image.tag`. Required when enabled. |
| realmImport.realms | object | `{}` | Realm files as `<file name>: <realm representation>` (real YAML, rendered to JSON in a ConfigMap) |
| tests | object | `{"enabled":true,"image":{"digest":"","pullPolicy":"IfNotPresent","repository":"busybox","tag":"1.37"},"resources":{"limits":{"memory":"32Mi"},"requests":{"cpu":"10m","memory":"16Mi"}}}` | `helm test` pod: checks `/health/ready` and `/realms/master/.well-known/openid-configuration` |

### Monitoring

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| serviceMonitor | object | `{"enabled":false,"interval":"30s","labels":{},"metricRelabelings":[],"relabelings":[],"scrapeTimeout":"10s"}` | Prometheus Operator ServiceMonitor (monitoring.coreos.com/v1) on the management port, path `<management path>/metrics`. Needs `metrics.enabled`. |
| serviceMonitor.labels | object | `{}` | Labels the Prometheus `serviceMonitorSelector` matches, e.g. `release: kube-prometheus-stack` |

### Other Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| commonLabels | object | `{}` | Labels added to every resource, e.g. `app.kubernetes.io/part-of` or an `owner` label an admission policy needs |
| fullnameOverride | string | `""` | Overrides the full resource name. Not part of any selector. |
| nameOverride | string | `""` | Overrides the chart name (`app.kubernetes.io/name`). Part of the StatefulSet selector: changing it later forces a delete and recreate of the StatefulSet. |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
