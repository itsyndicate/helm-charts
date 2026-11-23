{{/*
Expand the name of the chart.
*/}}
{{- define "keycloak.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "keycloak.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
<fullname>-<suffix>, still within 63 chars. Call with (dict "ctx" $ "suffix" "headless").
*/}}
{{- define "keycloak.childName" -}}
{{- printf "%s-%s" (include "keycloak.fullname" .ctx | trunc (int (sub 62 (len .suffix))) | trimSuffix "-") .suffix }}
{{- end }}

{{- define "keycloak.headlessName" -}}
{{- include "keycloak.childName" (dict "ctx" . "suffix" "headless") }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "keycloak.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Labels shared by every resource of the release. Selects all its pods, including the hook and test pods.
*/}}
{{- define "keycloak.selectorLabels" -}}
app.kubernetes.io/name: {{ include "keycloak.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Selector of the Keycloak pods. Immutable on the StatefulSet: changing it means deleting the StatefulSet.
*/}}
{{- define "keycloak.podSelectorLabels" -}}
{{ include "keycloak.selectorLabels" . }}
app.kubernetes.io/component: keycloak
{{- end }}

{{/*
Common labels
*/}}
{{- define "keycloak.labels" -}}
helm.sh/chart: {{ include "keycloak.chart" . }}
{{ include "keycloak.selectorLabels" . }}
app.kubernetes.io/version: {{ .Values.image.tag | default .Chart.AppVersion | replace "+" "_" | trunc 63 | trimSuffix "-" | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Labels of the Keycloak pod template. No helm.sh/chart and no managed-by: a chart upgrade alone must not roll the pods.
*/}}
{{- define "keycloak.podLabels" -}}
{{ include "keycloak.podSelectorLabels" . }}
app.kubernetes.io/version: {{ .Values.image.tag | default .Chart.AppVersion | replace "+" "_" | trunc 63 | trimSuffix "-" | quote }}
{{- /* One map, podLabels winning: a key set in both must not render twice */}}
{{- with merge (dict) .Values.podLabels .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Name of the service account to use
*/}}
{{- define "keycloak.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "keycloak.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Image reference repository[:tag][@digest] from a dict with repository, tag and digest.
*/}}
{{- define "keycloak.imageRef" -}}
{{- $ref := .repository -}}
{{- with .tag }}{{ $ref = printf "%s:%s" $ref (toString .) }}{{ end -}}
{{- with .digest }}{{ $ref = printf "%s@%s" $ref . }}{{ end -}}
{{- $ref -}}
{{- end }}

{{/*
Keycloak image. The tag is required and never falls back to the chart appVersion.
*/}}
{{- define "keycloak.image" -}}
{{- $tag := required "image.tag is required: pin the Keycloak version (e.g. \"26.8.2\"). The chart no longer defaults it to appVersion, so a chart upgrade never changes the Keycloak version. See \"Upgrading Keycloak\" in the README." .Values.image.tag -}}
{{- include "keycloak.imageRef" (dict "repository" .Values.image.repository "tag" $tag "digest" .Values.image.digest) }}
{{- end }}

{{/*
HTTP and management relative paths without the trailing slash: "" for "/".
The management path inherits the HTTP one, as Keycloak does.
*/}}
{{- define "keycloak.httpPath" -}}
{{- .Values.http.relativePath | default "/" | trimSuffix "/" }}
{{- end }}

{{- define "keycloak.managementPath" -}}
{{- .Values.http.managementRelativePath | default .Values.http.relativePath | default "/" | trimSuffix "/" }}
{{- end }}

{{/*
The management interface inherits TLS from the main server.
*/}}
{{- define "keycloak.managementScheme" -}}
{{- ternary "HTTPS" "HTTP" .Values.https.enabled }}
{{- end }}

{{/*
Port the Ingress, HTTPRoute, hook and test use: http when enabled, otherwise https.
*/}}
{{- define "keycloak.backendPortName" -}}
{{- ternary "http" "https" .Values.http.enabled }}
{{- end }}

{{/*
Its number on the Service: service.port / service.httpsPort, by default the container port.
*/}}
{{- define "keycloak.backendPort" -}}
{{- ternary (.Values.service.port | default .Values.http.port) (.Values.service.httpsPort | default .Values.https.port) .Values.http.enabled }}
{{- end }}

{{/*
In-cluster base URL of Keycloak, with the relative path.
*/}}
{{- define "keycloak.serviceUrl" -}}
{{- printf "%s://%s:%v%s" (include "keycloak.backendPortName" .) (include "keycloak.fullname" .) (include "keycloak.backendPort" .) (include "keycloak.httpPath" .) }}
{{- end }}

{{/*
Host of hostname.url (a URL or a bare hostname), without port. Empty when hostname.url is empty.
*/}}
{{- define "keycloak.publicHost" -}}
{{- include "keycloak.urlHost" (tpl (.Values.hostname.url | default "") .) -}}
{{- end }}

{{- define "keycloak.externalSecretName" -}}
{{- .Values.externalSecret.name | default (include "keycloak.childName" (dict "ctx" . "suffix" "secrets")) }}
{{- end }}

{{/*
Secret name of a {name, key} reference: an empty name means the chart's ExternalSecret.
Call with (dict "ref" $ref "what" "database.password" "ctx" $).
*/}}
{{- define "keycloak.secretRefName" -}}
{{- if .ref.name -}}
{{- .ref.name -}}
{{- else if .ctx.Values.externalSecret.enabled -}}
{{- include "keycloak.externalSecretName" .ctx -}}
{{- else -}}
{{- fail (printf "%s.secretKeyRef.name is empty and externalSecret is disabled" .what) -}}
{{- end -}}
{{- end }}

{{/*
String form of a scalar. Numbers from a values file are float64, and toString renders 2592000 as 2.592e+06.
*/}}
{{- define "keycloak.toString" -}}
{{- if kindIs "float64" . }}{{ toJson . }}{{ else }}{{ toString . }}{{ end -}}
{{- end }}

{{/*
One EnvVar from a {value, secretKeyRef} field; nothing when both are empty. secretKeyRef wins.
Call with (dict "name" "KC_DB_URL_HOST" "field" .Values.database.host "what" "database.host" "ctx" $).
*/}}
{{- define "keycloak.envVar" -}}
{{- $ref := .field.secretKeyRef | default dict -}}
{{- if and $ref.name (not $ref.key) -}}
{{- fail (printf "%s.secretKeyRef.name is %q but key is empty: set the key of the Secret to read" .what $ref.name) -}}
{{- end -}}
{{- if $ref.key }}
- name: {{ .name }}
  valueFrom:
    secretKeyRef:
      name: {{ include "keycloak.secretRefName" (dict "ref" $ref "what" .what "ctx" .ctx) | quote }}
      key: {{ $ref.key | quote }}
{{- else if .field.value }}
- name: {{ .name }}
  value: {{ include "keycloak.toString" .field.value | quote }}
{{- end }}
{{- end }}

{{/*
Options that take {value, secretKeyRef}, as (list envName field valuesPath). The bootstrap admin user and service
account are each left out while their secret is unset, and so is every option extraEnv sets itself.
*/}}
{{- define "keycloak.sourcedFields" -}}
{{- $d := .Values.database -}}
{{- $a := .Values.bootstrapAdmin -}}
{{- $fields := list
  (list "KC_DB_URL_HOST" $d.host "database.host")
  (list "KC_DB_URL_PORT" $d.port "database.port")
  (list "KC_DB_URL_DATABASE" $d.database "database.database")
  (list "KC_DB_SCHEMA" $d.schema "database.schema")
  (list "KC_DB_USERNAME" $d.username "database.username")
  (list "KC_DB_PASSWORD" $d.password "database.password")
  (list "KC_DB_URL" $d.url "database.url") -}}
{{- if or (dig "secretKeyRef" "key" "" $a.password) (dig "secretKeyRef" "name" "" $a.password) -}}
{{- $fields = concat $fields (list
  (list "KC_BOOTSTRAP_ADMIN_USERNAME" $a.username "bootstrapAdmin.username")
  (list "KC_BOOTSTRAP_ADMIN_PASSWORD" $a.password "bootstrapAdmin.password")) -}}
{{- end -}}
{{- if or (dig "secretKeyRef" "key" "" $a.client.secret) (dig "secretKeyRef" "name" "" $a.client.secret) -}}
{{- $fields = concat $fields (list
  (list "KC_BOOTSTRAP_ADMIN_CLIENT_ID" $a.client.id "bootstrapAdmin.client.id")
  (list "KC_BOOTSTRAP_ADMIN_CLIENT_SECRET" $a.client.secret "bootstrapAdmin.client.secret")) -}}
{{- end -}}
{{- $extra := list -}}
{{- range .Values.extraEnv }}{{ $extra = append $extra .name }}{{ end -}}
{{- $kept := list -}}
{{- range $fields }}{{ if not (has (index . 0) $extra) }}{{ $kept = append $kept . }}{{ end }}{{ end -}}
{{- toJson $kept -}}
{{- end }}

{{/*
Env of the Keycloak container: secret and plain {value, secretKeyRef} options, the pod name for the cache, then
extraEnv. extraEnv wins by replacing the chart's entry of the same name: a name listed twice is rejected by
server-side apply.
*/}}
{{- define "keycloak.containerEnv" -}}
{{- range (include "keycloak.sourcedFields" . | fromJsonArray) }}
{{- include "keycloak.envVar" (dict "name" (index . 0) "field" (index . 1) "what" (index . 2) "ctx" $) }}
{{- end }}
{{- $extra := list }}
{{- range .Values.extraEnv }}{{ $extra = append $extra .name }}{{ end }}
{{- /* The option is only available with the clustered cache */}}
{{- if and .Values.cache.nodeNameFromPod (eq .Values.cache.type "ispn") (not (has "KC_CACHE_EMBEDDED_NODE_NAME" $extra)) }}
- name: KC_CACHE_EMBEDDED_NODE_NAME
  valueFrom:
    fieldRef:
      fieldPath: metadata.name
{{- end }}
{{- with .Values.extraEnv }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Refuses a pod-by-pod roll onto another Keycloak major.minor: old and new nodes would run against one database while
the new one migrates the schema. Inert without a live StatefulSet (helm template, Argo CD), for a tag without
major.minor, for a single pod replaced by a single pod, for OnDelete and with upgradeGuard: false.
Call with (dict "live" <live StatefulSet or empty map> "ctx" $).
*/}}
{{- define "keycloak.upgradeGuard" -}}
{{- $v := .ctx.Values -}}
{{- $newTag := $v.image.tag | default "" -}}
{{- $liveImage := "" -}}
{{- range (dig "spec" "template" "spec" "containers" (list) .live) -}}
{{- if eq .name "keycloak" }}{{ $liveImage = .image }}{{ end -}}
{{- end -}}
{{- $liveTag := regexReplaceAll "@.*$" ($liveImage | splitList "/" | last) "" | splitList ":" | rest | first | default "" -}}
{{- $liveMM := regexFind "^[0-9]+\\.[0-9]+" $liveTag -}}
{{- $newMM := regexFind "^[0-9]+\\.[0-9]+" $newTag -}}
{{- $liveReplicas := dig "spec" "replicas" 0 .live | int -}}
{{- /* With autoscaling on the StatefulSet has no replicas field: at least one pod, minReplicas once the HPA acts */}}
{{- $wanted := ternary (max 1 $v.autoscaling.minReplicas) $v.replicaCount $v.autoscaling.enabled | int -}}
{{- $rolling := eq (dig "type" "RollingUpdate" ($v.updateStrategy | default dict)) "RollingUpdate" -}}
{{- if and $v.upgradeGuard $liveMM $newMM (ne $liveMM $newMM) $rolling (gt $liveReplicas 0) (gt $wanted 0) (gt (max $liveReplicas $wanted) 1) -}}
{{- fail (printf "Keycloak %s -> %s changes the major.minor version while %d pod(s) run and %d are wanted: a RollingUpdate would run both versions against one database. Stop every pod first (replicaCount: 0, autoscaling.enabled: false), then deploy %s with replicaCount: 1 and scale back up. See \"Upgrading Keycloak\" in the README. The versions are read from the image tags: set upgradeGuard: false if your tags do not start with the Keycloak version." $liveTag $newTag $liveReplicas $wanted $newTag) -}}
{{- end -}}
{{- end }}

{{/*
Stakater Reloader annotations of the StatefulSet. The chart's env ConfigMap is not listed: checksum/config covers it.
Targeted mode lists what a restart picks up: the Secrets and ConfigMaps of the rendered database options, extraEnv,
extraEnvFrom and extraVolumes (e.g. a mounted keycloak.conf). Not the bootstrap admin Secrets (read only when the
master realm is created) and not the TLS Secret (Keycloak reloads certificates itself, hourly by default).
*/}}
{{- define "keycloak.reloaderAnnotations" -}}
{{- if .Values.reloader.enabled }}
{{- if eq .Values.reloader.mode "auto" }}
reloader.stakater.com/auto: "true"
{{- else }}
{{- $secrets := list }}
{{- $configMaps := list }}
{{- range (include "keycloak.sourcedFields" . | fromJsonArray) }}
{{- $ref := (index . 1).secretKeyRef | default dict }}
{{- if and $ref.key (not (hasPrefix "KC_BOOTSTRAP_ADMIN_" (index . 0))) }}
{{- $secrets = append $secrets (include "keycloak.secretRefName" (dict "ref" $ref "what" (index . 2) "ctx" $)) }}
{{- end }}
{{- end }}
{{- range .Values.extraEnvFrom }}
{{- with .secretRef }}{{ $secrets = append $secrets .name }}{{ end }}
{{- with .configMapRef }}{{ $configMaps = append $configMaps .name }}{{ end }}
{{- end }}
{{- range .Values.extraEnv }}
{{- with .valueFrom }}
{{- with .secretKeyRef }}{{ $secrets = append $secrets .name }}{{ end }}
{{- with .configMapKeyRef }}{{ $configMaps = append $configMaps .name }}{{ end }}
{{- end }}
{{- end }}
{{- range .Values.extraVolumes }}
{{- with .secret }}{{ $secrets = append $secrets .secretName }}{{ end }}
{{- with .configMap }}{{ $configMaps = append $configMaps .name }}{{ end }}
{{- end }}
{{- with $secrets | uniq | sortAlpha }}
secret.reloader.stakater.com/reload: {{ join "," . | quote }}
{{- end }}
{{- with $configMaps | uniq | sortAlpha }}
configmap.reloader.stakater.com/reload: {{ join "," . | quote }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}

{{/*
One Ingress. Call with (dict "ctx" $ "name" <name> "cfg" <ingress values> "paths" <paths> "host" <host>).
*/}}
{{- define "keycloak.ingress" -}}
{{- $ctx := .ctx -}}
{{- $host := .host -}}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ .name }}
  labels:
    {{- include "keycloak.labels" $ctx | nindent 4 }}
  {{- with .cfg.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  {{- with .cfg.className }}
  ingressClassName: {{ . | quote }}
  {{- end }}
  {{- with .cfg.tls }}
  tls:
    {{- range . }}
    {{- $hosts := .hosts | default (compact (list $host)) }}
    {{- if $hosts }}
    - hosts:
        {{- range $hosts }}
        - {{ tpl . $ctx | quote }}
        {{- end }}
      {{- with .secretName }}
      secretName: {{ . | quote }}
      {{- end }}
    {{- else }}
    {{- /* No host anywhere: leave hosts out rather than render [""] */}}
    - {{ pick . "secretName" | toJson }}
    {{- end }}
    {{- end }}
  {{- end }}
  rules:
    - http:
        paths:
          {{- range .paths }}
          - path: {{ .path | quote }}
            pathType: {{ .pathType | default "Prefix" }}
            backend:
              {{- if .backend }}
              {{- toYaml .backend | nindent 14 }}
              {{- else }}
              service:
                name: {{ include "keycloak.fullname" $ctx }}
                port:
                  name: {{ include "keycloak.backendPortName" $ctx }}
              {{- end }}
          {{- end }}
      {{- with $host }}
      host: {{ . | quote }}
      {{- end }}
{{- end }}

{{/*
Host of a URL or a bare hostname, without port. Call with the string; empty in, empty out.
*/}}
{{- define "keycloak.urlHost" -}}
{{- if contains "://" . -}}
{{- regexReplaceAll ":[0-9]+$" (urlParse .).host "" -}}
{{- else -}}
{{- . | trimSuffix "/" -}}
{{- end -}}
{{- end }}

{{/*
NetworkPolicy egress rule for DNS, shared by both policies.
*/}}
{{- define "keycloak.dnsEgress" -}}
- to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
  ports:
    - port: 53
      protocol: UDP
    - port: 53
      protocol: TCP
{{- end }}
