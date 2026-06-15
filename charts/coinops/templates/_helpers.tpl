{{/*
Chart name (truncated to 63 chars, the Kubernetes label limit).
Used as a base for resource names that are not overridden by a per-component fullname.
*/}}
{{- define "coinops.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Standard Kubernetes recommended labels applied to every resource.
Pass a component name via dict: include "coinops.labels" (dict "ctx" . "component" "proxy")
*/}}
{{- define "coinops.labels" -}}
app.kubernetes.io/name: {{ .component }}
app.kubernetes.io/instance: {{ .ctx.Release.Name }}
app.kubernetes.io/managed-by: {{ .ctx.Release.Service }}
app.kubernetes.io/part-of: {{ include "coinops.name" .ctx }}
app.kubernetes.io/version: {{ .ctx.Chart.AppVersion | quote }}
helm.sh/chart: {{ printf "%s-%s" .ctx.Chart.Name .ctx.Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end -}}

{{/*
Selector labels — the subset of labels that uniquely identifies a workload.
These MUST be immutable: a Deployment's spec.selector cannot be edited after creation.
Pass: include "coinops.selectorLabels" (dict "ctx" . "component" "proxy")
*/}}
{{- define "coinops.selectorLabels" -}}
app.kubernetes.io/name: {{ .component }}
app.kubernetes.io/instance: {{ .ctx.Release.Name }}
{{- end -}}

{{/*
Build a full container image reference from a component image config and global defaults.
Pass: include "coinops.image" (dict "ctx" . "image" .Values.proxy.image)
where image is a dict like { name: "coin-ops-proxy", tag: "" } and `tag` may fall back to global.imageTag.
*/}}
{{- define "coinops.image" -}}
{{- $registry := .ctx.Values.global.imageRegistry -}}
{{- $tag := default .ctx.Values.global.imageTag .image.tag -}}
{{- printf "%s/%s:%s" $registry .image.name $tag -}}
{{- end -}}
