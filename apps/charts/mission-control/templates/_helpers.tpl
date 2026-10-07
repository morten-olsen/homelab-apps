{{- define "mission-control.agentImage" -}}
{{- $image := required "agentImage must be set to code.olsen.cloud/ai/mission-control-agent:<tag>@sha256:<digest>" .Values.agentImage -}}
{{- if not (regexMatch "@sha256:[0-9a-f]{64}$" $image) -}}
{{- fail "agentImage must be pinned by digest (…@sha256:<64 hex digits>): a registry tag can move" -}}
{{- end -}}
{{- $image -}}
{{- end -}}
