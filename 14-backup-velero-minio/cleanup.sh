#!/usr/bin/env bash
source "$(dirname "$0")/../lib.sh"
need kubectl
kubectl delete namespace demo-app --ignore-not-found
command -v velero >/dev/null 2>&1 && velero uninstall --force 2>/dev/null || true
kubectl delete -f manifests/minio.yaml --ignore-not-found
kubectl delete namespace velero --ignore-not-found
rm -f credentials-velero
info "done"
