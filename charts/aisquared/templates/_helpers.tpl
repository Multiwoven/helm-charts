{{/*
Expand the name of the chart.
*/}}
{{- define "chart.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "chart.fullname" -}}
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
{{- define "chart.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "chart.labels" -}}
helm.sh/chart: {{ include "chart.chart" . }}
{{ include "chart.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "chart.selectorLabels" -}}
app.kubernetes.io/name: {{ include "chart.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "chart.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "chart.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Fail on values keys that were renamed in the AI Squared rebrand. Helm ignores
unknown keys, so without this an old values file or --set flag would render
with chart defaults (example.com hosts, default images and DB settings)
instead of erroring.
*/}}
{{- define "chart.failOnRenamedValues" -}}
{{- $topLevel := dict "multiwovenConfig" "platformConfig" "multiwovenServer" "server" "multiwovenUI" "ui" "multiwovenWorker" "worker" "multiwovenSolidWorker" "solidWorker" "multiwovenPostgresql" "postgresql" }}
{{- range $old, $new := $topLevel }}
{{- if hasKey $.Values $old }}
{{- fail (printf "values key %q was renamed to %q" $old $new) }}
{{- end }}
{{- end }}
{{- $nested := dict "server" "multiwovenServer" "ui" "multiwovenUI" "worker" "multiwovenWorker" "solidWorker" "multiwovenSolidWorker" "postgresql" "multiwovenPostgresql" }}
{{- range $parent, $old := $nested }}
{{- if hasKey (index $.Values $parent) $old }}
{{- fail (printf "values key %q was renamed to %q" (printf "%s.%s" $parent $old) (printf "%s.%s" $parent $parent)) }}
{{- end }}
{{- end }}
{{- $hpa := dict "multiwovenServer" "server" "multiwovenUI" "ui" "multiwovenWorker" "worker" "multiwovenSolidWorker" "solidWorker" }}
{{- range $old, $new := $hpa }}
{{- if hasKey $.Values.hpa $old }}
{{- fail (printf "values key %q was renamed to %q" (printf "hpa.%s" $old) (printf "hpa.%s" $new)) }}
{{- end }}
{{- end }}
{{- $db := dict "multiwovenDBHost" "platformDBHost" "multiwovenDBName" "platformDBName" }}
{{- range $old, $new := $db }}
{{- if hasKey $.Values.multipleDbHosts $old }}
{{- fail (printf "values key %q was renamed to %q" (printf "multipleDbHosts.%s" $old) (printf "multipleDbHosts.%s" $new)) }}
{{- end }}
{{- end }}
{{- end }}
