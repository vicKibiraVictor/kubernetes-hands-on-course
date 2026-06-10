#!/usr/bin/env bash
source "$(dirname "$0")/../lib.sh"
need kubectl
step "deleting the virtual cluster"
command -v vcluster >/dev/null 2>&1 && vcluster delete team-a -n team-a 2>/dev/null || true
kubectl delete namespace team-a --ignore-not-found
info "done"
