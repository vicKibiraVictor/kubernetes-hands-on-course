#!/usr/bin/env bash
#
# Chapter 7 — RBAC: "what are you allowed to do?"
# We give jane read-only access to pods in ONE namespace (dev), then prove the
# limits: she can read there, but can't delete, and can't touch other namespaces.

source "$(dirname "$0")/../lib.sh"
cd "$(dirname "$0")"

need kubectl
need_cluster
title "Chapter 7 — RBAC & Auditing"

step "grant jane read-only pods in namespace 'dev'"
kubectl apply -f manifests/rbac.yaml

step "put a pod in 'dev' so there's something to read"
kubectl -n dev create deployment demo --image=nginx:alpine --dry-run=client -o yaml | kubectl apply -f -
kubectl -n dev rollout status deploy/demo --timeout=90s

# 'kubectl auth can-i ... --as=jane' asks the cluster on jane's behalf (impersonation).
ask() { kubectl auth can-i "$1" "$2" -n "$3" --as=jane --as-group=developers 2>/dev/null || true; }

step "TEST — what can jane do?"
info "list pods   in dev     -> $(ask list pods dev)        (expect yes)"
info "get  pods   in dev     -> $(ask get pods dev)         (expect yes)"
info "delete pods in dev     -> $(ask delete pods dev)      (expect no)"
info "list pods   in default -> $(ask list pods default)    (expect no — her Role is only in 'dev')"

step "and for real, as jane:"
kubectl --as=jane --as-group=developers -n dev get pods

title "Done"
info "RBAC is additive: start with nothing, grant the few verbs each role needs."
info "Auditing (who did what) — see the README; it needs a one-time cluster tweak."
info "Clean up:  ./cleanup.sh"
