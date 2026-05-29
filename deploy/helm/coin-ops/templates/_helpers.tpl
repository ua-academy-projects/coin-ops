{{/*
Expand the name of the chart.
*/}}
{{- define "coin-ops.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "coin-ops.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "coin-ops.labels" -}}
helm.sh/chart: {{ include "coin-ops.chart" . }}
{{ include "coin-ops.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "coin-ops.selectorLabels" -}}
app.kubernetes.io/name: {{ include "coin-ops.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
