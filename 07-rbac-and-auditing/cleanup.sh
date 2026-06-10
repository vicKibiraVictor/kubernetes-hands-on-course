#!/usr/bin/env bash
source "$(dirname "$0")/../lib.sh"
need kubectl
kubectl delete -f manifests/rbac.yaml --ignore-not-found
info "removed jane's RBAC and the dev namespace"
