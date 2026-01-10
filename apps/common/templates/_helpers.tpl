{{/*
Expand the name of the chart.
*/}}
{{- define "common.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "common.fullname" -}}
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
{{- define "common.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "common.labels" -}}
helm.sh/chart: {{ include "common.chart" . }}
{{ include "common.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "common.selectorLabels" -}}
app.kubernetes.io/name: {{ include "common.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Standard deployment strategy
*/}}
{{- define "common.deploymentStrategy" -}}
{{- if .Values.deployment.strategy }}
{{- .Values.deployment.strategy }}
{{- else }}
Recreate
{{- end }}
{{- end }}

{{/*
Standard container port (for backward compatibility)
*/}}
{{- define "common.containerPort" -}}
{{- if .Values.container.ports }}
{{- $primaryPort := first .Values.container.ports }}
{{- $primaryPort.port }}
{{- else if .Values.container.port }}
{{- .Values.container.port }}
{{- else }}
80
{{- end }}
{{- end }}

{{/*
Container ports list
*/}}
{{- define "common.containerPorts" -}}
{{- if .Values.container.ports }}
{{- range .Values.container.ports }}
- name: {{ .name }}
  containerPort: {{ .port }}
  protocol: {{ .protocol | default "TCP" }}
{{- end }}
{{- else if .Values.container.port }}
- name: http
  containerPort: {{ .Values.container.port }}
  protocol: TCP
{{- else }}
- name: http
  containerPort: 80
  protocol: TCP
{{- end }}
{{- end }}

{{/*
Standard service port (for backward compatibility)
*/}}
{{- define "common.servicePort" -}}
{{- if .Values.service.ports }}
{{- $primaryService := first .Values.service.ports }}
{{- $primaryService.port }}
{{- else if .Values.service.port }}
{{- .Values.service.port }}
{{- else }}
80
{{- end }}
{{- end }}

{{/*
Service ports list
*/}}
{{- define "common.servicePorts" -}}
{{- if .Values.service.ports }}
{{- range .Values.service.ports }}
- port: {{ .port }}
  targetPort: {{ .targetPort | default .port }}
  protocol: {{ .protocol | default "TCP" }}
  name: {{ .name }}
{{- end }}
{{- else if .Values.service.port }}
- port: {{ .Values.service.port }}
  targetPort: {{ include "common.containerPort" . }}
  protocol: TCP
  name: http
{{- else }}
- port: 80
  targetPort: {{ include "common.containerPort" . }}
  protocol: TCP
  name: http
{{- end }}
{{- end }}

{{/*
Standard health probe
*/}}
{{- define "common.healthProbe" -}}
{{- if .Values.container.healthProbe }}
{{- $probePort := .Values.container.healthProbe.port | default (include "common.containerPort" .) }}
{{- if eq .Values.container.healthProbe.type "httpGet" }}
httpGet:
  path: {{ .Values.container.healthProbe.path | default "/" }}
  {{- if regexMatch "^[0-9]+$" $probePort }}
  port: {{ $probePort }}
  {{- else }}
  port: {{ $probePort }}
  {{- end }}
{{- else if eq .Values.container.healthProbe.type "tcpSocket" }}
tcpSocket:
  {{- if regexMatch "^[0-9]+$" $probePort }}
  port: {{ $probePort }}
  {{- else }}
  port: {{ $probePort }}
  {{- end }}
{{- end }}
{{- if .Values.container.healthProbe.initialDelaySeconds }}
initialDelaySeconds: {{ .Values.container.healthProbe.initialDelaySeconds }}
{{- end }}
{{- if .Values.container.healthProbe.periodSeconds }}
periodSeconds: {{ .Values.container.healthProbe.periodSeconds }}
{{- end }}
{{- if .Values.container.healthProbe.timeoutSeconds }}
timeoutSeconds: {{ .Values.container.healthProbe.timeoutSeconds }}
{{- end }}
{{- if .Values.container.healthProbe.failureThreshold }}
failureThreshold: {{ .Values.container.healthProbe.failureThreshold }}
{{- end }}
{{- else }}
tcpSocket:
  port: {{ include "common.containerPort" . }}
{{- end }}
{{- end }}

{{/*
Full domain name
*/}}
{{- define "common.domain" -}}
{{ .Values.subdomain }}.{{ .Values.globals.domain }}
{{- end }}

{{/*
Full URL
*/}}
{{- define "common.url" -}}
https://{{ include "common.domain" . }}
{{- end }}

{{/*
Standard volume mounts
*/}}
{{- define "common.volumeMounts" -}}
{{- range .Values.volumes }}
- name: {{ .name }}
  mountPath: {{ .mountPath }}
{{- if .subPath }}
  subPath: {{ .subPath }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Standard volumes
*/}}
{{- define "common.volumes" -}}
{{- range .Values.volumes }}
- name: {{ .name }}
  {{- if .persistentVolumeClaim }}
  persistentVolumeClaim:
    {{- if or (eq .persistentVolumeClaim "config") (eq .persistentVolumeClaim "metadata") (eq .persistentVolumeClaim "data") }}
    claimName: {{ $.Release.Name }}-{{ .persistentVolumeClaim }}
    {{- else }}
    claimName: {{ .persistentVolumeClaim }}
    {{- end }}
  {{- else if .configMap }}
  configMap:
    name: {{ .configMap }}
  {{- else if .secret }}
  secret:
    secretName: {{ .secret }}
  {{- end }}
{{- end }}
{{- end }}

{{/*
Standard environment variables
*/}}
{{- define "common.env" -}}
{{- if .Values.env }}
{{- range $key, $value := .Values.env }}
- name: {{ $key }}
  {{- if kindIs "map" $value }}
  {{- if $value.valueFrom }}
  valueFrom:
    {{- if $value.valueFrom.secretKeyRef }}
    secretKeyRef:
      name: {{ $value.valueFrom.secretKeyRef.name | replace "{release}" $.Release.Name | replace "{namespace}" $.Release.Namespace | replace "{fullname}" (include "common.fullname" $) }}
      key: {{ $value.valueFrom.secretKeyRef.key }}
    {{- else if $value.valueFrom.configMapKeyRef }}
    configMapKeyRef:
      name: {{ $value.valueFrom.configMapKeyRef.name | replace "{release}" $.Release.Name | replace "{namespace}" $.Release.Namespace | replace "{fullname}" (include "common.fullname" $) }}
      key: {{ $value.valueFrom.configMapKeyRef.key }}
    {{- end }}
  {{- else if $value.value }}
  value: {{ $value.value | replace "{release}" $.Release.Name | replace "{namespace}" $.Release.Namespace | replace "{fullname}" (include "common.fullname" $) | replace "{subdomain}" $.Values.subdomain | replace "{domain}" $.Values.globals.domain | replace "{timezone}" $.Values.globals.timezone | quote }}
  {{- end }}
  {{- else }}
  value: {{ $value | replace "{release}" $.Release.Name | replace "{namespace}" $.Release.Namespace | replace "{fullname}" (include "common.fullname" $) | replace "{subdomain}" $.Values.subdomain | replace "{domain}" $.Values.globals.domain | replace "{timezone}" $.Values.globals.timezone | quote }}
  {{- end }}
{{- end }}
{{- end }}
{{- if .Values.globals.timezone }}
- name: TZ
  value: {{ .Values.globals.timezone | quote }}
{{- end }}
{{- end }}

{{/*
VirtualService gateway list for public gateway
*/}}
{{- define "common.virtualServiceGatewaysPublic" -}}
- {{ .Values.globals.istio.gateways.public | quote }}
- mesh
{{- end }}

{{/*
VirtualService gateway list for private gateway
*/}}
{{- define "common.virtualServiceGatewaysPrivate" -}}
- {{ .Values.globals.istio.gateways.private | quote }}
- mesh
{{- end }}

{{/*
DNS configuration for pod spec
*/}}
{{- define "common.dnsConfig" -}}
{{- if .Values.deployment.dns }}
{{- if .Values.deployment.dns.nameservers }}
dnsPolicy: {{ .Values.deployment.dns.policy | default "None" }}
dnsConfig:
  nameservers:
{{- range .Values.deployment.dns.nameservers }}
    - {{ . | quote }}
{{- end }}
{{- if .Values.deployment.dns.searches }}
  searches:
{{- range .Values.deployment.dns.searches }}
    - {{ . | quote }}
{{- end }}
{{- end }}
{{- if .Values.deployment.dns.options }}
  options:
{{- range .Values.deployment.dns.options }}
    - {{ toYaml . | nindent 6 }}
{{- end }}
{{- end }}
{{- end }}
{{- else if .Values.deployment.dnsPolicy }}
dnsPolicy: {{ .Values.deployment.dnsPolicy }}
{{- end }}
{{- end }}

{{/*
Full Deployment resource
*/}}
{{- define "common.deployment" -}}
{{- if .Values.deployment }}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "common.fullname" . }}
  labels:
    {{- include "common.labels" . | nindent 4 }}
spec:
  strategy:
    type: {{ include "common.deploymentStrategy" . }}
  {{- if hasKey .Values.deployment "replicas" }}
  replicas: {{ .Values.deployment.replicas }}
  {{- else }}
  replicas: {{ .Values.deployment.replicas }}
  {{- end }}
  {{- if hasKey .Values.deployment "revisionHistoryLimit" }}
  revisionHistoryLimit: {{ .Values.deployment.revisionHistoryLimit }}
  {{- else }}
  revisionHistoryLimit: 2
  {{- end }}
  selector:
    matchLabels:
      {{- include "common.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      {{- if .Values.deployment.podAnnotations }}
      annotations:
        {{- toYaml .Values.deployment.podAnnotations | nindent 8 }}
      {{- end }}
      labels:
        {{- include "common.selectorLabels" . | nindent 8 }}
    spec:
      {{- if .Values.deployment.serviceAccountName }}
      serviceAccountName: {{ .Values.deployment.serviceAccountName | replace "{release}" .Release.Name | replace "{fullname}" (include "common.fullname" .) }}
      {{- end }}
      {{- if .Values.deployment.hostNetwork }}
      hostNetwork: {{ .Values.deployment.hostNetwork }}
      {{- end }}
      {{- include "common.dnsConfig" . | nindent 6 }}
      containers:
        - name: {{ .Chart.Name }}
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy | default "IfNotPresent" }}
          {{- if .Values.command }}
          command: {{- toYaml .Values.command | nindent 12 }}
          {{- end }}
          {{- if .Values.args }}
          args: {{- toYaml .Values.args | nindent 12 }}
          {{- end }}
          ports:
{{ include "common.containerPorts" . | indent 12 }}
          {{- if .Values.container.healthProbe }}
          livenessProbe:
{{ include "common.healthProbe" . | indent 12 }}
          readinessProbe:
{{ include "common.healthProbe" . | indent 12 }}
          {{- end }}
          {{- if .Values.container.securityContext }}
          securityContext:
            {{- toYaml .Values.container.securityContext | nindent 12 }}
          {{- end }}
          {{- if .Values.volumes }}
          volumeMounts:
{{ include "common.volumeMounts" . | indent 12 }}
          {{- end }}
          {{- if or .Values.env .Values.globals.timezone }}
          env:
{{ include "common.env" . | indent 12 }}
          {{- end }}
      {{- if .Values.volumes }}
      volumes:
        {{- include "common.volumes" . | nindent 8 }}
      {{- end }}
{{- end }}
{{- end }}

{{/*
Full ServiceAccount resource
*/}}
{{- define "common.serviceAccount" -}}
{{- if .Values.serviceAccount }}
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ if .Values.serviceAccount.name }}{{ .Values.serviceAccount.name }}{{ else }}{{ include "common.fullname" . }}{{ end }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "common.labels" . | nindent 4 }}
{{- if .Values.serviceAccount.annotations }}
  annotations:
    {{- toYaml .Values.serviceAccount.annotations | nindent 4 }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Full Service resource(s) - supports multiple services
*/}}
{{- define "common.service" -}}
{{- if .Values.service }}
{{- if .Values.service.ports }}
{{- $firstPort := index .Values.service.ports 0 }}
{{- range $index, $port := .Values.service.ports }}
---
apiVersion: v1
kind: Service
metadata:
  name: {{ if $port.serviceName }}{{ include "common.fullname" $ }}-{{ $port.serviceName }}{{ else }}{{ include "common.fullname" $ }}{{ if and (gt $index 0) }}-{{ $port.name }}{{ end }}{{ end }}
  labels:
    {{- include "common.labels" $ | nindent 4 }}
spec:
  type: {{ $port.type | default $.Values.service.type | default "ClusterIP" }}
  ports:
    - port: {{ $port.port }}
      targetPort: {{ $port.targetPort | default $port.port }}
      protocol: {{ $port.protocol | default "TCP" }}
      name: {{ $port.name }}
  selector:
    {{- include "common.selectorLabels" $ | nindent 4 }}
{{- end }}
{{- else }}
apiVersion: v1
kind: Service
metadata:
  name: {{ include "common.fullname" . }}
  labels:
    {{- include "common.labels" . | nindent 4 }}
spec:
  type: {{ .Values.service.type | default "ClusterIP" }}
  ports:
{{ include "common.servicePorts" . | indent 4 }}
  selector:
    {{- include "common.selectorLabels" . | nindent 4 }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Full PVC resources
*/}}
{{- define "common.pvc" -}}
{{- if .Values.persistentVolumeClaims }}
{{- range .Values.persistentVolumeClaims }}
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: {{ $.Release.Name }}-{{ .name }}
  annotations:
    longhorn.io/description: "{{ $.Release.Namespace }}/{{ $.Release.Name }}"
    argocd.argoproj.io/sync-options: Delete=false
  labels:
    {{- include "common.labels" $ | nindent 4 }}
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: {{ .size }}
  {{- if .storageClassName }}
  storageClassName: {{ .storageClassName }}
  {{- else if $.Values.globals.storageClassName }}
  storageClassName: {{ $.Values.globals.storageClassName }}
  {{- end }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Full VirtualService resources
*/}}
{{- define "common.virtualService" -}}
{{- if and .Values.virtualService.enabled .Values.subdomain (hasKey .Values.globals "domain") (ne .Values.globals.domain "") }}
{{- if and .Values.virtualService.gateways.public (hasKey .Values.globals "istio") (hasKey .Values.globals.istio "gateways") (hasKey .Values.globals.istio.gateways "public") (ne .Values.globals.istio.gateways.public "") }}
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: {{ include "common.fullname" . }}-public
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "common.labels" . | nindent 4 }}
spec:
  gateways:
    {{- include "common.virtualServiceGatewaysPublic" . | nindent 4 }}
  hosts:
    - {{ include "common.domain" . }}
    {{- if .Values.virtualService.allowWildcard }}
    - "*.{{ include "common.domain" . }}"
    {{- end }}
    - mesh
  http:
    - route:
        - destination:
            host: {{ include "common.fullname" . }}
            port:
              {{- if .Values.virtualService.servicePort }}
              number: {{ .Values.virtualService.servicePort }}
              {{- else }}
              number: {{ include "common.servicePort" . }}
              {{- end }}

---
{{- end }}
{{- if and .Values.virtualService.gateways.private (hasKey .Values.globals "istio") (hasKey .Values.globals.istio "gateways") (hasKey .Values.globals.istio.gateways "private") (ne .Values.globals.istio.gateways.private "") }}
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: {{ include "common.fullname" . }}-private
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "common.labels" . | nindent 4 }}
spec:
  gateways:
    {{- include "common.virtualServiceGatewaysPrivate" . | nindent 4 }}
  hosts:
    - {{ include "common.domain" . }}
    {{- if .Values.virtualService.allowWildcard }}
    - "*.{{ include "common.domain" . }}"
    {{- end }}
    - mesh
  http:
    - route:
        - destination:
            host: {{ include "common.fullname" . }}
            port:
              {{- if .Values.virtualService.servicePort }}
              number: {{ .Values.virtualService.servicePort }}
              {{- else }}
              number: {{ include "common.servicePort" . }}
              {{- end }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Full DNS resource
*/}}
{{- define "common.dns" -}}
{{- if and .Values.dns.enabled (hasKey .Values.globals "networking") (hasKey .Values.globals.networking "private") (hasKey .Values.globals.networking.private "ip") (ne .Values.globals.networking.private.ip "") }}
apiVersion: dns.homelab.mortenolsen.pro/v1alpha1
kind: DNSRecord
metadata:
  name: {{ include "common.fullname" . }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "common.labels" . | nindent 4 }}
spec:
  type: {{ .Values.dns.type | default "A" }}
  domain: {{ .Values.globals.domain }}
  subdomain: {{ .Values.subdomain }}
  {{- if .Values.dns.dnsClassRef }}
  dnsClassRef:
    {{- toYaml .Values.dns.dnsClassRef | nindent 4 }}
  {{- end }}
  values:
    - {{ .Values.globals.networking.private.ip | quote }}
{{- end }}
{{- end }}

{{/*
Full OIDC/AuthentikClient resource
*/}}
{{- define "common.oidc" -}}
{{- if and .Values.oidc.enabled (hasKey .Values.globals "authentik") (hasKey .Values.globals.authentik "ref") (hasKey .Values.globals.authentik.ref "name") (hasKey .Values.globals.authentik.ref "namespace") (ne .Values.globals.authentik.ref.name "") (ne .Values.globals.authentik.ref.namespace "") }}
apiVersion: authentik.homelab.mortenolsen.pro/v1alpha1
kind: AuthentikClient
metadata:
  name: {{ include "common.fullname" . }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "common.labels" . | nindent 4 }}
spec:
  serverRef:
    name: {{ .Values.globals.authentik.ref.name }}
    namespace: {{ .Values.globals.authentik.ref.namespace }}
  name: {{ include "common.fullname" . }}
  redirectUris:
    {{- range .Values.oidc.redirectUris }}
    - {{ printf "https://%s%s" (include "common.domain" $) . | quote }}
    {{- end }}
  subjectMode: {{ .Values.oidc.subjectMode | default "user_username" }}
{{- end }}
{{- end }}

{{/*
Full PostgreSQL Database resource
*/}}
{{- define "common.database" -}}
{{- if and .Values.database.enabled (hasKey .Values.globals "database") (hasKey .Values.globals.database "ref") (hasKey .Values.globals.database.ref "name") (hasKey .Values.globals.database.ref "namespace") (ne .Values.globals.database.ref.name "") (ne .Values.globals.database.ref.namespace "") }}
apiVersion: postgres.homelab.mortenolsen.pro/v1
kind: PostgresDatabase
metadata:
  name: {{ .Release.Name }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "common.labels" . | nindent 4 }}
spec:
  clusterRef:
    name: {{ .Values.globals.database.ref.name | quote }}
    namespace: {{ .Values.globals.database.ref.namespace | quote }}
{{- end }}
{{- end }}

{{/*
Password generators for External Secrets (create these first)
*/}}
{{- define "common.externalSecrets.passwordGenerators" -}}
{{- if .Values.externalSecrets }}
{{- range .Values.externalSecrets }}
{{- $secretName := .name | default (printf "%s-%s" $.Release.Name "secrets") }}
{{- $secretName = $secretName | replace "{release}" $.Release.Name | replace "{fullname}" (include "common.fullname" $) }}
{{- range .passwords }}
---
apiVersion: generators.external-secrets.io/v1alpha1
kind: Password
metadata:
  name: {{ $secretName }}-{{ .name }}-generator
  namespace: {{ $.Release.Namespace }}
  labels:
    {{- include "common.labels" $ | nindent 4 }}
spec:
  length: {{ .length | default 32 }}
  allowRepeat: {{ .allowRepeat | default false }}
  noUpper: {{ .noUpper | default false }}
  {{- if .encoding }}
  encoding: {{ .encoding }}
  {{- end }}
  {{- if .secretKeys }}
  secretKeys:
    {{- range .secretKeys }}
    - {{ . }}
    {{- end }}
  {{- end }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}

{{/*
External Secrets (create these after password generators)
*/}}
{{- define "common.externalSecrets.externalSecrets" -}}
{{- if .Values.externalSecrets }}
{{- range .Values.externalSecrets }}
{{- $secretName := .name | default (printf "%s-%s" $.Release.Name "secrets") }}
{{- $secretName = $secretName | replace "{release}" $.Release.Name | replace "{fullname}" (include "common.fullname" $) }}
---
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: {{ $secretName }}
  namespace: {{ $.Release.Namespace }}
  labels:
    {{- include "common.labels" $ | nindent 4 }}
spec:
  refreshInterval: "0"
  # rotationPolicy is intentionally not set to ensure no automatic rotation
  target:
    name: {{ $secretName }}
    creationPolicy: Owner
  dataFrom:
    {{- range .passwords }}
    - sourceRef:
        generatorRef:
          apiVersion: generators.external-secrets.io/v1alpha1
          kind: Password
          name: {{ $secretName }}-{{ .name }}-generator
    {{- end }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Full External Secrets resources (ExternalSecret + Password generators)
Combined helper that outputs generators first, then ExternalSecrets
*/}}
{{- define "common.externalSecrets" -}}
{{- include "common.externalSecrets.passwordGenerators" . }}
{{- include "common.externalSecrets.externalSecrets" . }}
{{- end }}
