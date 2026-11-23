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
Keycloak image. The tag defaults to the chart appVersion.
*/}}
{{- define "keycloak.image" -}}
{{- include "keycloak.imageRef" (dict "repository" .Values.image.repository "tag" (.Values.image.tag | default .Chart.AppVersion) "digest" .Values.image.digest) }}
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

{{- define "keycloak.backendPort" -}}
{{- ternary .Values.http.port .Values.https.port .Values.http.enabled }}
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
{{- $url := tpl (.Values.hostname.url | default "") . -}}
{{- if contains "://" $url -}}
{{- regexReplaceAll ":[0-9]+$" (urlParse $url).host "" -}}
{{- else -}}
{{- $url | trimSuffix "/" -}}
{{- end -}}
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
One EnvVar from a {value, secretKeyRef} field; nothing when both are empty. secretKeyRef wins.
Call with (dict "name" "KC_DB_URL_HOST" "field" .Values.database.host "what" "database.host" "ctx" $).
*/}}
{{- define "keycloak.envVar" -}}
{{- $ref := .field.secretKeyRef | default dict -}}
{{- if $ref.key }}
- name: {{ .name }}
  valueFrom:
    secretKeyRef:
      name: {{ include "keycloak.secretRefName" (dict "ref" $ref "what" .what "ctx" .ctx) }}
      key: {{ $ref.key }}
{{- else if .field.value }}
- name: {{ .name }}
  value: {{ .field.value | toString | quote }}
{{- end }}
{{- end }}

{{/*
Options that take {value, secretKeyRef}, as (list envName field valuesPath). The bootstrap admin is left out
while its password is unset.
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
{{- if dig "secretKeyRef" "key" "" $a.password -}}
{{- $fields = concat $fields (list
  (list "KC_BOOTSTRAP_ADMIN_USERNAME" $a.username "bootstrapAdmin.username")
  (list "KC_BOOTSTRAP_ADMIN_PASSWORD" $a.password "bootstrapAdmin.password")) -}}
{{- end -}}
{{- toJson $fields -}}
{{- end }}

{{/*
Env of the Keycloak container: secret and plain {value, secretKeyRef} options, the pod name for the cache, then
extraEnv, which wins because it comes last.
*/}}
{{- define "keycloak.containerEnv" -}}
{{- range (include "keycloak.sourcedFields" . | fromJsonArray) }}
{{- include "keycloak.envVar" (dict "name" (index . 0) "field" (index . 1) "what" (index . 2) "ctx" $) }}
{{- end }}
{{- if .Values.cache.nodeNameFromPod }}
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
Stakater Reloader annotations of the StatefulSet. The chart's env ConfigMap is not listed: checksum/config covers it.
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
{{- if $ref.key }}
{{- $secrets = append $secrets (include "keycloak.secretRefName" (dict "ref" $ref "what" (index . 2) "ctx" $)) }}
{{- end }}
{{- end }}
{{- if .Values.externalSecret.enabled }}
{{- $secrets = append $secrets (include "keycloak.externalSecretName" .) }}
{{- end }}
{{- if .Values.https.enabled }}
{{- $secrets = append $secrets .Values.https.certificateSecret }}
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
  ingressClassName: {{ . }}
  {{- end }}
  {{- with .cfg.tls }}
  tls:
    {{- range . }}
    - hosts:
        {{- range (.hosts | default (list $host)) }}
        - {{ tpl . $ctx | quote }}
        {{- end }}
      {{- with .secretName }}
      secretName: {{ . }}
      {{- end }}
    {{- end }}
  {{- end }}
  rules:
    - http:
        paths:
          {{- range .paths }}
          - path: {{ .path }}
            pathType: {{ .pathType | default "Prefix" }}
            backend:
              service:
                name: {{ include "keycloak.fullname" $ctx }}
                port:
                  name: {{ include "keycloak.backendPortName" $ctx }}
          {{- end }}
      {{- with $host }}
      host: {{ . | quote }}
      {{- end }}
{{- end }}
