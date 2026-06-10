#!/usr/bin/env bash
source "$(dirname "$0")/../lib.sh"
need kubectl helm
helm uninstall harbor -n harbor >/dev/null 2>&1 || true
kubectl delete namespace harbor --ignore-not-found
info "done"
