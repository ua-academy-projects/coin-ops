{{- define "coin-ops.appNamespace" -}}
{{- .Values.namespaces.app | default .Release.Namespace -}}
{{- end -}}

{{- define "coin-ops.workersNamespace" -}}
{{- .Values.namespaces.workers | default (include "coin-ops.appNamespace" .) -}}
{{- end -}}

{{- define "coin-ops.dataNamespace" -}}
{{- .Values.namespaces.data | default (include "coin-ops.appNamespace" .) -}}
{{- end -}}

{{- define "coin-ops.partOf" -}}
{{- .Values.app.name -}}
{{- end -}}

{{- define "coin-ops.commonLabels" -}}
app.kubernetes.io/part-of: {{ include "coin-ops.partOf" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
{{- end -}}

{{- define "coin-ops.nameLabels" -}}
app.kubernetes.io/name: {{ .name }}
app.kubernetes.io/part-of: {{ include "coin-ops.partOf" .root }}
app.kubernetes.io/managed-by: {{ .root.Release.Service }}
helm.sh/chart: {{ .root.Chart.Name }}-{{ .root.Chart.Version | replace "+" "_" }}
{{- end -}}

{{- define "coin-ops.image" -}}
{{- printf "%s:%s" .repository .tag -}}
{{- end -}}

{{- define "coin-ops.imagePullSecrets" -}}
{{- if .Values.imagePullSecrets }}
imagePullSecrets:
{{- range .Values.imagePullSecrets }}
  - name: {{ .name }}
{{- end }}
{{- end }}
{{- end -}}
