#!/usr/bin/env bash
#
# Chapter 10 — A Secured Kubernetes Dashboard.
# The Dashboard is a web UI for the cluster. The danger is giving it too much
# power. We install it and create a READ-ONLY login — the safe way.

set -e

source "$(dirname "$0")/../lib.sh"
cd "$(dirname "$0")"

need kubectl helm
need_cluster
title "Chapter 10 — Secured Kubernetes Dashboard"

step "adding Kubernetes Dashboard Helm repo"

# Remove old/broken repo if present
helm repo remove kubernetes-dashboard 2>/dev/null || true

# Add the working retired repo
helm repo add kubernetes-dashboard https://kubernetes-retired.github.io/dashboard

step "updating Helm repos"
helm repo update

step "installing the Kubernetes Dashboard"
helm upgrade --install kubernetes-dashboard \
  kubernetes-dashboard/kubernetes-dashboard \
  -n kubernetes-dashboard \
  --create-namespace

step "waiting for the dashboard pods to be ready"
kubectl -n kubernetes-dashboard wait \
  --for=condition=Ready pods \
  --all \
  --timeout=240s || true

step "creating a READ-ONLY login (ServiceAccount 'viewer' bound to the built-in 'view' role)"
kubectl apply -f manifests/viewer.yaml

step "minting a login token for 'viewer'"
TOKEN="$(kubectl -n kubernetes-dashboard create token viewer --duration=1h)"

title "Dashboard ready"
info "1) start the proxy (leave it running in this terminal):"
info "     kubectl -n kubernetes-dashboard port-forward svc/kubernetes-dashboard-kong-proxy 8443:443"
info "2) open: https://localhost:8443"
info "3) choose 'Token' and paste:"
echo
echo "$TOKEN"
echo
info "This login can only VIEW. Clean up: ./cleanup.sh"
