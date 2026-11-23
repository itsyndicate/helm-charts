# keycloak

Keycloak (Quarkus) on the official image as a StatefulSet with an external database

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 26.8.2](https://img.shields.io/badge/AppVersion-26.8.2-informational?style=flat-square)

Keycloak on the official `quay.io/keycloak/keycloak` image, run with `kc.sh start` as a StatefulSet against an external database. The pods cluster through the database (`jdbc-ping`) and need no Kubernetes API access. The chart is tested with Keycloak 26.8.2 and needs Kubernetes 1.27 or newer.

Ready-made values are in [`examples/`](examples). Their Keycloak settings were booted on the real 26.8.2 image in a lab; the load balancer and Gateway parts were only rendered.

| File | Shows |
|---|---|
| `values-aws-alb.yaml` | AWS, dev/staging-sized: two pods, a public ALB that denies the master realm, the admin console on an internal ALB, an existing Secret, a theme from an image, NetworkPolicy |
| `values-production-ha.yaml` | AWS, production, HA: 3 to 6 pods with an HPA, on-demand nodes, a fixed database pool, metrics options, NetworkPolicy with internet-only egress, realm import |
| `values-gateway-api-eso.yaml` | Gateway API + chart-managed ExternalSecret: an HTTPRoute with per-realm prefixes |

Two runbooks are in [`docs/`](docs): [upgrading.md](docs/upgrading.md) and [migrating-from-bitnami.md](docs/migrating-from-bitnami.md). Facts on this page were measured in a lab, partly under emulation ([lab-measurements.md](docs/lab-measurements.md)). Where something was not tested it says **verify on dev**.

## Before you install

Three values have no default, and the chart refuses to render without them:

| Value | Why | Message |
|---|---|---|
| `image.tag` | A chart upgrade alone must never change the Keycloak version | `image.tag is required: pin the Keycloak version (e.g. "26.8.2"). ...` |
| `hostname.url` | Keycloak refuses to start without it while `hostname.strict` is true | `hostname.url is required while hostname.strict is true: ...` |
| `database.host` or `database.url` | The database is external; none is bundled | `database.host or database.url is required (value or secretKeyRef)` |

Helm prints each as `Error: execution error at (keycloak/templates/statefulset.yaml:<line>): <message>`. `helm lint` without values still passes: it lists them as `[INFO] Missing required value`.

The smallest values that render:

```yaml
image:
  tag: "26.8.2"
  digest: sha256:7e66a96e4739239070aeaf72e4c5decf0f7f682cfc725b9f7ea2b336eaba38b3
hostname:
  url: https://id.example.com/
database:
  host:
    value: keycloak.cluster-abc.eu-west-1.rds.amazonaws.com
  database:
    value: keycloak
  username:
    secretKeyRef: {name: keycloak-secrets, key: KEYCLOAK_DB_USER}
  password:
    secretKeyRef: {name: keycloak-secrets, key: KEYCLOAK_DB_PASSWORD}
```

- Give `hostname.url` as a full `https://` URL, not a bare host name. With it, plain-HTTP calls inside the cluster (the realm-import hook, `helm test`) also work from pod IPs outside RFC 1918, such as EKS pods in 100.64.0.0/10. Without it they got a 403.
- The schema is strict: an unknown key or a wrong type fails the render.
- Reloader annotations are on by default and do nothing without Reloader. The ExternalSecret, ServiceMonitor and HTTPRoute are off by default; their CRDs must exist when you turn them on.

## Image, read-only root filesystem and boot

Pin the tag and the digest. `image.digest` renders as `repository:tag@digest`, so the digest is what runs and the tag stays readable. The tag must start with the Keycloak version (`26.8.2`, `26.8.2-custom`): the [upgrade guard](#upgrading-keycloak) reads the version from it.

The containers run with `readOnlyRootFilesystem: true` under the restricted Pod Security Standard (uid 1000, no capabilities, `RuntimeDefault` seccomp). Keycloak writes to three emptyDirs: `/tmp`, `/opt/keycloak/data` (transaction logs) and `/opt/keycloak/lib/quarkus`.

The stock image is not pre-built. A non-optimized `start` first re-augments into `lib/quarkus`, in a JVM of its own. An empty directory there fails, and a start killed in that window leaves it half-written. So the init container `seed-quarkus` copies the image's `lib/quarkus` into a second emptyDir, and the Keycloak container copies it from there on every start before it runs `kc.sh`. `java` still ends up as PID 1.

A container killed in the middle of the build recovers on its next start. The price: **every container restart re-augments.** Under emulation a start took 38 s to Ready with the build and 12-14 s without it. A crash loop, for example Keycloak exiting because the database is unreachable, runs the full build on every retry.

**`optimized: true`** is for an image you built with `kc.sh build`: no build JVM at boot, no wrapper command, `lib/quarkus` read-only. Such an image booted in about 10 s under emulation; less memory at boot is expected, not measured. Every build-time option must be the same in the build and at start, or 26.8.2 refuses to start (exit code 2): `db`, `features`, `http-relative-path`, `http-management-relative-path`, `health-enabled=true`, `metrics-enabled=true`, and every build-time option you set through `config` (in the production example `features` and `event-metrics-user-enabled`). Provider JARs must be in that image: `providers` entries of `target: providers` fail the render together with `optimized`; `target: themes` works.

**Providers and themes from an image.** Each `providers` entry becomes an init container `provider-<name>` that copies `<source>/.` into an emptyDir mounted read-only at `/opt/keycloak/providers` (or `/opt/keycloak/themes` with `target: themes`). The files must be readable by uid 1000, and the image needs `sh` and `cp`. Tested with a theme JAR and a theme folder.

**JVM flags** go in `jvm.jdkJavaOptions` (`JDK_JAVA_OPTIONS`) or `jvm.javaOptsAppend` (`JAVA_OPTS_APPEND`). Never set `JAVA_OPTS`: it replaces the kc.sh defaults, including the heap `-XX:MaxRAMPercentage=70`.

## Sizing

| | Chart default | Rule |
|---|---|---|
| Memory | request = limit = `1536Mi` | Heap is 70% of the limit; the other 30% must hold the non-heap memory. `1280Mi` is the minimum, `2Gi` a production start |
| CPU | request `500m`, no limit | Take the request from measured load; a limit only throttles the boot |
| Database connections | Keycloak's own default: up to 100 per pod | `maxReplicas` x `db-pool-max-size` <= about 80% of the database's `max_connections` |
| Replicas | `1` | Two or more: one replica means downtime on every restart |

**Memory.** `kc.sh` sets the maximum heap to 70% of the memory limit. Measured on an idle 26.8.2 pod: 303-327 MiB of non-heap memory. At `1536Mi` the worst case is 1076 MiB of heap plus the non-heap memory, about 1379-1421 MiB: it fits. At `1280Mi` only 40-80 MiB are left once the heap is full: enough for a small dev pod, not for load, and the minimum with kc.sh's default heap percentages. At `1Gi` there is no margin, and a `768Mi` limit was OOM-killed at boot. Below `1280Mi`, lower the heap share with `JAVA_OPTS_KC_HEAP` through `extraEnv`; it replaces all three default flags, so set all of them, for example `-XX:MaxRAMPercentage=60 -XX:MinRAMPercentage=60 -XX:InitialRAMPercentage=40`. Memory under load was not measured: verify on dev.

**CPU.** The re-augmentation at boot and the JIT warm-up are CPU-heavy, and a limit only throttles them. The HPA scales on CPU relative to the request (`targetCPUUtilizationPercentage`) or on an absolute value (`targetCPUAverageValue`).

**Database connections.** Each pod opens up to `db-pool-max-size` connections. Upstream recommends one fixed size: initial = min = max. With `autoscaling.maxReplicas: 6` this is 180 connections, and each pod held its 30 right after boot:

```yaml
config:
  db-pool-initial-size: 30
  db-pool-min-size: 30
  db-pool-max-size: 30
```

**Replicas.** A StatefulSet replaces pods one at a time and never adds a surge pod. With one replica, every config change, Secret rotation and node drain is one boot of downtime (the PodDisruptionBudget's `maxUnavailable: 1` allows the eviction).

## Database and secrets

Each database field takes a plain `value` or a `secretKeyRef: {name, key}`; the Secret reference wins when both are set. `database.password` accepts only a Secret reference. When the chart takes over an existing database, set `database.schema` to the schema in use: with another one Keycloak initialises a new, empty schema.

### Secrets as environment variables (the default)

```yaml
database:
  host:
    secretKeyRef: {name: keycloak-secrets, key: KEYCLOAK_DB_HOST}
  database:
    value: keycloak
  username:
    secretKeyRef: {name: keycloak-secrets, key: KEYCLOAK_DB_USER}
  password:
    secretKeyRef: {name: keycloak-secrets, key: KEYCLOAK_DB_PASSWORD}
```

Name an existing Secret, as above, when something outside the chart already syncs it. A `secretKeyRef` without `name` points to the Secret of the chart's own ExternalSecret (`externalSecret.enabled`), called `<fullname>-secrets` unless `externalSecret.name` is set. That name must be free in the namespace: Helm does not adopt an ExternalSecret or Secret that already exists.

**`$` in a value.** Keycloak expands expressions in what it reads from the environment: `a$$b` arrives as `a$b`, and a value with a `${...}` it cannot resolve is dropped silently, as if no password was given. Backslashes are fine. So double every `$`, or use passwords without `$`. Upstream offers a `KCRAW_` prefix for raw values (verify on dev).

### Secrets from a file

If your policy forbids Secret data in environment variables, let Keycloak read it from a config file: mount a Secret that holds a `keycloak.conf` and point `KC_CONFIG_FILE` at it. Tested on 26.8.2: the file is readable with mode 0440 through `fsGroup`; the password appears in no log, environment or command line; an environment variable still wins over the file; the file replaces the image's default `conf/keycloak.conf` and is read only at start.

```yaml
database:
  host:
    value: keycloak.cluster-abc.eu-west-1.rds.amazonaws.com
  database:
    value: keycloak
  # no username and no password: both come from the file

externalSecret:
  enabled: true
  name: keycloak-conf
  dataFrom:
    - extract:
        key: myapp/dev/keycloak
  template:
    engineVersion: v2
    data:
      keycloak.conf: |
        db-username={{ .KEYCLOAK_DB_USER | replace "\\" "\\\\" | replace "$" "$$" }}
        db-password={{ .KEYCLOAK_DB_PASSWORD | replace "\\" "\\\\" | replace "$" "$$" }}

extraEnv:
  - name: KC_CONFIG_FILE
    value: /etc/keycloak/keycloak.conf
extraVolumes:
  - name: keycloak-conf
    secret:
      secretName: keycloak-conf
      defaultMode: 288 # 0440: readable by the keycloak user through fsGroup
extraVolumeMounts:
  - name: keycloak-conf
    mountPath: /etc/keycloak
    readOnly: true
```

- **Escaping in `keycloak.conf`** (tested): write every `\` as `\\` and every `$` as `$$`. Nothing else needs escaping: `#`, `=`, `:`, `!`, quotes and inner spaces are fine. An unescaped `\` is eaten (`a\b` becomes `ab`), a value with `${...}` makes Keycloak drop the option silently, and a password that starts or ends with whitespace cannot be used. The two `replace` calls above do the escaping in External Secrets Operator; that part was not run: verify on dev.
- `externalSecret.template` is passed to `spec.target.template` as it is. A Secret from elsewhere works the same way: leave `externalSecret` off and mount it.
- `--config-file` cannot go through `extraArgs` (a global option, it must come before `start`). The install notes say that `database.password` is not set; that is expected.
- `bootstrapAdmin` and `realmImport.auth` have no file mode: they stay `secretKeyRef` environment variables.

### Reloader

Environment variables and the config file are read at start, so a rotated Secret reaches Keycloak at the next restart. `reloader.enabled` (default `true`) annotates the StatefulSet for [Stakater Reloader](https://github.com/stakater/Reloader).

| `reloader.mode` | Restarts the pods when |
|---|---|
| `targeted` (default) | A Secret or ConfigMap of the `database` references, of `extraEnv`, `extraEnvFrom` or `extraVolumes` changes. Not the `bootstrapAdmin` Secrets (a restart does not re-apply them) and not the TLS Secret (Keycloak reloads certificate files itself) |
| `auto` | Anything Reloader finds referenced by the pod changes (`reloader.stakater.com/auto: "true"`) |

A rotation restarts the pods one at a time. Changes made through the chart need no Reloader: the pods carry `checksum/config` and, with the chart's ExternalSecret, `checksum/secret`. Neither these nor the pod labels depend on the chart version: a chart-only upgrade does not restart the pods.

### Bootstrap admin

`bootstrapAdmin` (`KC_BOOTSTRAP_ADMIN_*`) creates a temporary admin user, a temporary admin service account, or both. Keycloak applies it only when it creates the master realm, on the first start against an empty database. On an existing database it does nothing, and changing the Secret later changes nothing.

**Do not delete the temporary admin before a permanent admin of the master realm exists and works.** Tested: after the bootstrap account was deleted, nobody could administer the master realm any more (403). The chart has no way back: the container always runs `start`, and `kc.sh bootstrap-admin` needs every node stopped. Once the permanent admin works, also remove `bootstrapAdmin` from your values, or the credential stays in the pod's environment. The tested order is in [The first run on a new database](#the-first-run-on-a-new-database).

### Options: `config` and `extraEnv`

Plain Keycloak options go in `config` as `option-name: value`. They render as `KC_OPTION_NAME` into the ConfigMap `<fullname>-env`. `config` has two defaults, `shutdown-delay: 15s` and `log-console-output: json`; set a key to `null` to drop one. With `json` the runtime records are JSON, but about ten lines per start stay plain text (kc.sh and the build JVM): a log pipeline must accept both.

The chart refuses options that have a dedicated value, and everything that looks like a secret. The error names the option: `Error: execution error at (keycloak/templates/statefulset.yaml:57:28): config.<name> is not allowed: ...`

| Refused in `config` | Set it through |
|---|---|
| `db`, `db-url`, `db-url-host`, `db-url-port`, `db-url-database`, `db-url-properties`, `db-schema`, `db-username` | `database.*` |
| `hostname`, `hostname-admin`, `hostname-strict` | `hostname.*` |
| `proxy-headers`, `proxy-trusted-addresses` | `proxy.*` |
| `http-enabled`, `http-port`, `https-port`, `http-relative-path`, `http-management-*`, `https-certificate-file`, `https-certificate-key-file` | `http.*`, `https.*` |
| `cache`, `cache-stack`, `cache-embedded-node-name` | `cache.*` |
| `health-enabled`, `metrics-enabled`, `legacy-observability-interface` | Not configurable: health and metrics are always on, on the management port |
| `bootstrap-admin-*` | `bootstrapAdmin.*` |
| Any name ending in `password`, `secret` or `-pass` | `extraEnv` with a `secretKeyRef`, or the config file |

`extraEnv` wins over everything the chart sets: an entry replaces the chart's own entry of the same name, and a container variable beats the same variable from the ConfigMap.

## Values layering

Flux `valuesFrom` layers and several `-f` files merge maps key by key and replace lists whole. Everything an environment overlay usually changes is a map or a scalar. A base layer and an overlay:

```yaml
providers:
  example-theme:
    source: /usr/theme/example-theme
config:
  log-level: INFO
```

```yaml
providers:
  example-theme:
    image: 123456789012.dkr.ecr.us-east-1.amazonaws.com/keycloak-themes:42 # {"$imagepolicy": "flux-system:keycloak-themes"}
config:
  shutdown-delay: 30s
  log-console-output: null
```

The result has one provider with `image` and `source`, `KC_LOG_LEVEL=INFO`, `KC_SHUTDOWN_DELAY=30s` and no `KC_LOG_CONSOLE_OUTPUT`. A Flux `$imagepolicy` marker works on the plain `image:` line.

- **Lists are replaced whole:** `ingress.paths`, `ingress.admin.paths`, `httpRoute.rules`, `topologySpreadConstraints`, `extraEnv`, the `networkPolicy` lists. An overlay that adds one entry must repeat the others, the chart defaults included.
- **Rendered with `tpl`:** `hostname.url`, `hostname.adminUrl` (twice, so `adminUrl: "{{ .Values.hostname.url }}"` works even when `hostname.url` is a template), `ingress.host`, `ingress.admin.host`, `httpRoute.hostnames` and `extraObjects`.
- **Labels:** `commonLabels` and `podLabels` are merged on the pods, and `podLabels` win. The keys the chart sets itself are refused.
- **Flux:** a `valuesFrom` ConfigMap built by a kustomize `configMapGenerator` needs `disableNameSuffixHash: true`, because the HelmRelease refers to it by its plain name.
- **Types:** annotation and label maps take strings only, and `--set` turns `true` and numbers into other types (`podAnnotations.<key>: Invalid type. Expected: string, given: boolean`). Use `--set-string`; in Terraform's `helm_release` give the `set` block `type = "string"`, or put such values into a values file.

## Clustering

| Value | Default | Notes |
|---|---|---|
| `cache.type` | `ispn` | `local` is for a single pod only |
| `cache.stack` | `jdbc-ping` | Keycloak's default since 26.1: the pods find each other through the database. `kubernetes` (DNS_PING on the headless Service, deprecated since 26.3) also works. A custom stack goes through `extraEnv` (`KC_CACHE_STACK`) |
| `cache.nodeNameFromPod` | `true` | Sets `KC_CACHE_EMBEDDED_NODE_NAME` from the pod name. The option exists since 26.8.0: set `false` for older images |

- **Changing `cache.stack` needs every pod stopped first.** Treat it like a minor upgrade.
- With `kubernetes` the chart adds `-Djgroups.dns.query=<fullname>-headless.<namespace>.svc.cluster.local` to `JAVA_OPTS_APPEND`. `cluster.local` is fixed: a cluster with another domain needs its own `-Djgroups.dns.query=...` in `jvm.javaOptsAppend`.
- The pods talk to each other on 7800 and 57800. The chart's NetworkPolicy allows all traffic between the pods of the release.
- User sessions are in the database, and so are login failures since 26.8.0. The `authenticationSessions` and `actionTokens` caches live in memory with two owners: when several members leave at once, logins in progress can be lost. This is why the HPA removes one pod per two minutes and the PodDisruptionBudget allows one disruption at a time.

## Networking and exposure

The Service `<fullname>` carries http (and https). Its port is the container port (8080) unless `service.port` is set; the HTTPRoute, the realm-import hook and the test follow it. The headless Service `<fullname>-headless` governs the StatefulSet and adds the management port 9000 with `/health/*` and `/metrics`, which is never on the Ingress or HTTPRoute.

### What is public by default

`ingress.paths` and `httpRoute.rules` default to the paths Keycloak's reverse-proxy guide says to expose, plus `/robots.txt`. They assume `http.relativePath: /`.

| Path | In the defaults | Notes |
|---|---|---|
| `/realms/` | yes | Login pages and the OIDC and SAML endpoints of every realm, **the master realm included** |
| `/resources/`, `/.well-known/`, `/robots.txt` | yes | Static files of the login pages; metadata |
| `/admin/` | no | Admin console and Admin REST API. The guide says not to expose it: use `ingress.admin` |
| `/` | no | The guide says not to expose it. Use `path: /` only on an internal-only entry point |
| `/health/*`, `/metrics` | no | Management port only |

Brute-force detection is off by default in Keycloak: enable it in every realm (`bruteForceProtected: true` in a realm file).

### Admin console

`ingress.admin` renders a second Ingress `<fullname>-admin` with its own class, annotations and host, independent of `ingress.enabled`. For a separate internal admin host, set `hostname.adminUrl` to it and add `/realms/master/` and `/resources/` to its paths:

```yaml
hostname:
  url: https://id.example.com/
  adminUrl: https://id-admin.internal.example.com/
ingress:
  admin:
    enabled: true
    className: alb-internal
    annotations:
      alb.ingress.kubernetes.io/scheme: internal
      alb.ingress.kubernetes.io/target-type: ip
    paths:
      - path: /admin/
        pathType: Prefix
      - path: /realms/master/
        pathType: Prefix
      - path: /resources/
        pathType: Prefix
```

The host comes from `ingress.admin.host`, else from `hostname.adminUrl`, else from the main Ingress. Without `paths` it serves `/admin/` only. With Gateway API, add a second HTTPRoute on an internal Gateway through `extraObjects`.

### The master realm on a public load balancer

Keycloak's reverse-proxy guide says to keep `/realms/master/` off the public internet. The default `/realms/` prefix includes it. Two ways to close it:

**List per-realm prefixes** (`/realms/<realm>/` instead of `/realms/`). Then nothing of the master realm is routed at all; every new realm needs a new path. `examples/values-gateway-api-eso.yaml` does this.

**Or deny it.** A path entry may carry its own `backend` (an IngressBackend), rendered as it is instead of the chart's Service. With the AWS Load Balancer Controller that is a fixed-response action: the action name in the annotation is the backend's Service name, and the port name is `use-annotation`.

```yaml
ingress:
  enabled: true
  className: alb
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/actions.deny-master: >-
      {"type":"fixed-response","fixedResponseConfig":{"contentType":"text/plain","statusCode":"403","messageBody":"Forbidden"}}
  paths:
    - path: /realms/master/
      pathType: Prefix
      backend:
        service:
          name: deny-master
          port:
            name: use-annotation
    - path: /realms/
      pathType: Prefix
    - path: /resources/
      pathType: Prefix
    - path: /.well-known/
      pathType: Prefix
    - path: /robots.txt
      pathType: Exact
```

By its documentation the controller orders the listener rules Exact first, then Prefix with the longest path first, so `/realms/master/` wins over `/realms/`. Neither the fixed response nor the rule order was tested on an ALB: verify on dev, with the path matrix in the [rehearsal checklist](docs/migrating-from-bitnami.md#rehearsal-checklist). The realm-import hook and `helm test` use the Service inside the cluster and keep working; other automation against the Admin API must go through the internal admin host.

### Gateway API

`httpRoute.rules` are Gateway API `HTTPRouteRule`s, and `httpRoute.parentRefs` is required. The chart only fills in the backend: a rule **without the `backendRefs` key** goes to the chart's Service on its http port; a rule with the key, even `backendRefs: []`, and a `RequestRedirect` rule are left as they are. See `examples/values-gateway-api-eso.yaml`.

### Proxy headers

```yaml
proxy:
  headers: xforwarded
  trustedAddresses: 10.0.0.0/24,10.0.1.0/24
```

- Set `proxy.headers` only when every request comes through the proxy. Without it, and with an https `hostname.url`, kc.sh prints "Likely misconfiguration detected. When using an edge proxy, you must use `proxy-headers`" and Keycloak records the load balancer's address as the client.
- `proxy.trustedAddresses` decides **whose** headers Keycloak honours; empty means any peer. List the load balancer's own subnets, not the whole VPC CIDR: any peer in a trusted range that can reach port 8080 can send forged `X-Forwarded-*` headers. With the AWS VPC CNI, pod IPs come from the node subnets, so give the ALBs subnets of their own, without nodes or pods (`alb.ingress.kubernetes.io/subnets`), and use the same CIDRs in `networkPolicy.ingressFrom` (CNI-specific: verify on dev).
- **Behind an AWS ALB the client address stays client-controlled.** Keycloak takes the leftmost `X-Forwarded-For` element, and an ALB appends to the header instead of overwriting it. Take the real address from the ALB access logs or the WAF.

### NetworkPolicy

`networkPolicy.enabled` renders a default-deny policy for the Keycloak pods. Always allowed: DNS to the `kube-system` namespace, and all traffic between the pods of the release. Everything else is yours to open:

```yaml
networkPolicy:
  enabled: true
  ingressFrom:
    - ipBlock:
        cidr: 10.0.0.0/24 # the load balancer's own subnets (ALB target-type: ip)
  databaseTo:
    - ipBlock:
        cidr: 10.0.32.0/20 # database subnets
  extraEgress:
    # NodeLocal DNSCache
    - to:
        - ipBlock:
            cidr: 169.254.20.10/32
      ports:
        - port: 53
          protocol: UDP
        - port: 53
          protocol: TCP
```

| Value | Opens |
|---|---|
| `ingressFrom` | The http(s) port, for the ingress controller or gateway pods, or the load balancer subnets |
| `metricsFrom` | The management port, for whatever scrapes `/metrics` |
| `databaseTo` | Egress on `database.port.value`, else the vendor's default port. The policy cannot read Secrets: when the port comes from a `secretKeyRef` or from `database.url`, also set `database.port.value` |
| `extraIngress`, `extraEgress` | Anything else. Every outbound call needs an egress rule: identity brokering, SMTP, LDAP, a DNS service outside `kube-system` |

With `realmImport` or `tests` enabled, a second policy `<fullname>-hooks` gives those pods egress to DNS and to Keycloak only; `extraEgress` does not apply to it. A NetworkPolicy acts only when the cluster's CNI enforces it.

### external-dns

external-dns publishes the Ingress rule host in addition to the `external-dns.alpha.kubernetes.io/hostname` annotation, and the chart always renders a rule host. Where the public name is an alias managed elsewhere (a CDN in front of the load balancer), run external-dns with `--ignore-ingress-rules-spec` and put the name it should publish into `ingress.annotations`.

## Graceful shutdown and rollouts

**Shutdown.** On SIGTERM Keycloak fails readiness at once, keeps serving for `shutdown-delay`, then stops within `shutdown-timeout` (10s). Keycloak's own delay is 1s, too short for a load balancer that still sends requests, so the chart sets `config.shutdown-delay: 15s`. Measured: readiness answers 503 within 0.5 s of SIGTERM, liveness stays 200, ports 8080 and 9000 keep answering for the delay, and two nodes signalled together both exited after about 16 s. Behind an ALB the examples use `30s`. Keep `terminationGracePeriodSeconds` (60) above `shutdown-delay` + 10s.

**Rollouts.** A StatefulSet replaces one pod at a time; `podManagementPolicy: Parallel` only affects scaling. The deploy tool must wait longer than `replicas x (shutdown-delay + start-to-ready + load-balancer registration) + margin`. Measure the numbers on dev. By estimate, Flux's default `timeout: 5m` and Terraform's 300 s are too short for three replicas behind an ALB; the estimates and per-tool settings are in [docs/upgrading.md](docs/upgrading.md#timeouts).

**Readiness and the database.** `/health/ready` includes a database check, which exists only while metrics are enabled; this is why the chart always enables them. A database outage takes every pod out of the Service at once. That is intended; the liveness probe does not restart them.

**ALB with `target-type: ip`.** Label the namespace `elbv2.k8s.aws/pod-readiness-gate-inject: enabled`, so that a new pod counts as Ready only when its ALB target is healthy, and set `deregistration_delay.timeout_seconds` in `alb.ingress.kubernetes.io/target-group-attributes` (the ALB default is 300 s). Verify on dev that a rolling restart under load shows no 5xx.

## Upgrading Keycloak

| Change | What happens | Do |
|---|---|---|
| Chart version only | No pod restart | Normal deploy |
| Values, `config`, a rotated Secret | Rolling restart, one pod at a time | Normal deploy |
| Patch release (26.8.x to 26.8.y) | Usually rolling-capable, but release notes can exclude one (26.8.1 to 26.8.2 is excluded) | Read the release notes; snapshot first |
| Minor or major version (26.1 to 26.8) | The first new pod migrates the schema, one way. Old and new pods must not run together | Full stop: [docs/upgrading.md](docs/upgrading.md) |
| `cache.stack` | Not rolling-capable: every pod must be stopped first | Full stop |

Three rules:

1. **Pin `image.tag`.** It is required, so only you change the Keycloak version. Take a database snapshot before any tag change.
2. **A minor or major upgrade is a full stop:** scale to 0, back up, start one pod of the new version, wait until it is Ready, scale back. A new node migrates the schema as soon as it starts, and no probe notices an old node next to it.
3. **Never roll a version change back automatically.** No Flux remediation, no `helm upgrade --atomic`, no `helm rollback`: they start the old version on the migrated schema. Rollback is the database backup plus the old tag.

**The guard.** With `upgradeGuard: true` (the default) the chart reads the live StatefulSet and refuses to render a rolling update onto another `major.minor` while more than one pod runs or is wanted:

```text
Error: UPGRADE FAILED: execution error at (keycloak/templates/statefulset.yaml:<line>): Keycloak 26.7.3 -> 26.8.2
changes the major.minor version while 3 pod(s) run and 3 are wanted: a RollingUpdate would run both versions ...
```

Nothing has changed in the cluster when you see it: follow the runbook. The guard reads the versions from the image tags, is inert under `helm template` and Argo CD, and sees neither patch releases, nor a `cache.stack` change, nor a rollback.

[docs/upgrading.md](docs/upgrading.md) has the reasons, what bounds a migration, the timeouts, step-by-step runbooks for Flux and the Helm CLI, and the rollback order.

## Migrating from the Bitnami chart

[docs/migrating-from-bitnami.md](docs/migrating-from-bitnami.md) covers the move from Bitnami's `keycloak` chart to this one on the same database: the commands that read the live release, a mapping of values, the cut-over and a rehearsal checklist. The points that hurt most:

- The image, usually the Keycloak version, and the cache stack change together: it is a full stop.
- Set `database.schema` to the schema the Bitnami release used, or Keycloak initialises a new, empty one.
- `hostname.url` must give the same issuer as before; `service.port` must keep the port that clients inside the cluster use.
- Existing Admin API clients need the `kc-admin-api` scope after an upgrade to 26.8.2.

## Hooks

### Realm import

`realmImport.enabled` adds a post-install and post-upgrade Job that applies realm files with [keycloak-config-cli](https://github.com/adorsys/keycloak-config-cli), idempotently, through the chart's Service.

```yaml
realmImport:
  enabled: true
  image:
    tag: "6.5.1-26.5.5"
    digest: sha256:0955d98c8a341898b7aa177477edf8a1e90569ae50bbe7598141c1270b773274
  auth:
    clientId:
      value: realm-import
    clientSecret:
      secretKeyRef: {name: keycloak-secrets, key: KEYCLOAK_REALM_IMPORT_CLIENT_SECRET}
  realms:
    customers.json:
      realm: customers
      enabled: true
      bruteForceProtected: true
```

- **`realmImport.image.tag` is required.** The tag carries the Keycloak version the build is for. The newest build is `6.5.1-26.5.5`; it was not run against 26.8.2: verify on dev.
- **`realmImport.auth` is required;** the hook does not use `bootstrapAdmin`. Either `clientId` + `clientSecret` (recommended; it wins when both are set): a master-realm client with service accounts enabled and the scope and roles below. Or `username` + `password`: an admin user, through the password grant on `admin-cli`.
- **Realm files** come from `realmImport.realms` (real YAML, rendered to JSON in a ConfigMap) or from `realmImport.existingConfigMap`.
- **The pod** runs under the ServiceAccount `<fullname>-hooks`, which the chart creates without annotations and shares with the test pod; its token is not mounted. Never Keycloak's own account: on EKS that would hand a third-party image Keycloak's IAM role. `realmImport.serviceAccountName` overrides it. The pod inherits `nodeSelector`, `tolerations`, `priorityClassName`, `imagePullSecrets` and the node affinity of `affinity`.
- **Timing.** The hook runs inside `helm upgrade`, for at most `activeDeadlineSeconds` (900). It starts after the pods are Ready only when the deploy tool waits (`--wait`, Flux by default). Its availability check of up to 300 s logs in and calls the Admin API, so wrong credentials or a missing scope show up only after five minutes, as "Could not connect to keycloak in ... seconds". A failed hook fails the release.
- **Not rendered at `replicaCount: 0`** (without autoscaling): the hook needs a running Keycloak.
- **Rotating the client secret:** regenerate it in Keycloak first, then update the Secret. Changing only the Secret makes the next hook fail with 401.

What the hook's client may do (tested on 26.8.2 at the level of the Admin API):

| The client has | Result |
|---|---|
| No `kc-admin-api` client scope | 401. A new client does not get the scope by itself |
| `kc-admin-api` and the master-realm role `create-realm` | It can create realms and fully manage the realms **it created itself** (the creator gets that realm's `<realm>-realm` client roles). The server info answers 200 but without `systemInfo`, so without the server version, unless the client has the role `admin`; by its source, keycloak-config-cli 6.5.1 then falls back to its build version (read, not run) |
| The same, on a realm it did not create | `PUT` answers 403: every realm of a migrated database, and every realm the bootstrap account created. Grant the client that realm's `<realm>-realm` client roles in the master realm. The role `admin` works too, but prefer the per-realm roles |

### The first run on a new database

On an empty database only the temporary admin of `bootstrapAdmin` exists. Use it for one thing: to create the permanent identities. Then let the permanent client create the realms, so that it owns them. Install with `bootstrapAdmin.client` set and `realmImport.enabled: false`, then, in the Keycloak container (`kubectl exec`, `/opt/keycloak/bin`), with `--config /tmp/kcadm.config` added to every call:

```bash
kcadm.sh config credentials --server http://localhost:8080 --realm master --client <bootstrap-client-id> --secret <secret>
kcadm.sh create users -r master -s username=<admin> -s enabled=true
kcadm.sh set-password -r master --username <admin> --new-password <password>
kcadm.sh add-roles -r master --uusername <admin> --rolename admin
kcadm.sh create clients -r master -s clientId=realm-import -s publicClient=false -s serviceAccountsEnabled=true \
  -s standardFlowEnabled=false -s secret=<secret>
kcadm.sh update clients/<client-uuid>/default-client-scopes/<kc-admin-api-scope-uuid> -r master
kcadm.sh add-roles -r master --uusername service-account-realm-import --rolename create-realm
kcadm.sh config credentials --server http://localhost:8080 --realm master --user <admin> --password <password>
kcadm.sh delete clients/<bootstrap-client-uuid> -r master
```

The second `config credentials` logs in as the permanent admin before the temporary account is deleted. The two ids in the `update` line come from `kcadm.sh get clients -r master -q clientId=realm-import --fields id` and `kcadm.sh get client-scopes -r master --fields id,name`. Tested in this order: no lock-out, the permanent client then created and updated a realm, and the permanent admin still administered the master realm. Afterwards set `realmImport.enabled: true` with `realmImport.auth` pointing at the permanent client, and remove `bootstrapAdmin` from the values.

A shortcut also works at API level: point `realmImport.auth` at the id and Secret of `bootstrapAdmin.client` (the temporary account already carries `kc-admin-api`). But the realms then belong to the temporary account, and the permanent client needs their `<realm>-realm` roles afterwards.

### Secrets in realm files

`realmImport.varSubstitution: true` lets a realm file say `$(env:NAME)`; pass the variable with `realmImport.extraEnv`. It is off by default: with it, whoever can edit the realm files can read the hook's environment and files through `$(env:...)` and `$(file:...)`.

### helm test

`helm test <release>` runs a pod that checks `/health/ready` on the management port and `/realms/master/.well-known/openid-configuration` through the Service, each up to 12 times, 5 s apart: about 2 minutes per check at worst, inside `helm test`'s 5-minute default. It needs running pods, so switch it off in the deploy tool while `replicaCount` is 0 (Flux: `spec.test.enable: false`).

## Operations notes

**`kcadm.sh` in the pod.** The root filesystem is read-only, so kcadm needs its config file under `/tmp`, on every call: `--config /tmp/kcadm.config`.

**Turning autoscaling on later.** `autoscaling.enabled: true` on a running release removes `spec.replicas` from the manifest. Kubernetes documents that this drops the workload to one replica once, until the HPA acts. Do it in a quiet window.

**HPA scale-down.** The default behavior removes one pod per two minutes after a 300 s window. Do not replace it with a stateless default: several cache members leaving at once can lose logins in progress.

**Karpenter.** Do not put `karpenter.sh/do-not-disrupt: "true"` on every replica through `podAnnotations`: it blocks consolidation and leaves expired nodes (`expireAfter`) stuck draining. The PodDisruptionBudget already makes drains take one pod at a time, and `unhealthyPodEvictionPolicy: AlwaysAllow` lets a drain evict a pod that is not Ready. The one exception is the single pod of a version upgrade, annotated by hand for the window.

**Immutable fields.** The StatefulSet selects `app.kubernetes.io/name`, `instance` and `component: keycloak`. The selector, `serviceName` and `podManagementPolicy` are immutable: changing `nameOverride`, the release name or `podManagementPolicy` means deleting the StatefulSet first, or picking another `fullnameOverride`. The StatefulSet name is limited to 52 characters.

**Why a StatefulSet without volumes.** Keycloak keeps no data on disk here. The StatefulSet is there for stable pod names, which become the cache node names, and for its one-at-a-time rollout.

**Metrics.** `/metrics` is always on, on the management port; an empty `http.managementRelativePath` inherits `http.relativePath` as its path prefix. With the Prometheus Operator, `serviceMonitor.enabled` renders a ServiceMonitor; any other scraper needs the port opened in `networkPolicy.metricsFrom`. Mind the cardinality of the optional histograms: `cache-metrics-histograms-enabled: true` added 6,279 series on one idle pod.

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
