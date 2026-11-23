# Upgrading Keycloak

How to change the Keycloak version of a release of this chart, and how to go back. The short version is in the [README](../README.md#upgrading-keycloak).

Facts on this page were measured on the `quay.io/keycloak/keycloak:26.8.2` image in a lab, partly under emulation. Where something was not tested it says **verify on dev**.

## What kind of change is it

| Change | What happens | Do |
|---|---|---|
| Chart version only | No pod restart: pod labels and checksums do not depend on the chart version | Normal deploy |
| Values, `config`, a rotated Secret; same Keycloak version | Rolling restart, one pod at a time | Normal deploy |
| Patch release in the same major.minor (26.8.x to 26.8.y) | Usually rolling-capable. `kc.sh update-compatibility check` reports patch updates as rolling-capable, but release notes can exclude one: the 26.8.2 notes say a rolling upgrade from 26.8.1 is not supported. The guard does not look at patch releases | Read the release notes. Rolling supported: normal deploy. Not supported: full stop |
| Minor or major version (26.1 to 26.8) | The first new pod migrates the database schema, one way. The chart refuses a rolling update while more than one pod runs or is wanted | Full stop |
| `cache.stack` | `kc.sh update-compatibility check` reports it as not rolling-capable: every pod must be stopped first. The guard does not look at it | Full stop |

## Before any tag change

These hold for every change of `image.tag`, a patch release included:

1. Read the upstream release notes and the upgrading guide of every version in between.
2. Take a database snapshot first.
3. Keep automatic rollback off for that deploy (Flux: `spec.upgrade.remediation.retries: 0`; Helm: no `--atomic`).

## Why a full stop

A new Keycloak node migrates the schema as soon as it starts, with the old nodes still live. Tested with a 26.1.4 node and a 26.8.2 node on one database: the schema was migrated at once, the two nodes did not form one cluster, both stayed Ready behind one Service, the old node kept answering and logged nothing, and tokens issued by the old node were rejected by the new one with 401. No probe and no Helm wait notices any of this.

## What bounds a migration

Since 26.6 Keycloak starts asynchronously. Observed on 26.8.2: `/health/started` and `/health/live` have no checks and answer 200 before the schema migration ends, and `/health/ready` answers 503 for the whole Liquibase run. So a migrating pod is `Running` and not Ready, the kubelet never restarts it, and the startup probe does not gate the migration.

- On the side of Keycloak and the kubelet, **the only bound is the wait timeout of the deploy tool.** Setting `transaction-setup-timeout` did not bound a migration in the test.
- Two things outside can still cut it short: a `statement_timeout` on the database side aborts a long changeset, and `server-async-bootstrap=false` brings the startup probe back as a gate.
- An image older than 26.6 (seen on 26.1.4) starts synchronously. There the startup probe does gate the migration: size `startupProbe.failureThreshold` x `periodSeconds` (default 90 x 10 s) for it.

How long it takes depends on the data. Upstream's 26.6 upgrading guide quotes about 22 minutes per 10 million offline client sessions for one of its migrations. Measure yours on a copy of the real data and set the timeout above it.

Upstream's upgrading guide also says that index creation is skipped on tables above 300,000 rows and that the SQL is logged for you to run by hand. Search the log of the migrating pod for it afterwards (from upstream's documentation, not tested).

## The guard

`upgradeGuard: true` (the default) makes the chart read the live StatefulSet with `lookup` and refuse to render a `RollingUpdate` onto another major.minor while more than one pod runs or is wanted. Helm prints one line:

```text
Error: UPGRADE FAILED: execution error at (keycloak/templates/statefulset.yaml:<line>): Keycloak 26.7.3 -> 26.8.2
changes the major.minor version while 3 pod(s) run and 3 are wanted: a RollingUpdate would run both versions against
one database. Stop every pod first (replicaCount: 0, autoscaling.enabled: false), then deploy 26.8.2 with
replicaCount: 1 and scale back up. See "Upgrading Keycloak" in the README. The versions are read from the image tags:
set upgradeGuard: false if your tags do not start with the Keycloak version.
```

Nothing has changed in the cluster at that point. Under Flux the message is in the HelmRelease status (`flux get helmrelease <name> -n <hr-namespace>`). Follow a runbook below.

| The guard | When |
|---|---|
| Passes | The live StatefulSet has 0 replicas; one pod is replaced by one pod (the StatefulSet deletes the old pod before it creates the new one); `updateStrategy.type: OnDelete`; `upgradeGuard: false` |
| Is inert | `lookup` returns nothing (`helm template`, Argo CD); an image tag that does not start with `major.minor` |
| Cannot see | Patch releases; a `cache.stack` change; a rollback (`helm rollback` and Flux remediation re-apply a stored manifest and do not render the chart) |

**Tag convention.** The versions are read from the image tags of the live StatefulSet and of `image.tag`. A tag must start with the Keycloak version: `26.8.2`, `26.8.2-custom`. For images tagged differently the guard sees nothing; set `upgradeGuard: false` to say so on purpose.

The guard's logic was exercised with a stand-in for the live StatefulSet, not against a cluster: verify on dev that a real `helm upgrade` (or Flux) stops with this message.

## Timeouts

A StatefulSet replaces one pod at a time, with no surge pod. The deploy tool must wait longer than:

```text
replicas x (shutdown-delay + start-to-ready + load-balancer registration) + margin
```

Take the three numbers from your own measurement on dev. Until you have them, these are **estimates**, not measurements:

| Setup | Per pod | 3 replicas | 6 replicas |
|---|---|---|---|
| Chart defaults (`shutdown-delay: 15s`), no load balancer readiness gate | 60-90 s | 3-5 min | 6-9 min |
| `shutdown-delay: 30s` and an ALB pod readiness gate | 100-120 s | 5-6 min | 10-12 min |

So 300 s is not enough for 3 replicas behind an ALB, and 10 minutes is not enough for 6.

| Deploy tool | Default wait | Set |
|---|---|---|
| Flux `HelmRelease` | `spec.timeout: 5m`; no remediation retries | `spec.timeout` from the formula, for example `15m` for 6 replicas |
| A CI job running `helm upgrade --install --wait --timeout 10m` | What the job passes | The value from the formula. By the estimates above `10m` is enough for 3 to 4 replicas behind an ALB |
| Terraform `helm_release` | `wait = true`, `timeout = 300`, `atomic = false` | `timeout`. A wrapper module that does not expose `timeout` leaves the 300 s |

When the wait runs out, Helm marks the release failed, but the StatefulSet keeps rolling. For a version upgrade the timeout must also cover the schema migration.

## Runbook: Flux

Placeholders: `<name>` and `<hr-namespace>` of the HelmRelease, `<kustomization>` that applies it, `<namespace>`, `<release>` and `<fullname>` of the Keycloak release. Every step is one commit, then:

```bash
flux reconcile kustomization <kustomization> --with-source
flux reconcile helmrelease <name> -n <hr-namespace>
```

### Before the window

1. Do the three things of [Before any tag change](#before-any-tag-change); the snapshot comes in step 3 below.
2. Rehearse this runbook on a staging environment **of production topology** and record how long step 4 takes. A single-pod environment rehearses neither the stop, nor the guard, nor the scale-back.
3. Make sure nothing changes `image.tag` by itself: no Flux `$imagepolicy` marker on the Keycloak image.
4. Make sure no Secret rotation falls into the window: Reloader would restart the migrating pod.

### In the window

1. **Stop.** Values: `replicaCount: 0` and `autoscaling.enabled: false`. HelmRelease: `spec.test.enable: false` (the test needs running pods) and `spec.upgrade.remediation.retries: 0`. Logins fail from here.

   ```yaml
   replicaCount: 0
   autoscaling:
     enabled: false
   ```

   Done when this lists no pod:

   ```bash
   kubectl -n <namespace> get pods -l app.kubernetes.io/instance=<release>,app.kubernetes.io/component=keycloak
   ```

   The realm-import hook is not rendered at 0 replicas, so it does not run here.

2. **Freeze (optional).** If someone else can merge into the repository during the window: `flux suspend helmrelease <name> -n <hr-namespace>`, and `flux resume helmrelease <name> -n <hr-namespace>` before step 4.

3. **Back up the database.** For RDS (Aurora: `create-db-cluster-snapshot` and `wait db-cluster-snapshot-available`):

   ```bash
   aws rds create-db-snapshot --db-instance-identifier <db-instance> --db-snapshot-identifier <snapshot-name>
   aws rds wait db-snapshot-available --db-snapshot-identifier <snapshot-name>
   ```

4. **Upgrade with one pod.** Values: the new `image.tag` and `image.digest`, `replicaCount: 1`.

   ```yaml
   image:
     tag: "26.8.2"
     digest: sha256:7e66a96e4739239070aeaf72e4c5decf0f7f682cfc725b9f7ea2b336eaba38b3
   replicaCount: 1
   autoscaling:
     enabled: false
   ```

   HelmRelease, from this step until step 8:

   ```yaml
   spec:
     # longer than the migration measured in the rehearsal, plus one boot
     timeout: 45m
     upgrade:
       # no realm import inside the upgrade: a failed hook would fail the release
       disableHooks: true
       # never roll back onto a migrated schema
       remediation:
         retries: 0
     test:
       enable: false
   ```

   **Protect the pod.** The single migrating pod has no protection: the PodDisruptionBudget allows evicting 1 of 1, so Karpenter consolidation, a Spot reclaim or a node drain can take it, and so can Reloader after a Secret change. As soon as the pod exists:

   ```bash
   kubectl -n <namespace> annotate pod <fullname>-0 karpenter.sh/do-not-disrupt=true
   ```

   The annotation is on the pod only and goes away with it. Prefer on-demand capacity for the window. An interrupted migration was not tested: rehearse it on a copy.

   Watch it. The pod is `Running` and `0/1` while the schema migrates:

   ```bash
   kubectl -n <namespace> get pod <fullname>-0 -w
   kubectl -n <namespace> logs <fullname>-0 -c keycloak -f
   ```

   Done when the pod is `1/1` and the HelmRelease is Ready.

   If the timeout runs out first: the HelmRelease turns `Ready=False` and nothing is rolled back. Leave the pod alone and wait until it is Ready. The commit of step 6 makes Flux upgrade again. If the HelmRelease stays failed after that, run `flux reconcile helmrelease <name> -n <hr-namespace> --force` (verify on dev).

5. **Verify** with the one pod: `helm -n <namespace> test <release>`, a login through the public URL, the admin console through its host. Coming from a version before 26.8.2, do [After an upgrade to 26.8.2](#after-an-upgrade-to-2682) now.

6. **Scale back, hooks still off.** Values: the normal `replicaCount`, or `autoscaling.enabled: true`. HelmRelease: `spec.timeout` back to its normal value; `disableHooks: true`, `retries: 0` and `test.enable: false` stay. The guard does not object: the live and the new version are now the same.

   Done when all pods are Ready and the HelmRelease is Ready.

7. **Run the realm import, still without remediation.** HelmRelease: remove `disableHooks`; `retries: 0` stays. If Flux sees nothing to upgrade, force one: `flux reconcile helmrelease <name> -n <hr-namespace> --force` (verify on dev).

   This is the hook's first run on the new version, and it can fail: a missing `kc-admin-api` scope, missing roles on existing realms, a keycloak-config-cli build that does not fit. A failed hook here leaves Keycloak running. Fix the client and reconcile again. With remediation on, Flux would instead roll back to the last revision it considers good, which may be the stopped one.

8. **Restore remediation and the test,** if you use them, only after one release went through cleanly with the hook.

9. Write down the times of steps 1 to 8. Keep the snapshot until you are sure you will not go back.

## Runbook: Helm CLI

`<chart>` is the chart reference and version that is deployed now, `values.yaml` your normal values with the new `image.tag` and `image.digest` already in it.

```bash
# 1. Stop. No -f here: the release keeps its values and its old tag; only the replicas change. Logins fail from here.
helm -n <namespace> upgrade <release> <chart> --reuse-values \
  --set replicaCount=0 --set autoscaling.enabled=false --wait --timeout 10m
kubectl -n <namespace> get pods -l app.kubernetes.io/instance=<release>,app.kubernetes.io/component=keycloak

# 2. Back up the database (RDS)
aws rds create-db-snapshot --db-instance-identifier <db-instance> --db-snapshot-identifier <snapshot-name>
aws rds wait db-snapshot-available --db-snapshot-identifier <snapshot-name>

# 3. Upgrade with one pod: no hooks, a timeout above the migration time, and never --atomic.
#    From a second terminal, as soon as the pod exists:
#    kubectl -n <namespace> annotate pod <fullname>-0 karpenter.sh/do-not-disrupt=true
helm -n <namespace> upgrade <release> <chart> -f values.yaml \
  --set replicaCount=1 --set autoscaling.enabled=false --no-hooks --wait --timeout 45m

# 4. Verify
helm -n <namespace> test <release>

# 5. Scale back with the plain values, hooks still off
helm -n <namespace> upgrade <release> <chart> -f values.yaml --no-hooks --wait --timeout 15m

# 6. Run the realm import: the same command with hooks
helm -n <namespace> upgrade <release> <chart> -f values.yaml --wait --timeout 15m
```

- Step 1 uses `--reuse-values` without `-f`, so the release keeps its old tag while `values.yaml` already holds the new one. A `-f values.yaml` next to `--reuse-values` would apply the new tag in step 1. Without `--reuse-values`, run step 1 with the old values file.
- `--no-hooks` keeps the realm import out of steps 3 and 5: a failed hook fails the release, and a failed release invites a rollback. Coming from a version before 26.8.2, do [After an upgrade to 26.8.2](#after-an-upgrade-to-2682) before step 6. A failed hook in step 6 leaves Keycloak running: fix the client and run step 6 again.
- If `--wait` times out in step 3, the release is marked failed and the pod keeps migrating. Wait until it is Ready, then run the same command again.
- Never add `--atomic` (Helm 4: `--rollback-on-failure`) to steps 3 to 6.
- The single pod of step 3 is as unprotected as in the Flux runbook: see "Protect the pod" there.

## Other deploy tools

- **A CI job** that runs one `helm upgrade --install --wait --timeout <n>` does not fit a version upgrade: it has one step and a fixed timeout. Run the Helm CLI runbook by hand, or make the replicas, `--no-hooks` and the timeout parameters of the job. Check that the job does not add `--atomic`.
- **Terraform `helm_release`:** one apply per step (stop, upgrade with one pod, scale back, hooks) with `timeout` above the migration time and `atomic = false` (the default). With the provider's 300 s the wait runs out during a longer migration; the pod goes on migrating, and the next apply finds it Ready.
- **`updateStrategy.type: OnDelete`** is not a shortcut. `helm upgrade --wait` and Flux report success immediately, and nothing is upgraded until the pods are deleted. Deleting all pods at once to upgrade was not rehearsed: verify on dev before you rely on it.

## Rollback

Rollback means the old version on the old data. Everything written since the snapshot is lost. An automatic rollback after the schema was migrated starts the old version on the new schema, so for a version change never use Flux remediation, `helm upgrade --atomic` (Helm 4: `--rollback-on-failure`) or `helm rollback`. They also bypass the guard: a rollback re-applies a stored manifest and does not render the chart.

In this order:

1. **Stop:** `replicaCount: 0`, `autoscaling.enabled: false`, hooks and test off, as in step 1 of the runbook. Do not skip this. Without it, step 3 makes Reloader restart the pods one by one, and for a while they run against two databases.
2. **Restore the snapshot.** An RDS snapshot restores into a new instance with a new endpoint.
3. **Repoint.** Put the new endpoint where the database host comes from (for example the secret behind the ExternalSecret) and wait until the Kubernetes Secret shows it.
4. **Deploy the old tag** (and the old chart version, if that changed too) with `replicaCount: 1`, hooks off, remediation off. This is a normal upgrade to the old tag, so the guard sees it; with 0 live replicas it passes.
5. **Verify:** logins work, and the data is that of the snapshot.
6. **Scale back,** then the hooks, then remediation, as in steps 6 to 8 of the runbook.

Rehearse the whole sequence once and time it: the total belongs in the plan of the production window.

## After an upgrade to 26.8.2

A client of your own that existed before the upgrade does not have the `kc-admin-api` client scope: the upgrade adds it only to `admin-cli` and `security-admin-console`. Tested on an upgraded database: a pre-existing service-account client got 401 from the Admin API, and 200 once the scope was added. An admin user through `admin-cli` kept working.

Add the scope to every such client, including the one in `realmImport.auth`, before you switch the hooks back on. A hook that logs in with `username` and `password` is not affected.
