{{/*
Expand the name of the chart.
*/}}
{{- define "hermes.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "hermes.fullname" -}}
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
Create chart name and version as used by the chart label.
*/}}
{{- define "hermes.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "hermes.labels" -}}
helm.sh/chart: {{ include "hermes.chart" . }}
{{ include "hermes.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "hermes.selectorLabels" -}}
app.kubernetes.io/name: {{ include "hermes.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "hermes.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "hermes.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Image reference: repository@digest when a digest is set, otherwise repository:tag (tag defaults to appVersion).
*/}}
{{- define "hermes.image" -}}
{{- $img := .Values.hermes.image -}}
{{- if $img.digest -}}
{{- printf "%s@%s" $img.repository $img.digest -}}
{{- else -}}
{{- printf "%s:%s" $img.repository ($img.tag | default .Chart.AppVersion) -}}
{{- end -}}
{{- end }}

{{/*
Name of the PVC mounted as HERMES_HOME
*/}}
{{- define "hermes.pvcName" -}}
{{- .Values.persistence.existingClaim | default (printf "%s-data" (include "hermes.fullname" .)) -}}
{{- end }}

{{- define "hermes.validateSecretsManager" -}}
{{- $sm := .Values.hermes.env.envFromSecretsManager -}}
{{- if and $sm.secretPath $sm.secretPaths -}}
{{- fail "hermes.env.envFromSecretsManager: set either secretPath or secretPaths, not both" -}}
{{- end -}}
{{- if and $sm.enabled (not $sm.secretPath) (not $sm.secretPaths) -}}
{{- fail "hermes.env.envFromSecretsManager.enabled is true: set secretPath or secretPaths" -}}
{{- end -}}
{{- end }}

{{- define "hermes.extSecretNames" -}}
{{- $fullname := include "hermes.fullname" . -}}
{{- $sm := .Values.hermes.env.envFromSecretsManager -}}
{{- $names := list -}}
{{- if $sm.enabled -}}
{{- if $sm.secretPaths -}}
{{- range $i, $path := $sm.secretPaths -}}
{{- $names = append $names (printf "%s-env-ext-secrets-%d" $fullname $i) -}}
{{- end -}}
{{- else -}}
{{- $names = append $names (printf "%s-env-ext-secrets" $fullname) -}}
{{- end -}}
{{- end -}}
{{- join "," $names -}}
{{- end }}

{{/*
One Ingress for the given component. Call with (dict "ctx" $ "name" "api" "cfg" .Values.ingress.api "port" "api").
*/}}
{{- define "hermes.ingress" -}}
{{- $ctx := .ctx -}}
{{- $fullName := include "hermes.fullname" $ctx -}}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ printf "%s-%s" $fullName .name }}
  labels:
    {{- include "hermes.labels" $ctx | nindent 4 }}
  {{- with .cfg.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  {{- with .cfg.className }}
  ingressClassName: {{ . }}
  {{- end }}
  {{- if .cfg.tls }}
  tls:
    {{- range .cfg.tls }}
    - hosts:
        {{- range .hosts }}
        - {{ . | quote }}
        {{- end }}
      secretName: {{ .secretName }}
    {{- end }}
  {{- end }}
  rules:
    {{- $port := .port }}
    {{- range .cfg.hosts }}
    - host: {{ .host | quote }}
      http:
        paths:
          {{- range .paths }}
          - path: {{ .path }}
            pathType: {{ .pathType | default "Prefix" }}
            backend:
              service:
                name: {{ dig "backend" "service" "name" $fullName . }}
                port:
                  name: {{ dig "backend" "service" "port" "name" $port . }}
          {{- end }}
    {{- end }}
{{- end }}
