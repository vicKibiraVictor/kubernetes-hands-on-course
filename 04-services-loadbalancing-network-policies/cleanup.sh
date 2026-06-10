#!/usr/bin/env bash
source "$(dirname "$0")/../lib.sh"
need kubectl
step "removing the sample app (leaving MetalLB + ingress for later chapters)"
kubectl delete -f manifests/netpol.yaml --ignore-not-found
kubectl delete -f manifests/ingress.yaml --ignore-not-found
kubectl delete -f manifests/web.yaml --ignore-not-found
info "done. (MetalLB and ingress-nginx are kept — other chapters use them.)"
