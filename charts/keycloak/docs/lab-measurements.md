# Lab measurements

The numbers behind the recommendations in the [README](../README.md). They were taken on `quay.io/keycloak/keycloak:26.8.2` with one or two pods, without load, partly under CPU emulation. They show orders of magnitude. Native timings and memory under load were not measured: verify on dev.

## Memory

`kc.sh` sets the maximum heap to 70% of the memory limit. Measured with JVM native memory tracking:

| Memory limit | Result |
|---|---|
| `2Gi` | `examples/values-production-ha.yaml` booted |
| `1536Mi` (chart default) | Worst case 1076 MiB of heap + 303-345 MiB of non-heap = 1379-1421 MiB: fits |
| `1280Mi` | The boot-time build JVM fits. At runtime 40-80 MiB are left once the heap is full. The minimum with kc.sh's default heap percentages; `examples/values-aws-alb.yaml` booted at it without an OOM kill |
| `1Gi` | No margin |
| `768Mi` | OOM-killed at boot |

- An idle pod used 303-327 MiB of non-heap memory.
- The boot-time build JVM of a non-optimized image commits about 625-675 MB plus transients.
- Upstream's sizing guide counts 1250 MB base memory per pod, which gives a limit of about 1360 MB: (1250 - 300) / 0.7.
- Below `1280Mi`, `JAVA_OPTS_KC_HEAP` (through `extraEnv`) lowers the heap share. It replaces all three default flags: `-XX:MaxRAMPercentage=60 -XX:MinRAMPercentage=60 -XX:InitialRAMPercentage=40`.

To see whether a pod was OOM-killed (prints the restart count and the last termination reason):

```bash
kubectl -n <namespace> get pod <fullname>-0 \
  -o jsonpath='{.status.containerStatuses[0].restartCount} {.status.containerStatuses[0].lastState.terminated.reason}{"\n"}'
```

## Boot

| Start | Time to Ready (emulated) |
|---|---|
| Stock image, with the build (every container start of this chart) | 38 s |
| Stock image, without the build (a restart before the chart re-seeded `lib/quarkus`) | 12-14 s |
| Pre-built image with `optimized: true` | about 10 s |

A container killed in the middle of the build recovered on its next start.

## Shutdown

| Setting | Observed after SIGTERM |
|---|---|
| Keycloak's own default (`shutdown-delay` 1s) | Listeners closed after 1.2 s |
| Chart default, `shutdown-delay: 15s` | Readiness 503 within 0.5 s, liveness stays 200, ports 8080 and 9000 answer for 15 s, exit after about 15 s. Worst case 15 s + 10 s `shutdown-timeout` |
| `shutdown-delay: 30s` (the AWS examples) | Ports served for about 30 s, exit after 30 s |
| Two nodes signalled together, chart default | Both exited after about 16 s |
| A 26.1.4 image | `KC_SHUTDOWN_DELAY` is ignored: exit in less than 1 s |

## Database, cluster, metrics

- With the fixed pool of the production example (`db-pool-*: 30`), a pod held 30 database connections right after boot, with TLS to PostgreSQL (`?sslmode=require`).
- The two pods of `examples/values-gateway-api-eso.yaml` formed one cluster through `jdbc-ping`.
- `cache-metrics-histograms-enabled: true` added 6,279 histogram series on one idle pod.
