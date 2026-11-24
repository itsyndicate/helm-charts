# Migrating from the Bitnami Keycloak chart

How to move a release of Bitnami's `keycloak` chart (Bitnami image) to this chart (official image) on the same database.

The Bitnami side of this page was read from the public source of its chart for Keycloak 26.1.4 (chart 24.x). Your release may override any of it, so read the live release first: [Pre-flight](#pre-flight-read-the-live-release). Statements about Keycloak were measured in a lab on the 26.1.4 and 26.8.2 images. Where something was not tested it says **verify on dev**.

## What changes

- **The image.** Bitnami's image runs as uid 1001 under `/opt/bitnami/keycloak` and is configured with `KEYCLOAK_*` variables that its own scripts translate. The official image runs as uid 1000 under `/opt/keycloak` and reads `KC_*` options.
- **The Keycloak version,** if you go to a newer one. 26.1 to 26.8 is a multi-minor upgrade: a one-way schema migration, a full stop and a backup first, as in [upgrading.md](upgrading.md).
- **The cache stack,** from Bitnami's default `kubernetes` to `jdbc-ping`. That needs a full stop too.

The database stays the same.

**Rehearse first.** Run the whole procedure on a staging environment of production topology, fill in the [rehearsal checklist](#rehearsal-checklist), and repeat exactly that on production.

## One step or two

| | One step | Two steps |
|---|---|---|
| What | Bitnami 26.1.4 straight to this chart on 26.8.2 | A: this chart on the official `26.1.4` image. B: later, the upgrade to 26.8.2 with [upgrading.md](upgrading.md) |
| Windows | One | Two. Both need a full stop: the first because the cache stack changes |
| Rollback of the chart change | Database restore | Step A keeps Keycloak 26.1.4, so the schema does not change and the old release can come back on the same data |

[Cut-over](#cut-over) describes one step. Tested for it: the official 26.8.2 image started on a database last used by Bitnami 26.1.4, and logins worked.

### Two steps

Step A follows the cut-over below with these differences:

1. Values: `image.tag: "26.1.4"` and `cache.nodeNameFromPod: false` (26.1 does not know the option).
2. **Stop the old pods yourself.** The guard is inert on the same minor, although the cache stack changes.
3. There is no schema migration in this step. Take the snapshot anyway.
4. Keep the step short and behind an internal entry point. On 26.1:
   - Keycloak ignores `KC_SHUTDOWN_DELAY`: it exits less than 1 s after SIGTERM, so expect errors during restarts.
   - The startup probe does gate a schema migration (none is expected in this step).
   - By upstream's upgrading guide, Keycloak rejects non-normalised paths (`//`, `;`) by default only in releases after 26.4.2 (from upstream's documentation, not tested). A prefix rule on the load balancer that denies `/realms/master/` can be bypassed with such paths.
5. Not tested: whether the official 26.1.x image has the `/bin/sh`, `cp` and `lib/quarkus` layout that the chart's start wrapper needs. On Bitnami's 26.1.4 `kc.sh`, Keycloak started with every variable this chart renders and printed no warning. Verify on dev.

Going back from step A needs no restore, because the schema did not change: stop this chart's pods, then bring the old release back with one pod and its hooks off, verify, scale (the order of [Rollback](#rollback) without the restore and the repoint).

Step B is the [Flux runbook](upgrading.md#runbook-flux). Remove `cache.nodeNameFromPod: false` with the new tag.

## Pre-flight: read the live release

Run these against each environment. **Review the output before you attach it to a ticket:** `helm get values`, `kubectl get helmrelease -o yaml` and the listing of the container environment print every password that was set by value.

```bash
NS=<namespace>
REL=<release>          # helm -n $NS list
STS=<statefulset>      # kubectl -n $NS get statefulset

# 1. The release: its values, and what it owns (is the Ingress part of it?)
helm -n $NS get values $REL -o yaml
helm -n $NS get manifest $REL | grep -A3 '^kind:' | grep -E '^(kind|  name):'
kubectl -n <hr-namespace> get helmrelease <name> -o yaml

# 2. The StatefulSet: selector, serviceName, podManagementPolicy, replicas, volume claims, containers and images
kubectl -n $NS get statefulset $STS -o jsonpath='{.spec.selector.matchLabels}{"\n"}'
kubectl -n $NS get statefulset $STS \
  -o jsonpath='{.spec.serviceName} {.spec.podManagementPolicy} replicas={.spec.replicas} pvc={.spec.volumeClaimTemplates[*].metadata.name}{"\n"}'
kubectl -n $NS get statefulset $STS \
  -o jsonpath='{range .spec.template.spec.containers[*]}{.name} {.image}{"\n"}{end}'

# 3. The Services and their ports
kubectl -n $NS get service -l app.kubernetes.io/instance=$REL \
  -o custom-columns='NAME:.metadata.name,PORTS:.spec.ports[*].port,TARGETS:.spec.ports[*].targetPort'

# 4. The configuration: the env ConfigMap of the Bitnami chart, then the container env
#    (plain values, and for Secret references the Secret name and key)
kubectl -n $NS get configmap $STS-env-vars -o jsonpath='{.data}{"\n"}'
kubectl -n $NS get statefulset $STS \
  -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}={.value} {.valueFrom.secretKeyRef.name}/{.valueFrom.secretKeyRef.key}{"\n"}{end}'
kubectl -n $NS get statefulset $STS -o jsonpath='{.spec.template.spec.containers[0].envFrom}{"\n"}'
kubectl -n $NS get statefulset $STS -o jsonpath='{.spec.template.spec.initContainers[*].name}{"\n"}'

# 5. The Secret with the credentials: key names only, and who owns it
kubectl -n $NS describe secret <secret>
kubectl -n $NS get externalsecret \
  -o custom-columns='NAME:.metadata.name,SECRET:.spec.target.name,STORE:.spec.secretStoreRef.name'

# 6. The Ingresses: class, hosts, load balancer, annotations
kubectl -n $NS get ingress \
  -o custom-columns='NAME:.metadata.name,CLASS:.spec.ingressClassName,HOSTS:.spec.rules[*].host,LB:.status.loadBalancer.ingress[*].hostname'
kubectl -n $NS get ingress <ingress> -o jsonpath='{.metadata.annotations}{"\n"}'

# 7. The issuer the clients see today
curl -s https://<public-host>/realms/<realm>/.well-known/openid-configuration | jq -r .issuer

# 8. Providers that only the Bitnami image has
kubectl -n $NS logs $STS-0 | grep KC-SERVICES0047
```

In the database, count what the migration has to touch, and find the realms that use the metrics listener of the Bitnami image:

```sql
SELECT count(*) FROM offline_client_session;
SELECT count(*) FROM offline_user_session;
SELECT r.name FROM realm_events_listeners l JOIN realm r ON r.id = l.realm_id WHERE l.value = 'metrics-listener';
```

What each answer decides:

| You read | It decides |
|---|---|
| Image tag of the `keycloak` container (2) | Which minors the migration crosses, and so which upstream upgrading guides to read. The guard compares its `major.minor` with the new tag |
| Selector, `serviceName`, `podManagementPolicy`, volume claims (2) | Whether the StatefulSet can be replaced in place. These fields are immutable. Compare them with what this chart renders: `helm template <release> <chart> -f values.yaml -s templates/statefulset.yaml`. Bitnami adds its `podLabels` and `commonLabels` to the selector |
| Replicas (2) | With more than one pod running, the guard refuses an in-place takeover onto another minor |
| Service names and ports (3) | Clients inside the cluster use them. Bitnami's Service listens on 80 by default, this chart's on 8080: set `service.port` to the live port. The Service keeps its name only when `<fullname>` stays the same |
| `KEYCLOAK_HOSTNAME`, `KEYCLOAK_HOSTNAME_STRICT` (4) and the issuer (7) | `hostname.url`. The issuer after the cut-over must be exactly the issuer before it, or every client rejects the tokens |
| `KEYCLOAK_HTTP_RELATIVE_PATH` (4) | `http.relativePath`. It must stay the same: it is part of every URL and of the issuer |
| `KEYCLOAK_DATABASE_*` and their Secret keys (4, 5) | `database.host`, `.port`, `.database`, `.username`, `.password` |
| `KEYCLOAK_DATABASE_SCHEMA`, `KEYCLOAK_JDBC_PARAMS` (4) | `database.schema` and `database.urlProperties`. **Do not miss the schema:** see [Traps](#traps) |
| `KEYCLOAK_PROXY_HEADERS` (4) | `proxy.headers` |
| `KEYCLOAK_CACHE_STACK`, `JAVA_OPTS_APPEND` (4) | The stack in use today. It changes to `jdbc-ping`, so no old pod may run next to a new one |
| `KEYCLOAK_PRODUCTION` (4) | Nothing to map: this chart always runs `start` |
| `KC_BOOTSTRAP_ADMIN_USERNAME`, `KEYCLOAK_ADMIN_USER`, `KEYCLOAK_ADMIN`, `KEYCLOAK_ADMIN_PASSWORD` (4) | The admin created at the first install. It lives in the database and survives the move, but an admin created on 26.1.4 is flagged temporary: create a permanent one. `bootstrapAdmin` does nothing on an existing database |
| Every other variable (4) | `KC_*` goes to `config` (or `extraEnv` when it is a secret). `KEYCLOAK_*` is Bitnami's own: find the Keycloak option it stands for |
| Init containers and extra volumes (1, 4) | How the theme gets into the pod today: it becomes a `providers` entry |
| Owner of the credentials Secret (5) | Whether it survives the old release. A Secret synced by an ExternalSecret outside the Helm release does, as long as that ExternalSecret is not pruned during the cut-over |
| Whether the Ingress is in the release manifest (1, 6) | If the old release owns the Ingress, removing the release removes the load balancer |
| HelmRelease: chart, `valuesFrom`, `timeout`, install and upgrade remediation, `test` (1) | What to change for the cut-over, and what to revert to |
| `metrics-listener` in the log (8) and in the SQL result | Which realms list an event listener that the official image does not have: see [Traps](#traps) |
| Row counts | How long the migration may take. Compare with the time measured in the rehearsal |

## Mapping

"Source" means: read in the source of the Bitnami chart, or rendered from this chart. "Tested" means: run in the lab.

| Bitnami chart | This chart | Checked |
|---|---|---|
| `image` `bitnami/keycloak:26.1.4-debian-12-r0` | `image.repository: quay.io/keycloak/keycloak`, `image.tag` (required), `image.digest` | Source |
| `replicaCount`, `nodeSelector`, `tolerations`, `affinity`, `topologySpreadConstraints`, `priorityClassName`, `podAnnotations`, `podLabels`, `resources` | The same keys. `resources` defaults to 1536Mi here; Bitnami uses a preset. A memory limit below `1280Mi` carried over from the Bitnami release (for example `768Mi`) must be raised: see [Traps](#traps) | Source; the OOM: tested |
| `externalDatabase.host`, `.port`, `.database`, `.user`, `.existingSecret` with `existingSecret*Key` (`KEYCLOAK_DATABASE_*`) | `database.host`, `.port`, `.database`, `.username`, `.password`, each as `value` or `secretKeyRef` | Source |
| The JDBC URL the Bitnami image builds: `jdbc:.../NAME?currentSchema=<KEYCLOAK_DATABASE_SCHEMA>&<KEYCLOAK_JDBC_PARAMS>`, schema `public` by default | `database.schema` for the schema; `database.urlProperties` for the parameters, with a leading `?` | Tested: a missed schema gives a new, empty one |
| `auth.adminUser`, `auth.existingSecret` (`KC_BOOTSTRAP_ADMIN_*`) | Nothing. `bootstrapAdmin` is for a new database only | Source |
| `production: true` | Nothing: always `start` | Source |
| `proxyHeaders` or `proxy` (`KEYCLOAK_PROXY_HEADERS`) | `proxy.headers`, plus `proxy.trustedAddresses` | Source |
| `httpRelativePath` | `http.relativePath` | Source |
| `ingress.hostname` (`KEYCLOAK_HOSTNAME`, set only when the chart's Ingress is on) | `hostname.url`, always required here | Source; that the issuer stays the same: verify on dev |
| `adminIngress.*` (`KEYCLOAK_HOSTNAME_ADMIN`) | `ingress.admin.*` and `hostname.adminUrl` | Source |
| `ingress.*`, one path `/` | `ingress.*` with the public paths only | Source; behaviour of the load balancer: verify on dev |
| `service.ports.http: 80` | `service.port` (empty: 8080) | Source |
| `cache.stackName: kubernetes` | `cache.stack: jdbc-ping` | Source |
| `extraEnvVars`, `extraEnvVarsCM`, `extraEnvVarsSecret` | `config`, `extraEnv`, `extraEnvFrom` | Each variable: verify on dev |
| `extraStartupArgs` | `extraArgs` or `config` | Verify on dev |
| `initContainers` and `extraVolumes` that copy a theme into `/opt/bitnami/keycloak/...` | `providers.<name>` with `image`, `source` and `target` | Mechanism tested with a JAR and a folder; that uid 1000 can read your files: verify on dev |
| `keycloakConfigCli.*` | `realmImport.*` with `realmImport.auth` | Verify on dev |
| `metrics.enabled`, `metrics.serviceMonitor.*` | Metrics are always on, on port 9000. `serviceMonitor.*` is optional | Source |
| `pdb.create`, `autoscaling.*`, `networkPolicy.*` | `podDisruptionBudget`, `autoscaling`, `networkPolicy`: other keys and other defaults, write them anew | Source |
| An existing Secret with the credentials | Name it in the `secretKeyRef`s and leave `externalSecret.enabled: false` | Source |
| Reloader annotations set by hand | `reloader.enabled` (default) | Source |
| Flux HelmRelease with several `valuesFrom` layers | The same: see "Values layering" in the README | Source |

## Traps

- **The database schema.** The Bitnami image puts `currentSchema=<KEYCLOAK_DATABASE_SCHEMA>` into the JDBC URL (`public` by default). If the live release uses another schema and `database.schema` does not name it, Keycloak initialises a **new, empty schema** next to your data and starts as a fresh installation.
- **The name of the chart's ExternalSecret.** It is `<fullname>-secrets`: with a release called `keycloak`, that is `keycloak-secrets`. If an ExternalSecret or Secret of that name already exists, Helm does not adopt it. And if an existing ExternalSecret is pruned first, its Secret is garbage-collected with it. Keep the existing one and name its Secret in every `secretKeyRef`, or give the chart's another name with `externalSecret.name`.
- **The Service port.** This chart's Service listens on `http.port` (8080) unless `service.port` is set. Clients inside the cluster may use the old port.
- **`bootstrapAdmin` does nothing** on the existing database. The admin users that exist today keep working. An admin that Keycloak 26.1.4 created from the bootstrap variables is flagged temporary: create a permanent admin of the master realm.
- **The cache stack changes,** and so may the version. Both need every old pod stopped before the first new pod starts.
- **The guard refuses an in-place takeover** of a running StatefulSet with more than one pod on another minor. That is intended: stop the old pods first. On the same minor it says nothing.
- **The issuer.** Bitnami sets `KEYCLOAK_HOSTNAME` only when its own Ingress is enabled; otherwise Keycloak derives its URLs from the request. This chart always sets `hostname.url`. Compare the issuer before and after (verify on dev).
- **Clients inside the cluster** that reach Keycloak through the Service now get the public URLs in the discovery document. If they relied on internal ones, prefer pointing them at an internal host name. `hostname-backchannel-dynamic` (through `config`) is the other way, with a cost: the backchannel URLs then come from request headers, and an ALB does not manage `X-Forwarded-Host`. Verify on dev.
- **Admin API clients after the upgrade to 26.8.2.** A client that existed before has no `kc-admin-api` scope and gets 401 from the Admin API until you add it (tested: 401 before, 200 after). This includes a client used in `realmImport.auth`. `username` and `password` are not affected.
- **The realm import on existing realms.** `create-realm` lets the hook's client manage only the realms it created itself. Every realm of the migrated database was created by someone else: the client also needs the `<realm>-realm` client roles of each realm it imports (see "Hooks" in the README).
- **The `metrics-listener` event listener** comes with the Bitnami image only. Tested: a realm that still lists it keeps working after the cut-over (logins answer 200), but Keycloak logs two ERROR records per event: `KC-SERVICES0083: Event listener 'metrics-listener' registered, but provider not found`. Removing it afterwards through the Admin API works. So this is clean-up, not a precondition; do it before or after.
- **The memory limit.** A limit that served the Bitnami image is not enough for the official one: with `768Mi` it was OOM-killed at boot. `1280Mi` is the minimum with kc.sh's default heap percentages, `1536Mi` the chart default ([lab-measurements.md](lab-measurements.md#memory)). Check every values layer that sets `resources`, since an overlay replaces the chart default.
- **The HelmRelease timeouts.** `spec.upgrade.timeout` and `spec.install.timeout` win over `spec.timeout`. If the live HelmRelease sets them (for example `10m`), raising only `spec.timeout` leaves the cut-over to fail on them during the migration.
- **The theme image** was read by uid 1001 and is now read by uid 1000.
- **The load balancer.** If the old release owns the Ingress and the release is removed, the load balancer is deleted and the new one gets another DNS name. external-dns follows, but clients wait for the DNS TTL.
- **Bitnami's NetworkPolicy and PodDisruptionBudget** are on by default and are removed with the old release. This chart's NetworkPolicy is off by default.
- **The old values cannot be reused.** This chart's schema rejects unknown keys (`auth`, `externalDatabase`, ...), so a leftover Bitnami key fails the render instead of being ignored. Write the values layers anew.

## Cut-over

The Flux fields are those of the [Flux runbook](upgrading.md#runbook-flux); read it first.

1. **Write the values.** Start from one of the `examples/`. Put in what the pre-flight showed. Render them with `helm template` and compare names, selector, Service port and hosts with the live objects.

2. **Stop the old release.** Setting `replicaCount: 0` in its values is an upgrade of the *old* chart: its own post-upgrade hook (keycloak-config-cli, if enabled), its test and its remediation fire against 0 pods. So either set `spec.upgrade.disableHooks: true`, `spec.upgrade.remediation.retries: 0` and `spec.test.enable: false` on the old HelmRelease together with `replicaCount: 0` (and `autoscaling.enabled: false` if the old release uses its HPA: with it on, `replicaCount` is ignored and the pods keep running), or suspend it and scale by hand:

   ```bash
   flux suspend helmrelease <name> -n <hr-namespace>
   kubectl -n <namespace> scale statefulset <statefulset> --replicas=0
   ```

   Wait until no pod is left. Logins fail from here.

3. **Back up the database** (RDS snapshot, as in the runbook).

4. **Replace the release** with `replicaCount: 1`, a long timeout and the test off. The timeout is `spec.timeout`, unless the HelmRelease sets `spec.upgrade.timeout` (in place) or `spec.install.timeout` (reinstall): those win, so raise them. Choose one way in the rehearsal and keep to it:

   - **In place,** when the pre-flight shows the same selector, `serviceName` and `podManagementPolicy` as this chart renders, and no volume claims. Keep the release name and `<fullname>`, and point the HelmRelease at this chart, with:

     ```yaml
     spec:
       upgrade:
         disableHooks: true
         remediation:
           retries: 0
     ```

     Helm patches the objects that keep their name (StatefulSet, Services, Ingress, so the load balancer stays) and deletes the rest of the old release. The guard lets it through because the old StatefulSet has 0 replicas. Under Flux this is an upgrade only because both charts are named `keycloak`: the helm-controller compares the chart name of the stored release with the new one. None of this was run: verify on dev.

   - **Remove and install,** when anything differs or you want a clean release. Delete the old HelmRelease (Flux uninstalls the release), check with `helm -n <namespace> list` that it is gone and that the credentials Secret is still there, then add the new HelmRelease. A fresh install reads `spec.install`, not `spec.upgrade`:

     ```yaml
     spec:
       install:
         disableHooks: true
         remediation:
           retries: 0
       upgrade: # steps 7 and 8 are upgrades
         disableHooks: true
         remediation:
           retries: 0
     ```

     With install remediation on, a timed-out install makes Flux *uninstall* the release, Ingress and load balancer included, and try again. An Ingress owned by the old release goes with that release, and so does its load balancer.

   If you suspended the HelmRelease in step 2: a suspended HelmRelease does not reconcile, and Flux does not uninstall its release when it is deleted. **In place:** commit the new chart and values, run `flux reconcile kustomization <kustomization> --with-source`, then `flux resume helmrelease <name> -n <hr-namespace>`. **Remove and install:** delete the HelmRelease, then run `helm -n <namespace> uninstall <release>` yourself, and check `helm -n <namespace> list` before you add the new one.

5. **Protect the pod and wait until it is Ready.** Annotate it as in step 4 of the runbook (`karpenter.sh/do-not-disrupt=true`), and make sure no Secret rotation is due. This first start runs the schema migration. Time it.

6. **Verify** with the [rehearsal checklist](#rehearsal-checklist). Then, still with one pod: create a permanent admin of the master realm; add the `kc-admin-api` scope to your Admin API clients; give the hook's client the `<realm>-realm` roles of the existing realms; remove `metrics-listener` from the realms that list it.

7. **Scale back, hooks still off:** the normal `replicaCount` or autoscaling, the normal timeout, `disableHooks: true` and `retries: 0` unchanged.

8. **Run the realm import, still without remediation:** remove `disableHooks`. If Flux sees nothing to upgrade, force one as in step 7 of the runbook. A failed hook here leaves Keycloak running; fix the client and reconcile.

9. **Restore remediation and the test** only after one release went through cleanly with the hook.

## Rollback

Rollback is the old release on the old data, in the order of ["Rollback" in upgrading.md](upgrading.md#rollback): stop, restore the snapshot, repoint the database host, bring the old release back with one pod and its hooks off, verify, scale. For "remove and install", go back the same way: delete the new HelmRelease, wait until `helm -n <namespace> list` shows the release gone, then add the old HelmRelease with `replicaCount: 1`, `spec.install.disableHooks: true` and `spec.install.remediation.retries: 0`. Do not revert both commits at once: one commit that swaps the chart inside the same HelmRelease is an in-place upgrade, and it fails on the immutable fields that made you choose this way.

## Rehearsal checklist

Run it on staging, in this order, and write the results down. Production repeats what was proven there. Nothing in this list has been verified for you.

| # | Check | Pass when, and what to record |
|---|---|---|
| 1 | Staging has production topology | Same replica count or HPA, load balancer, NetworkPolicy, Reloader, node pool type |
| 2 | Audit the live HelmRelease | `timeout`, install and upgrade remediation, `test`, and the Flux version are written down |
| 3 | Reloader mode and the Secret rotation schedule | No rotation falls into the window |
| 4 | Pre-flight commands and SQL counts | Output reviewed for passwords, then stored |
| 5 | Render and compare the immutable fields | Decision recorded: in place, or remove and install. In place passes when `helm history` shows a new revision (not a reinstall) and the load balancer's host name is unchanged |
| 6 | The guard blocks | Deploy a new minor without the stop, with more than one pod running: the HelmRelease is not Ready and shows the guard message; the pod ages are unchanged |
| 7 | Stop | No pod left; the old release's hook and test did not fire. Record the seconds. If you freeze with `flux suspend`: reconcile the Kustomization and confirm the HelmRelease stays suspended |
| 8 | Snapshot | Minutes |
| 9 | Migration | Minutes from pod start to `1/1`, row counts. Once more against a restore of a production snapshot |
| 10 | Timeout drill | With a 2-minute timeout: no rollback, the pod keeps going, the next commit recovers the release |
| 11 | Interrupted-migration drill, on a copy | Delete the pod in mid-migration; record what the next start does |
| 12 | Functional checks | Logins; issuer unchanged (pre-flight 7, before and after); clients inside the cluster; admin console through its host; the theme shows; the path matrix below |
| 13 | Scale back with hooks off | All pods Ready; with autoscaling the HPA shows `ScalingActive` true and reaches `minReplicas`. Record the seconds |
| 14 | First run of the hook, on its own | `kubectl -n <namespace> get job` and the Job log. Record the roles the client needed |
| 15 | Hook failure drill | With a wrong client secret: the release fails, Keycloak keeps serving, the fix recovers it |
| 16 | `helm test` | `helm -n <namespace> test <release>` passes |
| 17 | Rolling restart under load | The loop below shows no 5xx during `kubectl -n <namespace> rollout restart statefulset/<fullname>`. Record seconds per pod and derive the timeouts |
| 18 | Node drain | One pod at a time, no 5xx |
| 19 | Clean shutdown with several pods | Each pod leaves the cluster and exits before the grace period ends |
| 20 | Database failover | Pods turn NotReady and come back without a restart. Record the seconds of 503 |
| 21 | Secret rotation | The pods restart one by one. Record the minutes, and the errors seen while pods still hold the old password |
| 22 | NetworkPolicy | DNS and the database work; a pod in another namespace reaches neither `<fullname>:8080` nor port 9000 (timeouts) |
| 23 | Boot without OOM, native timings | Restart count 0 and no `OOMKilled` (command in [lab-measurements.md](lab-measurements.md#memory)); seconds to Ready; peak memory under load |
| 24 | Chart-only bump | Pod ages unchanged |
| 25 | Logs and alerts | Plain-text and JSON lines are both ingested; an alert fires when a container is killed |
| 26 | Full rollback drill, in order | Total minutes |
| 27 | Plan of the production window | stop (7) + snapshot (8) + migration (9) x 1.5 + verify + scale (13), plus the rollback minutes (26) |
| 28 | Forged proxy headers | A request with its own `X-Forwarded-Host` and `X-Forwarded-For` does not change the issuer. Record which address the login event shows |
| 29 | The container | `kubectl exec` shows uid 1000, and `providers`, `themes` and the mounted config are read-only |
| 30 | The hook pod | Its environment has no `AWS_ROLE_ARN` and no `AWS_WEB_IDENTITY_TOKEN_FILE` |
| 31 | Permanent admin and the bootstrap credential | A permanent admin of the master realm exists and logs in. After that: the old bootstrap credential answers 401, and the StatefulSet has no `KC_BOOTSTRAP_ADMIN_*` |

The path matrix of check 12. Every line must print 403 or 404, never 200 or 401:

```bash
H=https://<public-host>
for p in /realms/master /realms/master/ /realms//master/ '/realms/%6daster/' '/realms/master;x=1/' \
         /realms/master/.well-known/openid-configuration /admin/ /admin/master/console/ /metrics /health/ready /; do
  printf '%s %s\n' "$(curl -s -o /dev/null --path-as-is -w '%{http_code}' "$H$p")" "$p"
done
# and one that must print 200
curl -s -o /dev/null -w '%{http_code}\n' "$H/realms/<realm>/.well-known/openid-configuration"
```

The loop of check 17: about 5 minutes of requests, then a count per status code.

```bash
for i in $(seq 1 1500); do
  curl -s -o /dev/null -w '%{http_code}\n' https://<public-host>/realms/<realm>/.well-known/openid-configuration
  sleep 0.2
done | sort | uniq -c
```
