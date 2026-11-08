{{- define "kubecomputer.labels" -}}
app.kubernetes.io/name: kubecomputer
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Values.image.tag | splitList "@" | first | trunc 63 | trimAll "-_." | quote }}
{{- end }}

{{- define "kubecomputer.image" -}}
{{- required "image.tag is required" .Values.image.tag | printf "%s:%s" .Values.image.repository }}
{{- end }}

{{- define "kubecomputer.url" -}}
http://kubecomputer.{{ .Values.namespace }}.svc:8090
{{- end }}
