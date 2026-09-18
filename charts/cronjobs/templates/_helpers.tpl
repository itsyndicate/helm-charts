{{/*
Expand the name of the chart.
*/}}
{{- define "cronjobs.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "cronjobs.fullname" -}}
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
{{- define "cronjobs.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "cronjobs.labels" -}}
helm.sh/chart: {{ include "cronjobs.chart" . }}
{{ include "cronjobs.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "cronjobs.selectorLabels" -}}
app.kubernetes.io/name: {{ include "cronjobs.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "cronjobs.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "cronjobs.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{- define "cronjobs.validateSecretsManager" -}}
{{- $sm := .Values.env.envFromSecretsManager -}}
{{- if and $sm.secretPath $sm.secretPaths -}}
{{- fail "env.envFromSecretsManager: set either secretPath or secretPaths, not both" -}}
{{- end -}}
{{- if and $sm.enabled (not $sm.secretPath) (not $sm.secretPaths) -}}
{{- fail "env.envFromSecretsManager.enabled is true: set secretPath or secretPaths" -}}
{{- end -}}
{{- end }}

{{- define "cronjobs.extSecretNames" -}}
{{- $fullname := include "cronjobs.fullname" . -}}
{{- $sm := .Values.env.envFromSecretsManager -}}
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
