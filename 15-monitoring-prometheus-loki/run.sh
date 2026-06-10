#!/usr/bin/env bash
#
# Chapter 15 — Monitoring & Logging.
#   Metrics: kube-prometheus-stack (Prometheus + Grafana + Alertmanager)
#   Logs:    Loki + Promtail   (lightweight — replaces heavy Elasticsearch/OpenSearch)
# Both show up in one Grafana.

source "$(dirname "$0")/../lib.sh"
cd "$(dirname "$0")"

need kubectl helm
need_cluster
title "Chapter 15 — Monitoring & Logging"
warn "this chapter is resource-heavy — give Docker ~6GB RAM and close other chapters first."

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null
helm repo add grafana https://grafana.github.io/helm-charts >/dev/null
helm repo update prometheus-community grafana >/dev/null
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

step "installing Loki + Promtail (lightweight log collection)"
helm upgrade --install loki grafana/loki-stack -n monitoring \
  --set grafana.enabled=false \
  --set prometheus.enabled=false \
  --set promtail.enabled=true

step "installing Prometheus + Grafana + Alertmanager (this takes a few minutes)"
helm upgrade --install kps prometheus-community/kube-prometheus-stack -n monitoring \
  -f monitoring-values.yaml

step "waiting for Grafana"
kubectl -n monitoring rollout status deploy/kps-grafana --timeout=300s

title "Monitoring ready"
info "1) open Grafana:"
info "     kubectl -n monitoring port-forward svc/kps-grafana 3000:80"
info "2) browse http://localhost:3000   (login: admin / admin)"
info "3) METRICS: open a dashboard (try 'Kubernetes / Compute Resources / Namespace (Pods)')"
info "4) LOGS:    left menu -> Explore -> pick the 'Loki' data source -> query  {namespace=\"kube-system\"}"
info "Alertmanager:  kubectl -n monitoring port-forward svc/kps-kube-prometheus-stack-alertmanager 9093:9093"
info "Clean up:  ./cleanup.sh"
