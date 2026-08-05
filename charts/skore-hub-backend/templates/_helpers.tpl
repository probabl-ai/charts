{{/*
Expand the name of the chart.
*/}}
{{- define "skore-hub.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this
(by the DNS naming spec).
*/}}
{{- define "skore-hub.fullname" -}}
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
{{- define "skore-hub.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "skore-hub.labels" -}}
helm.sh/chart: {{ include "skore-hub.chart" . }}
{{ include "skore-hub.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "skore-hub.selectorLabels" -}}
app.kubernetes.io/name: {{ include "skore-hub.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use.
*/}}
{{- define "skore-hub.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "skore-hub.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Render the application environment (SKH__* variables) from the `skh.env` map.
*/}}
{{- define "skore-hub.env" -}}
{{- range $key, $value := .Values.skh.env }}
- name: {{ $key }}
  value: {{ $value | quote }}
{{- end }}
{{- end }}

{{/*
Volume for the TOML ConfigMap. Empty when `skh.config.enabled` is false.
*/}}
{{- define "skore-hub.configVolume" -}}
{{- if .Values.skh.config.enabled }}
- name: skh-config
  configMap:
    name: {{ include "skore-hub.fullname" . }}-config
{{- end }}
{{- end -}}

{{/*
VolumeMount for the TOML ConfigMap. Empty when `skh.config.enabled` is false.
*/}}
{{- define "skore-hub.configVolumeMount" -}}
{{- if .Values.skh.config.enabled }}
- name: skh-config
  mountPath: {{ .Values.skh.config.mountPath }}
  readOnly: true
{{- end }}
{{- end -}}

{{/*
`SKH_CONFIG_FILE` env entry pointing at the mounted TOML. Emitted only when
`skh.config.enabled` is true AND the user has not already set `SKH_CONFIG_FILE`
in `skh.env` or `skh.extraEnv` (their explicit value then wins).
*/}}
{{- define "skore-hub.configEnv" -}}
{{- if .Values.skh.config.enabled }}
{{- $userSet := false -}}
{{- if hasKey .Values.skh.env "SKH_CONFIG_FILE" }}{{- $userSet = true }}{{- end -}}
{{- range .Values.skh.extraEnv }}{{- if eq .name "SKH_CONFIG_FILE" }}{{- $userSet = true }}{{- end }}{{- end -}}
{{- if not $userSet }}
- name: SKH_CONFIG_FILE
  value: {{ printf "%s/%s" .Values.skh.config.mountPath .Values.skh.config.filename | quote }}
{{- end }}
{{- end }}
{{- end -}}

{{/*
SHA-256 checksum of `skh.config.data`, used as a pod annotation so a config
change rolls out the Deployment and re-runs the migrations Job. Empty when the
ConfigMap is disabled (so no annotation is emitted).
*/}}
{{- define "skore-hub.configChecksum" -}}
{{- if .Values.skh.config.enabled }}{{- .Values.skh.config.data | sha256sum }}{{- end }}
{{- end -}}
