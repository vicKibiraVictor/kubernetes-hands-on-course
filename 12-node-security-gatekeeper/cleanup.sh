#!/usr/bin/env bash
source "$(dirname "$0")/../lib.sh"
need kubectl
kubectl delete pod good-pod --ignore-not-found
kubectl delete -f manifests/constraints.yaml --ignore-not-found
kubectl delete -f manifests/templates.yaml --ignore-not-found
info "removed the node-security policies (Gatekeeper itself stays — see Ch 11 cleanup)"
