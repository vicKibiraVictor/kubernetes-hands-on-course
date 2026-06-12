#!/usr/bin/env bash
#
# Chapter 16 — An Introduction to Istio (a service mesh).
# Istio puts a tiny proxy next to every pod, so you get traffic control,
# security (mTLS), and observability WITHOUT changing your app's code.

source "$(dirname "$0")/../lib.sh"
cd "$(dirname "$0")"

need kubectl curl
need_cluster
title "Chapter 16 — Introduction to Istio"
warn "Istio is resource-heavy. Give Docker ~6GB RAM."

# download Istio (gives us istioctl + the sample apps)
if ! ls -d istio-*/ >/dev/null 2>&1; then
  step "downloading Istio"
  curl -L https://istio.io/downloadIstio | sh -
fi
ISTIO_DIR="$(ls -d istio-*/ | head -1)"
export PATH="${PWD}/${ISTIO_DIR}bin:${PATH}"
# make istioctl available to Chapter 17 too
SUDO=""; [ -w /usr/local/bin ] || SUDO="sudo"
$SUDO cp "${ISTIO_DIR}bin/istioctl" /usr/local/bin/ 2>/dev/null || true
info "istioctl $(istioctl version --remote=false 2>/dev/null)"

step "installing Istio (slim config — see slim-istio.yaml)"
istioctl install -f slim-istio.yaml -y

step "creating namespace 'bookinfo' with automatic sidecar injection"
kubectl create namespace bookinfo --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace bookinfo istio-injection=enabled --overwrite

step "deploying the Bookinfo sample app"
kubectl apply -n bookinfo -f "${ISTIO_DIR}samples/bookinfo/platform/kube/bookinfo.yaml"
kubectl -n bookinfo wait --for=condition=Ready pods --all --timeout=300s || true
info "notice each pod is 2/2 — your container + the Istio sidecar proxy"

step "installing just Kiali + Prometheus (skipping Grafana/Jaeger to save resources)"
kubectl apply -f "${ISTIO_DIR}samples/addons/prometheus.yaml"
kubectl apply -f "${ISTIO_DIR}samples/addons/kiali.yaml" \
  || (sleep 5; kubectl apply -f "${ISTIO_DIR}samples/addons/kiali.yaml")
kubectl -n istio-system rollout status deploy/kiali --timeout=180s

title "Istio is running"
info "Generate some traffic (run in another terminal):"
info "  kubectl -n bookinfo port-forward svc/productpage 9080:9080"
info "  then:  for i in \$(seq 1 50); do curl -s -o /dev/null http://localhost:9080/productpage; done"
info "See the live service graph in Kiali:"
info "  istioctl dashboard kiali        (opens your browser)"
info "Clean up:  ./cleanup.sh"
