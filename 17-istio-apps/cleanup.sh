#!/usr/bin/env bash
source "$(dirname "$0")/../lib.sh"
need kubectl
kubectl delete -f manifests/authz-get-only.yaml --ignore-not-found
kubectl delete -f manifests/peer-auth-strict.yaml --ignore-not-found
kubectl delete -f manifests/gateway.yaml --ignore-not-found
kubectl delete -f manifests/meshclient.yaml --ignore-not-found
info "removed the gateway, mTLS and authz rules (Bookinfo + Istio stay — see Ch 16 cleanup)"
