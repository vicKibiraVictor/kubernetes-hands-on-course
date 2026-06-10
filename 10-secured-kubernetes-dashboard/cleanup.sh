#!/usr/bin/env bash
source "$(dirname "$0")/../lib.sh"
need kubectl helm
kubectl delete -f manifests/viewer.yaml --ignore-not-found
helm uninstall kubernetes-dashboard -n kubernetes-dashboard >/dev/null 2>&1 || true
kubectl delete namespace kubernetes-dashboard --ignore-not-found
info "done"
