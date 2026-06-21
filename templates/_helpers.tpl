{{/*
Expand the name of the chart.
*/}}
{{- define "data-platform.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "data-platform.fullname" -}}
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
{{- define "data-platform.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "data-platform.labels" -}}
helm.sh/chart: {{ include "data-platform.chart" . }}
{{ include "data-platform.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "data-platform.selectorLabels" -}}
app.kubernetes.io/name: {{ include "data-platform.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Default Security Context – gibt die globalen Security-Defaults zurück
*/}}
{{- define "data-platform.securityContext" -}}
allowPrivilegeEscalation: false
readOnlyRootFilesystem: true
runAsNonRoot: true
capabilities:
  drop: [ALL]
seccompProfile:
  type: RuntimeDefault
{{- end }}

{{/*
Default Pod Security Context – gibt die globalen Pod-Security-Defaults zurück
*/}}
{{- define "data-platform.podSecurityContext" -}}
runAsNonRoot: true
fsGroupChangePolicy: OnRootMismatch
{{- end }}

{{/*
Validates that resources (requests & limits) are properly set.
Usage: {{ include "data-platform.resources" .Values.someComponent.resources }}
Returns error message if requests or limits are missing.
*/}}
{{- define "data-platform.resources" -}}
{{- if not .requests }}
{{- fail "ERROR: resources.requests must be set (cpu, memory)" }}
{{- end }}
{{- if not .requests.cpu }}
{{- fail "ERROR: resources.requests.cpu must be set" }}
{{- end }}
{{- if not .requests.memory }}
{{- fail "ERROR: resources.requests.memory must be set" }}
{{- end }}
{{- if not .limits }}
{{- fail "ERROR: resources.limits must be set (cpu, memory)" }}
{{- end }}
{{- if not .limits.cpu }}
{{- fail "ERROR: resources.limits.cpu must be set" }}
{{- end }}
{{- if not .limits.memory }}
{{- fail "ERROR: resources.limits.memory must be set" }}
{{- end }}
{{- end }}
