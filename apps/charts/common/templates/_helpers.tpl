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
Standard container port
*/}}
{{- define "common.containerPort" -}}
{{- if .Values.container.port }}
{{- .Values.container.port }}
{{- else }}
80
{{- end }}
{{- end }}

{{/*
Standard service port
*/}}
{{- define "common.servicePort" -}}
{{- if .Values.service.port }}
{{- .Values.service.port }}
{{- else }}
80
{{- end }}
{{- end }}

{{/*
Standard health probe
*/}}
{{- define "common.healthProbe" -}}
{{- if .Values.container.healthProbe }}
{{- if eq .Values.container.healthProbe.type "httpGet" }}
httpGet:
  path: {{ .Values.container.healthProbe.path | default "/" }}
  port: {{ include "common.containerPort" . }}
{{- else if eq .Values.container.healthProbe.type "tcpSocket" }}
tcpSocket:
  port: {{ include "common.containerPort" . }}
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
      name: {{ $value.valueFrom.secretKeyRef.name }}
      key: {{ $value.valueFrom.secretKeyRef.key }}
    {{- else if $value.valueFrom.configMapKeyRef }}
    configMapKeyRef:
      name: {{ $value.valueFrom.configMapKeyRef.name }}
      key: {{ $value.valueFrom.configMapKeyRef.key }}
    {{- end }}
  {{- end }}
  {{- else }}
  value: {{ $value | quote }}
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
  replicas: {{ .Values.deployment.replicas | default 1 }}
  {{- if .Values.deployment.revisionHistoryLimit }}
  revisionHistoryLimit: {{ .Values.deployment.revisionHistoryLimit }}
  {{- end }}
  selector:
    matchLabels:
      {{- include "common.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "common.selectorLabels" . | nindent 8 }}
    spec:
      containers:
        - name: {{ .Chart.Name }}
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy | default "IfNotPresent" }}
          ports:
            - name: http
              containerPort: {{ include "common.containerPort" . }}
              protocol: TCP
          {{- if .Values.container.healthProbe }}
          livenessProbe:
{{ include "common.healthProbe" . | indent 12 }}
          readinessProbe:
{{ include "common.healthProbe" . | indent 12 }}
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
Full Service resource
*/}}
{{- define "common.service" -}}
{{- if .Values.service }}
apiVersion: v1
kind: Service
metadata:
  name: {{ include "common.fullname" . }}
  labels:
    {{- include "common.labels" . | nindent 4 }}
spec:
  type: {{ .Values.service.type | default "ClusterIP" }}
  ports:
    - port: {{ include "common.servicePort" . }}
      targetPort: {{ include "common.containerPort" . }}
      protocol: TCP
      name: http
  selector:
    {{- include "common.selectorLabels" . | nindent 4 }}
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
  labels:
    {{- include "common.labels" $ | nindent 4 }}
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: {{ .size }}
  {{- if $.Values.globals.environment }}
  storageClassName: {{ $.Values.globals.environment }}
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
    - mesh
  http:
    - route:
        - destination:
            host: {{ include "common.fullname" . }}
            port:
              number: {{ include "common.servicePort" . }}

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
    - mesh
  http:
    - route:
        - destination:
            host: {{ include "common.fullname" . }}
            port:
              number: {{ include "common.servicePort" . }}
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
{{- end }}
{{- end }}
