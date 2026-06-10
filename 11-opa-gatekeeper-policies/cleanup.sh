#!/usr/bin/env bash
source "$(dirname "$0")/../lib.sh"
need kubectl helm
kubectl delete namespace has-owner --ignore-not-found
kubectl delete -f manifests/constraint.yaml --ignore-not-found
kubectl delete -f manifests/template.yaml --ignore-not-found
# Chapter 12 also uses Gatekeeper — only uninstall if you're done with both.
warn "leaving Gatekeeper installed (Chapter 12 needs it). To remove it fully:"
info "  helm uninstall gatekeeper -n gatekeeper-system && kubectl delete ns gatekeeper-system"
