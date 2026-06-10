#!/usr/bin/env bash
source "$(dirname "$0")/../lib.sh"
need kubectl helm
kubectl delete -f manifests/policy.yaml --ignore-not-found
kubectl delete -f manifests/app.yaml --ignore-not-found
helm uninstall kubearmor-operator -n kubearmor >/dev/null 2>&1 || true
kubectl delete namespace kubearmor --ignore-not-found
info "done"
