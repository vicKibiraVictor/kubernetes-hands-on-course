#!/usr/bin/env bash
#
# Chapter 17 — Building & Securing Apps on Istio.
# Builds on Chapter 16's Bookinfo. We add: a gateway to expose it, STRICT mTLS so
# only mesh members can talk, and an authorization rule (GET only).

source "$(dirname "$0")/../lib.sh"
cd "$(dirname "$0")"

need kubectl
need_cluster
title "Chapter 17 — Securing Apps on Istio"

kubectl get ns bookinfo >/dev/null 2>&1 || die "Bookinfo not found. Run Chapter 16 first."

step "deploying an in-mesh test client"
kubectl apply -f manifests/meshclient.yaml
kubectl -n bookinfo rollout status deploy/meshclient --timeout=120s

# helper: run curl from inside the mesh and print the HTTP status
mesh() { kubectl -n bookinfo exec deploy/meshclient -c curl -- curl -s -m 5 -o /dev/null -w '%{http_code}' "$@" 2>/dev/null || echo FAILED; }

step "1) expose Bookinfo through the Istio gateway"
kubectl apply -f manifests/gateway.yaml
info "in-mesh GET productpage -> $(mesh http://productpage:9080/productpage)   (expect 200)"

step "2) turn on STRICT mTLS"
kubectl apply -f manifests/peer-auth-strict.yaml
sleep 6
info "in-mesh GET still works (sidecars do mTLS automatically) -> $(mesh http://productpage:9080/productpage)   (expect 200)"
OUT="$(kubectl -n default run plaincurl --image=curlimages/curl:latest --restart=Never -i --rm --quiet -- \
  curl -s -m 5 -o /dev/null -w '%{http_code}' http://productpage.bookinfo:9080/productpage 2>/dev/null || echo BLOCKED)"
info "OUTSIDE the mesh (plain pod, no sidecar) -> ${OUT}   (expect BLOCKED/000 — no mTLS)"

step "3) authorization: allow only GET on productpage"
kubectl apply -f manifests/authz-get-only.yaml
sleep 6
info "in-mesh GET  productpage -> $(mesh http://productpage:9080/productpage)        (expect 200)"
info "in-mesh POST productpage -> $(mesh -X POST http://productpage:9080/productpage)  (expect 403 — denied)"

title "Done"
info "Reach the app through the gateway:"
info "  kubectl -n istio-system port-forward svc/istio-ingressgateway 8080:80"
info "  curl http://localhost:8080/productpage"
info "Clean up:  ./cleanup.sh"
