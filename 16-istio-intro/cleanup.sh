#!/usr/bin/env bash
source "$(dirname "$0")/../lib.sh"
need kubectl
ISTIO_DIR="$(ls -d istio-*/ 2>/dev/null | head -1)"
warn "Chapter 17 builds on this Istio install — only clean up if you're done with both."
kubectl delete namespace bookinfo --ignore-not-found
[ -n "${ISTIO_DIR}" ] && kubectl delete -f "${ISTIO_DIR}samples/addons" --ignore-not-found 2>/dev/null || true
command -v istioctl >/dev/null 2>&1 && istioctl uninstall --purge -y 2>/dev/null || true
kubectl delete namespace istio-system --ignore-not-found
info "done"
