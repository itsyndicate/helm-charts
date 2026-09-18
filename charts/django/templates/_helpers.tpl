{{/*
Expand the name of the chart.
*/}}
{{- define "django.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "django.fullname" -}}
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
{{- define "django.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "django.labels" -}}
helm.sh/chart: {{ include "django.chart" . }}
{{ include "django.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "django.selectorLabels" -}}
app.kubernetes.io/name: {{ include "django.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "django.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "django.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{- define "django.validateSecretsManager" -}}
{{- $sm := .Values.django.env.envFromSecretsManager -}}
{{- if and $sm.secretPath $sm.secretPaths -}}
{{- fail "django.env.envFromSecretsManager: set either secretPath or secretPaths, not both" -}}
{{- end -}}
{{- if and $sm.enabled (not $sm.secretPath) (not $sm.secretPaths) -}}
{{- fail "django.env.envFromSecretsManager.enabled is true: set secretPath or secretPaths" -}}
{{- end -}}
{{- end }}

{{- define "django.extSecretNames" -}}
{{- $fullname := include "django.fullname" . -}}
{{- $sm := .Values.django.env.envFromSecretsManager -}}
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

{{- define "django.migrationExtSecretNames" -}}
{{- $fullname := include "django.fullname" . -}}
{{- $sm := .Values.django.env.envFromSecretsManager -}}
{{- $names := list -}}
{{- if $sm.enabled -}}
{{- if $sm.secretPaths -}}
{{- range $i, $path := $sm.secretPaths -}}
{{- $names = append $names (printf "%s-env-migration-ext-secrets-%d" $fullname $i) -}}
{{- end -}}
{{- else -}}
{{- $names = append $names (printf "%s-env-migration-ext-secrets" $fullname) -}}
{{- end -}}
{{- end -}}
{{- join "," $names -}}
{{- end }}
