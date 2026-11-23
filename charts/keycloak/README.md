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
| autoscaling | object | A complex object. Please check values below | HorizontalPodAutoscaler (autoscaling/v2) on CPU. Memory is no signal for a JVM. |
| autoscaling.behavior | object | `{"scaleDown":{"policies":[{"periodSeconds":120,"type":"Pods","value":1}],"selectPolicy":"Min","stabilizationWindowSeconds":300},"scaleUp":{"policies":[{"periodSeconds":30,"type":"Percent","value":100}],"stabilizationWindowSeconds":0}}` | HPA behavior. Scale down one pod per 2 minutes after a 300 s window, up fast. Do not copy a stateless default here: authenticationSessions and actionTokens have 2 in-memory owners, so several Infinispan members leaving at once lose in-flight logins. |
| autoscaling.enabled | bool | `false` | Render the HPA; `replicaCount` is then ignored. Turning it on for a running release removes `spec.replicas` from the StatefulSet, which drops it to 1 pod once until the HPA acts: do it in a quiet window. |
| autoscaling.maxReplicas | int | `5` | Maximum replicas. Size the database for it: `maxReplicas` x `db-pool-max-size` connections. |
| autoscaling.minReplicas | int | `3` | Minimum replicas |
| autoscaling.targetCPUAverageValue | string | `""` | Average CPU per pod as an absolute value, e.g. `400m`. When set, it replaces `targetCPUUtilizationPercentage`, so the threshold does not depend on `resources.requests.cpu`. |
| autoscaling.targetCPUUtilizationPercentage | int | `80` | Average CPU utilization, in percent of `resources.requests.cpu` |
| nodeSelector | object | `{}` | Node selector |
| podDisruptionBudget | object | `{"enabled":true,"maxUnavailable":1,"minAvailable":null,"unhealthyPodEvictionPolicy":"AlwaysAllow"}` | PodDisruptionBudget (policy/v1). Set exactly one of `maxUnavailable` and `minAvailable` (null the other). |
| podDisruptionBudget.enabled | bool | `true` | Render the PodDisruptionBudget |
| podDisruptionBudget.maxUnavailable | int | `1` | Pods a voluntary disruption may take down at once (number or percentage). 1 serialises node drains. With one replica it still lets a drain evict the only pod. |
| podDisruptionBudget.minAvailable | string | `nil` | Pods that must stay available (number or percentage). Set `maxUnavailable: null` to use it. |
| podDisruptionBudget.unhealthyPodEvictionPolicy | string | `"AlwaysAllow"` | `AlwaysAllow` lets a node drain evict pods that are not Ready (e.g. crash-looping) whatever the budget says. Empty leaves the field out (Kubernetes default: `IfHealthyBudget`). The field needs Kubernetes 1.27, the chart's `kubeVersion`. |
| priorityClassName | string | `""` | PriorityClass of the pods |
| tolerations | list | `[]` | Tolerations |
| topologySpreadConstraints | list | `[{"maxSkew":1,"topologyKey":"topology.kubernetes.io/zone","whenUnsatisfiable":"ScheduleAnyway"},{"maxSkew":1,"topologyKey":"kubernetes.io/hostname","whenUnsatisfiable":"ScheduleAnyway"}]` | Topology spread. A constraint without `labelSelector` gets the chart's selector labels. The defaults spread over zones and nodes but never block scheduling (`ScheduleAnyway`), like a preferred anti-affinity. |

### Database

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| bootstrapAdmin | object | A complex object. Please check values below | Temporary admin: a user, a service account, or both (`KEYCLOAK_ADMIN` is deprecated). Applied only when the master realm is created, i.e. on the first start against an empty database: on an existing database it does nothing, and changing the Secret later changes nothing in Keycloak. Create a permanent admin of the master realm and check that it works before you remove the temporary one: without one nobody can administer the master realm any more, and the chart has no way back. Then remove `bootstrapAdmin` from your values, so the credential does not stay in the pod. Same `value` / `secretKeyRef` shape as `database`. The realm-import hook has its own credentials (`realmImport.auth`). |
| bootstrapAdmin.client | object | `{"id":{"secretKeyRef":{},"value":""},"secret":{"secretKeyRef":{}}}` | Temporary admin service account (KC_BOOTSTRAP_ADMIN_CLIENT_ID / KC_BOOTSTRAP_ADMIN_CLIENT_SECRET), independent of the user above and under the same rules. Not rendered while the secret is unset. An empty `id` leaves Keycloak's default, `temp-admin`. |
| bootstrapAdmin.client.id | object | `{"secretKeyRef":{},"value":""}` | KC_BOOTSTRAP_ADMIN_CLIENT_ID |
| bootstrapAdmin.client.secret | object | `{"secretKeyRef":{}}` | KC_BOOTSTRAP_ADMIN_CLIENT_SECRET. Secret only. |
| bootstrapAdmin.password | object | `{"secretKeyRef":{}}` | KC_BOOTSTRAP_ADMIN_PASSWORD. Secret only. The temporary user is not rendered while this is unset. |
| bootstrapAdmin.username | object | `{"secretKeyRef":{},"value":"admin"}` | KC_BOOTSTRAP_ADMIN_USERNAME |
| database | object | A complex object. Please check values below | External database. Each field takes either `value` or `secretKeyRef: {name, key}`; both render into the container `env`, and `secretKeyRef` wins. An empty `secretKeyRef.name` means the Secret of the chart's own ExternalSecret. `host` or `url` is required. |
| database.database | object | `{"secretKeyRef":{},"value":""}` | KC_DB_URL_DATABASE |
| database.host | object | `{"secretKeyRef":{},"value":""}` | KC_DB_URL_HOST |
| database.password | object | `{"secretKeyRef":{}}` | KC_DB_PASSWORD. Secret only: the schema rejects `value`. Leave it unset when Keycloak reads the password from a mounted `keycloak.conf` instead of the environment (README "Database and secrets"). Keycloak reads `$$` in the value as `$`, and silently drops a value that contains a `${...}` it cannot resolve. |
| database.port | object | `{"secretKeyRef":{},"value":""}` | KC_DB_URL_PORT. Empty lets Keycloak use the vendor's default port. Also the egress port of the NetworkPolicy. |
| database.schema | object | `{"secretKeyRef":{},"value":""}` | KC_DB_SCHEMA. When this chart takes over an existing database, set the schema that database uses: with another one Keycloak initialises a new, empty schema. |
| database.url | object | `{"secretKeyRef":{},"value":""}` | KC_DB_URL, a full JDBC URL. Overrides host, port and database. |
| database.urlProperties | string | `""` | KC_DB_URL_PROPERTIES with the leading `?`, e.g. `?sslmode=require` |
| database.username | object | `{"secretKeyRef":{},"value":""}` | KC_DB_USERNAME |
| database.vendor | string | `"postgres"` | KC_DB: postgres, mysql, mariadb, mssql, oracle |

### Cache

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| cache | object | `{"nodeNameFromPod":true,"stack":"jdbc-ping","type":"ispn"}` | Infinispan clustering |
| cache.nodeNameFromPod | bool | `true` | Set KC_CACHE_EMBEDDED_NODE_NAME from the pod name, as the 26.8 upgrading guide recommends for non-operator setups. The option exists since 26.8.0: set it to false for older images (26.1.4 ignored the variable). |
| cache.stack | string | `"jdbc-ping"` | KC_CACHE_STACK: `jdbc-ping` (default since 26.1, nodes find each other through the database) or `kubernetes` (DNS_PING on the headless Service, deprecated since 26.3). Changing it needs every node stopped. The schema takes Keycloak's built-in stacks only; a custom one goes through `extraEnv` (KC_CACHE_STACK). |
| cache.type | string | `"ispn"` | KC_CACHE: `ispn` (clustered) or `local` (single node only) |

### Keycloak

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| config | object | `{"log-console-output":"json","shutdown-delay":"15s"}` | Plain Keycloak options as `<option-name>: <value>`, rendered into the env ConfigMap as `KC_<OPTION_NAME>`. A map, so values layers (e.g. Flux valuesFrom) merge key by key; null drops a default. The chart refuses to render the options that have a dedicated value (`db`, `db-url*`, `db-schema`, `db-username`, `hostname`, `hostname-admin`, `hostname-strict`, `proxy-headers`, `proxy-trusted-addresses`, ports and relative paths, `http-management-*`, `health-enabled`, `metrics-enabled`, `cache`, `cache-stack`, the TLS certificate files, `bootstrap-admin-*`) and every name ending in `password`, `secret` or `-pass`: secrets go through the `database`, `bootstrapAdmin` or `extraEnv` secret references, never into a ConfigMap. The error names the option. |
| config.log-console-output | string | `"json"` | Structured logs. About ten lines per start stay plain text (messages of kc.sh and of the build JVM). |
| config.shutdown-delay | string | `"15s"` | Keep serving this long after SIGTERM, while readiness already fails, so load balancers drain first (Keycloak default: 1s). `terminationGracePeriodSeconds` must stay above shutdown-delay + shutdown-timeout (10s). |
| extraArgs | list | `[]` | Extra arguments after `start [--optimized]`. The chart always runs `start`, never `start-dev`. `--config-file` does not work here (a global option, it must come before `start`): set `KC_CONFIG_FILE` through `extraEnv`. |
| hostname | object | `{"adminUrl":"","strict":true,"url":""}` | Public and admin URLs of Keycloak |
| hostname.adminUrl | string | `""` | Admin console URL (KC_HOSTNAME_ADMIN), e.g. an internal host served by `ingress.admin`. Rendered with tpl twice, so `"{{ .Values.hostname.url }}"` works even when `hostname.url` is a template itself. Empty: the console answers on the public URL. |
| hostname.strict | bool | `true` | KC_HOSTNAME_STRICT. Leave it true: once `url` is set, false changes nothing, and without a URL it lets Keycloak take its host name from request headers. |
| hostname.url | string | `""` | Public URL of Keycloak (KC_HOSTNAME), e.g. `https://id.example.com/`. Rendered with tpl. Required unless `hostname.strict` is false. Its host is also the default Ingress and HTTPRoute host. Give the full `https://` URL, not a bare host name: with it plain-HTTP calls inside the cluster (the realm-import hook, the test) also work from pod IPs outside RFC 1918 (e.g. EKS 100.64.0.0/10), which otherwise get a 403. |
| http | object | `{"enabled":true,"managementPort":9000,"managementRelativePath":"","port":8080,"relativePath":"/"}` | HTTP listener and the management interface |
| http.enabled | bool | `true` | Plain HTTP listener (KC_HTTP_ENABLED). On by default: TLS usually ends at the load balancer. |
| http.managementPort | int | `9000` | Management port: `/health/*` and `/metrics` (KC_HTTP_MANAGEMENT_PORT). Never exposed on the Ingress. Health and metrics are always enabled: the probes need health, and the database check of `/health/ready` only exists while metrics are enabled. |
| http.managementRelativePath | string | `""` | KC_HTTP_MANAGEMENT_RELATIVE_PATH. Empty inherits `relativePath`, as Keycloak does. Probes and the ServiceMonitor follow it. |
| http.port | int | `8080` | Container port of http (KC_HTTP_PORT). The Service port is `service.port`. |
| http.relativePath | string | `"/"` | KC_HTTP_RELATIVE_PATH. `/` keeps every URL and the token issuer at the root. |
| https | object | `{"certificateSecret":"","enabled":false,"port":8443}` | HTTPS listener with a `kubernetes.io/tls` Secret mounted as files (KC_HTTPS_CERTIFICATE_FILE / KC_HTTPS_CERTIFICATE_KEY_FILE) |
| https.certificateSecret | string | `""` | Name of the `kubernetes.io/tls` Secret (`tls.crt`, `tls.key`) |
| https.enabled | bool | `false` | Enable the HTTPS listener. Needs `certificateSecret`. The management port (probes, metrics) then speaks HTTPS too. While `http.enabled` is also true, the Ingress, HTTPRoute, hook and test keep using http. |
| https.port | int | `8443` | Container port of https (KC_HTTPS_PORT). The Service port is `service.httpsPort`. |
| jvm | object | `{"javaOptsAppend":"","jdkJavaOptions":""}` | JVM options. Never set JAVA_OPTS: it replaces the kc.sh defaults, including the heap `-XX:MaxRAMPercentage=70`. |
| jvm.javaOptsAppend | string | `""` | JAVA_OPTS_APPEND, appended by kc.sh after its defaults. With `cache.stack: kubernetes` the chart prepends `-Djgroups.dns.query=<headless>.<namespace>.svc.cluster.local`; another `-Djgroups.dns.query` here wins, which a cluster domain other than `cluster.local` needs. |
| jvm.jdkJavaOptions | string | `""` | JDK_JAVA_OPTIONS, read by the java launcher itself (log line `NOTE: Picked up JDK_JAVA_OPTIONS`). E.g. `-XX:-UseBASE64Intrinsics` (CVE-2026-114938), only needed on images with a JDK older than 21.0.13.1. |
| optimized | bool | `false` | Pass `--optimized` to `kc.sh start`. Only for images pre-built with `kc.sh build`; the stock image is not. 26.8.2 refuses to start (exit code 2) when a build-time option differs from the build, so build the image with the same `db`, `features`, `http-relative-path`, `http-management-relative-path`, `health-enabled=true` and `metrics-enabled=true`, and with every build-time option you set through `config`. The `cache*` options are not build-time. Not possible together with `providers` entries of `target: providers`. |
| proxy | object | `{"headers":"","trustedAddresses":""}` | Reverse proxy headers |
| proxy.headers | string | `""` | Which proxy headers to trust (KC_PROXY_HEADERS): `xforwarded`, `forwarded` or empty for none. Set it only when every request comes through the proxy, otherwise clients can spoof their address and scheme. Empty behind a TLS-terminating load balancer (an https `hostname.url`): Keycloak logs a "Likely misconfiguration" warning and records the load balancer's address as the client. |
| proxy.trustedAddresses | string | `""` | Proxies allowed to set those headers (KC_PROXY_TRUSTED_ADDRESSES): comma-separated IPs or CIDRs, rendered only while `headers` is set. Empty: Keycloak accepts the headers from any peer. Keycloak takes the leftmost `X-Forwarded-For` element, so the proxy must overwrite the header, not append to it (an AWS ALB only appends), or the client address stays client-controlled. List the proxy's own addresses or subnets, not a range that also holds pods or nodes: every peer in it can send forged headers to the http port. |

### Security

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| emptyDirSizeLimits | object | `{"data":"256Mi","providers":"256Mi","quarkus":"64Mi","tmp":"256Mi"}` | Size limits of the emptyDirs behind the read-only root: `/tmp`, `/opt/keycloak/data` (transaction logs) and, unless `optimized`, `/opt/keycloak/lib/quarkus`. A non-optimized `start` re-augments into lib/quarkus at boot, and an empty dir there fails (`quarkus-application.dat` missing). An init container from the Keycloak image copies the image's lib/quarkus (2-5 MiB) into a second emptyDir of the `quarkus` limit, and every container start copies it from there, so a start killed half-way does not break the next one. |
| emptyDirSizeLimits.providers | string | `"256Mi"` | Each of the `providers` and `themes` emptyDirs |
| podSecurityContext | object | `{"fsGroup":1000,"fsGroupChangePolicy":"OnRootMismatch","runAsNonRoot":true,"runAsUser":1000,"seccompProfile":{"type":"RuntimeDefault"}}` | Pod security context (restricted Pod Security Standard). uid 1000 is the keycloak user of the official image. |
| securityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true,"runAsNonRoot":true}` | Security context of every container the chart renders (Keycloak, init containers, hooks) |
| serviceAccount | object | `{"annotations":{},"automountServiceAccountToken":false,"create":true,"name":""}` | ServiceAccount. Keycloak does not call the Kubernetes API with either cache stack. |
| serviceAccount.annotations | object | `{}` | Annotations, e.g. `eks.amazonaws.com/role-arn` |
| serviceAccount.automountServiceAccountToken | bool | `false` | Mount the API token into the pod |
| serviceAccount.create | bool | `true` | Create the ServiceAccount. False: use the existing one named in `name` (empty: `default`). |
| serviceAccount.name | string | `""` | Name (a lowercase DNS name). Empty uses the full name. Keep it stable when an IAM trust policy references it. |

### Secrets

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| externalSecret | object | A complex object. Please check values below | ExternalSecret (external-secrets.io/v1) whose Secret the `secretKeyRef`s with an empty name point to |
| externalSecret.data | list | `[]` | Single keys, e.g. `[{secretKey: db-password, remoteRef: {key: myapp/prod/keycloak, property: password}}]` |
| externalSecret.dataFrom | list | `[]` | Whole secrets to extract, e.g. `[{extract: {key: myapp/prod/keycloak}}]`. Set this or `data`. |
| externalSecret.enabled | bool | `false` | Render the ExternalSecret. Leave it off when the Secret already exists (e.g. synced by an ExternalSecret outside the chart) and name that Secret in the `secretKeyRef`s. |
| externalSecret.name | string | `""` | Name of the ExternalSecret and its Secret. Empty: `<fullname>-secrets`. It must differ from every ExternalSecret and Secret that already exists in the namespace: Helm does not adopt them. |
| externalSecret.refreshInterval | string | `"1m"` | How often External Secrets Operator reads the source again |
| externalSecret.secretStoreRef | object | `{"kind":"ClusterSecretStore","name":"global-secret-store"}` | Secret store: `{name, kind}`, kind `ClusterSecretStore` or `SecretStore` |
| externalSecret.template | object | `{}` | `spec.target.template` of the ExternalSecret, passed as is (not through `tpl`, so its `{{ }}` reach External Secrets Operator untouched). E.g. render a `keycloak.conf` from the fetched keys for the file mode of README "Database and secrets"; in that file every `\` must be written as `\\` and every `$` as `$$`. |
| reloader | object | `{"enabled":true,"mode":"targeted"}` | Stakater Reloader annotations on the StatefulSet. Inert without Reloader in the cluster. |
| reloader.enabled | bool | `true` | Annotate the StatefulSet for Reloader, so a changed Secret restarts the pods (one by one). Env vars are read at start only: without Reloader a rotated Secret reaches Keycloak at the next restart. |
| reloader.mode | string | `"targeted"` | `targeted`: `secret.reloader.stakater.com/reload` / `configmap.reloader.stakater.com/reload` with the Secrets and ConfigMaps of the `database` references, `extraEnv`, `extraEnvFrom` and `extraVolumes`. Not the `bootstrapAdmin` Secrets (a restart does not re-apply them) and not the TLS Secret (Keycloak reloads the files itself). `auto`: `reloader.stakater.com/auto: "true"` |

### Extras

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| extraContainers | list | `[]` | Sidecar containers |
| extraEnv | list | `[]` | Extra env vars of the Keycloak container (EnvVar list). They win over everything the chart sets: an entry replaces the chart's entry of the same name. |
| extraEnvFrom | list | `[]` | Extra envFrom sources of the Keycloak container |
| extraObjects | list | `[]` | Extra manifests, rendered with tpl |
| extraVolumeMounts | list | `[]` | Extra volume mounts of the Keycloak container |
| extraVolumes | list | `[]` | Extra pod volumes, e.g. the Secret with a `keycloak.conf` (README "Database and secrets") |
| initContainers | list | `[]` | Extra init containers, run after the provider init containers |
| podAnnotations | object | `{}` | Annotations of the pods (string values only). Do not put `karpenter.sh/do-not-disrupt: "true"` on every replica: it blocks consolidation and leaves expired nodes stuck draining; the PodDisruptionBudget already serialises drains. |
| podLabels | object | `{}` | Labels of the pods, merged with `commonLabels`; on the same key `podLabels` win. Not part of the selector. The keys the chart sets itself are rejected (see `commonLabels`). |

### Networking

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| httpRoute | object | A complex object. Please check values below | Gateway API HTTPRoute (gateway.networking.k8s.io/v1) |
| httpRoute.annotations | object | `{}` | Annotations (string values only) |
| httpRoute.enabled | bool | `false` | Render the HTTPRoute |
| httpRoute.hostnames | list | `[]` | Hostnames. Rendered with tpl. Empty takes the host of `hostname.url`. |
| httpRoute.labels | object | `{}` | Extra labels |
| httpRoute.parentRefs | list | `[]` | Gateways to attach to, e.g. `[{name: public, namespace: gateway, sectionName: https}]`. Required when enabled. |
| httpRoute.rules | list | `[{"matches":[{"path":{"type":"PathPrefix","value":"/realms/"}},{"path":{"type":"PathPrefix","value":"/resources/"}},{"path":{"type":"PathPrefix","value":"/.well-known/"}},{"path":{"type":"Exact","value":"/robots.txt"}}]}]` | HTTPRouteRules (matches, filters, backendRefs, timeouts), by default the public paths of `ingress.paths`: see there for `http.relativePath` and the master realm. The admin console needs `/admin/`: a second HTTPRoute on an internal Gateway (`extraObjects`). A rule without the `backendRefs` key goes to the chart's Service on its http port; a rule that has the key, even `backendRefs: []`, and a RequestRedirect rule are left as they are. |
| ingress | object | A complex object. Please check values below | Ingress (networking.k8s.io/v1) to the http port: the public entry point |
| ingress.admin | object | `{"annotations":{},"className":"","enabled":false,"host":"","paths":[],"tls":[]}` | A second Ingress `<fullname>-admin` with its own class, annotations and host, e.g. an internal load balancer or a source-IP allow list. Independent of `ingress.enabled`. Empty `host` takes the host of `hostname.adminUrl`, then the main Ingress host. |
| ingress.admin.annotations | object | `{}` | Annotations (string values only) |
| ingress.admin.className | string | `""` | IngressClass name, e.g. the class of an internal load balancer |
| ingress.admin.enabled | bool | `false` | Render the admin Ingress |
| ingress.admin.host | string | `""` | Host. Rendered with tpl. Empty takes the host of `hostname.adminUrl`, then the main Ingress host. |
| ingress.admin.paths | list | `[]` | Paths. Empty: `<relativePath>admin/`. On a separate admin host (with `hostname.adminUrl` pointing at it) also add `/realms/master/` and `/resources/`. Entries take `backend` like `ingress.paths`. |
| ingress.admin.tls | list | `[]` | TLS entries, as `ingress.tls` |
| ingress.annotations | object | `{}` | Annotations (string values only), e.g. the `alb.ingress.kubernetes.io/*` settings and `external-dns.alpha.kubernetes.io/hostname` |
| ingress.className | string | `""` | IngressClass name |
| ingress.enabled | bool | `false` | Render the public Ingress |
| ingress.host | string | `""` | Host. Rendered with tpl. Empty takes the host of `hostname.url`. |
| ingress.paths | list | `[{"path":"/realms/","pathType":"Prefix"},{"path":"/resources/","pathType":"Prefix"},{"path":"/.well-known/","pathType":"Prefix"},{"path":"/robots.txt","pathType":"Exact"}]` | Paths to the http port, by default the ones Keycloak's reverse-proxy guide says to expose, plus `/robots.txt`. They assume `http.relativePath: /`: prefix them yourself otherwise. The admin console needs `/admin/`, left out: serve it through `ingress.admin`. `/realms/` still includes the master realm's login and token endpoints: to keep them off the public entry point list per-realm prefixes (`/realms/<realm>/`) instead, or deny `/realms/master/` with a per-path `backend`. `path: /` is for an internal-only entry point. An entry may set `backend` (an IngressBackend), rendered as is instead of the chart's Service, e.g. an ALB `use-annotation` fixed-response action that answers 403. |
| ingress.tls | list | `[]` | TLS entries (`[{secretName, hosts}]`). Empty `hosts` take `host`, or are left out when there is no host. Leave empty when TLS ends at the load balancer. |
| networkPolicy | object | `{"databaseTo":[],"enabled":false,"extraEgress":[],"extraIngress":[],"ingressFrom":[],"metricsFrom":[]}` | NetworkPolicy, default deny, of the Keycloak pods. Always allowed: DNS to kube-system, and all traffic between this release's pods (clustering on 7800/57800, the hook and test pods). DNS egress is allowed to the `kube-system` namespace only: NodeLocal DNSCache (169.254.20.10) or a DNS namespace other than kube-system needs an `extraEgress` `ipBlock` / `namespaceSelector` rule. With `realmImport` or `tests` enabled a second policy `<fullname>-hooks` gives those pods egress to DNS and to Keycloak only; `extraEgress` does not reach it (policies add up: bring your own through `extraObjects`). |
| networkPolicy.databaseTo | list | `[]` | Egress peers of the database (`ipBlock` of the RDS subnets), on `database.port.value`, else the vendor's default port. The policy cannot read Secrets: when the port comes from a `secretKeyRef` or from `database.url`, also set `database.port.value`. |
| networkPolicy.enabled | bool | `false` | Render the NetworkPolicies. They only act when the cluster's CNI enforces NetworkPolicy. |
| networkPolicy.extraEgress | list | `[]` | Extra egress rules (NetworkPolicyEgressRule list). Every outbound call of Keycloak needs one: identity brokering and social login (443), SMTP, LDAP, NodeLocal DNSCache. |
| networkPolicy.extraIngress | list | `[]` | Extra ingress rules (NetworkPolicyIngressRule list) |
| networkPolicy.ingressFrom | list | `[]` | Peers allowed to the http(s) port: ingress controller or gateway pods, or the load balancer subnets (`ipBlock`) for ALB `target-type: ip`. Give the load balancer subnets of its own: an `ipBlock` that also holds pods or nodes opens the port to them. |
| networkPolicy.metricsFrom | list | `[]` | Peers allowed to the management port, e.g. Prometheus |
| service | object | `{"annotations":{},"httpsPort":"","labels":{},"port":"","type":"ClusterIP"}` | Service for HTTP(S). The management port is only on the headless Service. |
| service.annotations | object | `{}` | Annotations, e.g. ALB health-check settings for `target-type: ip` |
| service.httpsPort | string | `""` | Service port of https. Empty: the container port (`https.port`). |
| service.labels | object | `{}` | Extra labels. The keys the chart sets itself are rejected (see `commonLabels`). |
| service.port | string | `""` | Service port of http. Empty: the container port (`http.port`). The HTTPRoute, the realm-import hook and the test follow it; the headless Service keeps the container ports. When this chart replaces another release, keep the port the old Service had (e.g. 80): clients inside the cluster may use it. |
| service.type | string | `"ClusterIP"` | Service type. ClusterIP is enough behind an ALB with `target-type: ip` or a Gateway. |

### Image

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| image | object | `{"digest":"","pullPolicy":"IfNotPresent","repository":"quay.io/keycloak/keycloak","tag":""}` | Keycloak image, rendered as `repository:tag[@digest]` |
| image.digest | string | `""` | Image digest (`sha256:...`). With it set the digest is what runs and the tag stays readable. |
| image.pullPolicy | string | `"IfNotPresent"` | Image pull policy |
| image.repository | string | `"quay.io/keycloak/keycloak"` | Image repository. A registry mirror or a pre-built image (`optimized`) goes here. |
| image.tag | string | `""` | Keycloak version. Required: the chart never defaults it to its appVersion, so a chart upgrade alone never changes the Keycloak version. Changing it is a Keycloak upgrade: read README "Upgrading Keycloak" first. The tag must start with the Keycloak version (`26.8.2`, `26.8.2-custom`): `upgradeGuard` reads the version from it. |
| imagePullSecrets | list | `[]` | Registry credentials for private images (list of `{name: <secret>}`) |

### Providers

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| initContainerResources | object | `{"limits":{"memory":"64Mi"},"requests":{"cpu":"10m","memory":"32Mi"}}` | Resources of the init containers the chart renders (the lib/quarkus seed and the providers) |
| providers | object | `{}` | Provider JARs and themes copied from images. A map, so values layers merge per entry: a base can set `source` and an env overlay only `image` (where a Flux `$imagepolicy` marker works on the plain `image:` line). Each entry renders an init container `provider-<name>` that runs `cp -R -- <source>/. /target/`, where `/target` is an emptyDir mounted read-only in Keycloak at `/opt/keycloak/providers` (`target: providers`, the default) or `/opt/keycloak/themes` (`target: themes`). The emptyDir hides anything a custom image baked into that directory. The image needs `sh` and `cp`, and its files must be readable by uid 1000. `command` replaces the copy command and must write to `/target`. |

### Probes

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| livenessProbe | object | `{"enabled":true,"failureThreshold":5,"periodSeconds":30,"timeoutSeconds":5}` | Liveness probe on `<management path>/health/live`. Kept loose: a restart never fixes a slow database. |
| readinessProbe | object | `{"enabled":true,"failureThreshold":3,"periodSeconds":10,"timeoutSeconds":2}` | Readiness probe on `<management path>/health/ready` (HTTP, not TCP: since 26.6 the ports open before init ends) |
| startupProbe | object | `{"enabled":true,"failureThreshold":90,"initialDelaySeconds":15,"periodSeconds":10,"timeoutSeconds":2}` | Startup probe on `<management path>/health/started`. The chart sets `httpGet`; only timings live here. Since 26.6 Keycloak starts asynchronously: on 26.8.2 `/health/started` and `/health/live` have no checks and pass before the schema migration ends, so this probe does not gate a migration: the Helm (or Flux) wait timeout does, through readiness. An image older than 26.6, or `server-async-bootstrap=false`, starts synchronously: there this probe does gate the migration, so size it for that. |

### Workload

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| podManagementPolicy | string | `"Parallel"` | `Parallel` creates and deletes pods at once when scaling, `OrderedReady` one by one. Updates always go one pod at a time. Immutable on a StatefulSet. |
| replicaCount | int | `1` | Pod replicas. Ignored while `autoscaling.enabled`. With 1, every config change, Secret rotation and node drain is one boot of downtime. 0 stops Keycloak (a step of the upgrade runbook); the realm-import hook is then not rendered and `helm test` cannot pass. |
| resources | object | `{"limits":{"memory":"1536Mi"},"requests":{"cpu":"500m","memory":"1536Mi"}}` | Container resources. No CPU limit: the boot-time re-augmentation and JIT warm-up are CPU-heavy and a limit only throttles them. Memory: kc.sh sizes the heap at 70% of the limit, non-heap took 303-327 MiB on an idle pod, and the upstream baseline is 1250 MB per pod. The boot-time build JVM needs about 750 MB. `1280Mi` is the minimum with kc.sh's default heap percentages (README "Sizing"). |
| revisionHistoryLimit | int | `3` | ControllerRevisions the StatefulSet keeps (null falls back to the Kubernetes default of 10). Helm rollback does not use them. |
| terminationGracePeriodSeconds | int | `60` | Seconds between SIGTERM and SIGKILL. Keep it above `config.shutdown-delay` + shutdown-timeout (10s). |
| updateStrategy | object | `{"type":"RollingUpdate"}` | StatefulSet update strategy. `RollingUpdate` is right for config changes and, as a rule, for patch releases inside one major.minor (read the release notes: a single patch can be excluded). A minor or major upgrade migrates the schema one way and must not run next to the old version: stop every pod first (scale to 0), see README "Upgrading Keycloak". The chart refuses to render a `RollingUpdate` onto another major.minor while more than one pod runs or is wanted (`upgradeGuard`). With `OnDelete` nothing is upgraded until the pods are deleted, and `helm upgrade --wait` (or Flux) reports success at once. |
| upgradeGuard | bool | `true` | Refuse to render a `RollingUpdate` onto another Keycloak major.minor while more than one pod runs or is wanted (see `updateStrategy`). The versions are read from the image tags of the live StatefulSet and of `image.tag`, so a tag must start with the Keycloak version (`26.8.2`, `26.8.2-custom`): turn the guard off for images tagged differently. The live StatefulSet is read with `lookup`, so the guard is inert under `helm template` and Argo CD. It does not compare patch releases or the cache stack. A rollback (`helm rollback`, Flux remediation) does not render the chart and so never meets it. |

### Hooks

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| realmImport | object | A complex object. Please check values below | Post-install / post-upgrade Job that applies realm files with keycloak-config-cli (idempotent). Off by default. It logs in with `realmImport.auth` and reaches Keycloak through the chart's Service. Not rendered while Keycloak is scaled to zero (`replicaCount: 0` without autoscaling). Its pod inherits `imagePullSecrets`, `nodeSelector`, `tolerations`, the node affinity of `affinity` and `priorityClassName`, and runs under the `<fullname>-hooks` ServiceAccount. |
| realmImport.activeDeadlineSeconds | int | `900` | Deadline of the Job in seconds. The deploy tool's timeout must cover it too: a hook runs inside `helm upgrade`. |
| realmImport.auth | object | A complex object. Please check values below | Master-realm credentials of the hook, in the `value` / `secretKeyRef` shape of `database`. Required when enabled: `bootstrapAdmin` is not used, it only exists on a new database and is meant to be deleted. Either `clientId` + `clientSecret` (recommended, wins when both are set): a client with service accounts enabled, the `kc-admin-api` client scope (a new client does not get it by itself, and without it the Admin API answers 401) and the master-realm role `create-realm`. That covers the realms the client creates itself. Each realm that already exists (a migrated database, a realm created by the bootstrap account) additionally needs its `<realm>-realm` client roles (preferred) or the `admin` role. Or `username` + `password`: an admin user, password grant on `admin-cli`. The first run on a new database: README "Hooks". |
| realmImport.auth.clientId | object | `{"secretKeyRef":{},"value":""}` | Client id (KEYCLOAK_CLIENTID) |
| realmImport.auth.clientSecret | object | `{"secretKeyRef":{}}` | Client secret (KEYCLOAK_CLIENTSECRET). Secret only. Setting it selects the client-credentials grant. |
| realmImport.auth.password | object | `{"secretKeyRef":{}}` | Admin password (KEYCLOAK_PASSWORD). Secret only. |
| realmImport.auth.username | object | `{"secretKeyRef":{},"value":""}` | Admin user (KEYCLOAK_USER) |
| realmImport.backoffLimit | int | `1` | Retries of the Job |
| realmImport.deletePolicy | string | `"before-hook-creation,hook-succeeded"` | `helm.sh/hook-delete-policy`, comma separated. Empty leaves the annotation out: Helm then applies `before-hook-creation`. |
| realmImport.enabled | bool | `false` | Render the hook Job. Needs `image.tag`, `auth` and `realms` or `existingConfigMap`. |
| realmImport.existingConfigMap | string | `""` | Use an existing ConfigMap of realm files instead of `realms`. Setting both is an error. |
| realmImport.extraEnv | list | `[]` | Extra env of the hook (EnvVar list). An entry with the name of a variable the chart sets replaces it. |
| realmImport.hooks | string | `"post-install,post-upgrade"` | Hook events, comma separated |
| realmImport.image | object | `{"digest":"","pullPolicy":"IfNotPresent","repository":"docker.io/adorsys/keycloak-config-cli","tag":""}` | keycloak-config-cli image. Its tag carries the Keycloak version it was built for (e.g. `6.5.1-26.1.0`): pick the one closest to `image.tag`. Required when enabled. |
| realmImport.realms | object | `{}` | Realm files as `<file name>: <realm representation>` (real YAML, rendered to JSON in a ConfigMap). File names are ConfigMap keys: `[-._a-zA-Z0-9]+`. |
| realmImport.resources | object | `{"limits":{"memory":"512Mi"},"requests":{"cpu":"100m","memory":"256Mi"}}` | Resources of the hook container |
| realmImport.serviceAccountName | string | `""` | ServiceAccount of the hook pod. Empty: `<fullname>-hooks`, which the chart creates without annotations for the hook and test pods; its token is not mounted. Not Keycloak's own: the Job runs a third-party image, and the EKS webhook would inject Keycloak's IRSA / Pod Identity credentials into it whatever `automountServiceAccountToken` says. |
| realmImport.varSubstitution | bool | `false` | IMPORT_VARSUBSTITUTION_ENABLED. Turn it on to reference secrets from realm files with `$(env:NAME)` and pass them with `extraEnv`. Off by default: with it, whoever can edit the realm files can read the hook's env and files through `$(env:...)` and `$(file:...)`. |
| tests | object | A complex object. Please check values below | `helm test` pod: checks `/health/ready` and `/realms/master/.well-known/openid-configuration`, each up to 12 times, 5 s apart (worst case about 2 minutes per check). Its pod inherits `imagePullSecrets`, `nodeSelector`, `tolerations`, the node affinity of `affinity` and `priorityClassName`, and runs under the `<fullname>-hooks` ServiceAccount. |
| tests.enabled | bool | `true` | Render the test pod. It needs running Keycloak pods: turn the test off in the deploy tool (Flux `spec.test.enable`) while `replicaCount` is 0. |
| tests.image | object | `{"digest":"","pullPolicy":"IfNotPresent","repository":"docker.io/library/busybox","tag":"1.37"}` | Image of the test pod (needs `sh`, `wget` and `grep`) |
| tests.resources | object | `{"limits":{"memory":"32Mi"},"requests":{"cpu":"10m","memory":"16Mi"}}` | Resources of the test container |

### Monitoring

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| serviceMonitor | object | `{"enabled":false,"interval":"30s","labels":{},"metricRelabelings":[],"relabelings":[],"scrapeTimeout":"10s"}` | Prometheus Operator ServiceMonitor (monitoring.coreos.com/v1) on the management port, path `<management path>/metrics` |
| serviceMonitor.enabled | bool | `false` | Render the ServiceMonitor. Needs the Prometheus Operator CRDs. |
| serviceMonitor.interval | string | `"30s"` | Scrape interval |
| serviceMonitor.labels | object | `{}` | Labels the Prometheus `serviceMonitorSelector` matches, e.g. `release: kube-prometheus-stack` |
| serviceMonitor.metricRelabelings | list | `[]` | RelabelConfigs applied to the samples, e.g. to drop histogram buckets |
| serviceMonitor.relabelings | list | `[]` | RelabelConfigs applied before the scrape |
| serviceMonitor.scrapeTimeout | string | `"10s"` | Scrape timeout |

### Other Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| commonLabels | object | `{}` | Labels added to every resource, e.g. `app.kubernetes.io/part-of` or an `owner` label an admission policy needs. The keys the chart sets itself are rejected: `app.kubernetes.io/name`, `instance`, `component`, `version`, `managed-by` and `helm.sh/chart`. |
| fullnameOverride | string | `""` | Overrides the full resource name. Not part of any selector. |
| nameOverride | string | `""` | Overrides the chart name (`app.kubernetes.io/name`). Part of the StatefulSet selector: changing it later forces a delete and recreate of the StatefulSet. |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
