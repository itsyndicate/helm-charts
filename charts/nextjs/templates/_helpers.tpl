{{/*
Expand the name of the chart.
*/}}
{{- define "nextjs.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "nextjs.fullname" -}}
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
{{- define "nextjs.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "nextjs.labels" -}}
helm.sh/chart: {{ include "nextjs.chart" . }}
{{ include "nextjs.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "nextjs.selectorLabels" -}}
app.kubernetes.io/name: {{ include "nextjs.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "nextjs.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "nextjs.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{- define "nextjs.validateSecretsManager" -}}
{{- $sm := .Values.nextjs.env.envFromSecretsManager -}}
{{- if and $sm.secretPath $sm.secretPaths -}}
{{- fail "nextjs.env.envFromSecretsManager: set either secretPath or secretPaths, not both" -}}
{{- end -}}
{{- if and $sm.enabled (not $sm.secretPath) (not $sm.secretPaths) -}}
{{- fail "nextjs.env.envFromSecretsManager.enabled is true: set secretPath or secretPaths" -}}
{{- end -}}
{{- end }}

{{- define "nextjs.extSecretNames" -}}
{{- $fullname := include "nextjs.fullname" . -}}
{{- $sm := .Values.nextjs.env.envFromSecretsManager -}}
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
