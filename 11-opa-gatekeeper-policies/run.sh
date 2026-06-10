#!/usr/bin/env bash
#
# Chapter 11 — Policies with OPA Gatekeeper.
# RBAC controls WHO can act. Gatekeeper controls WHAT may be created — it checks
# every new object against your rules and rejects ones that break them.

source "$(dirname "$0")/../lib.sh"
cd "$(dirname "$0")"

need kubectl helm
need_cluster
title "Chapter 11 — OPA Gatekeeper"

step "installing Gatekeeper"
helm repo add gatekeeper https://open-policy-agent.github.io/gatekeeper/charts >/dev/null
helm repo update gatekeeper >/dev/null
helm upgrade --install gatekeeper gatekeeper/gatekeeper -n gatekeeper-system --create-namespace
kubectl -n gatekeeper-system rollout status deploy/gatekeeper-controller-manager --timeout=180s

step "defining the rule type (ConstraintTemplate, written in Rego)"
kubectl apply -f manifests/template.yaml
info "waiting for the new rule kind to register..."
kubectl wait --for condition=established crd/k8srequiredlabels.constraints.gatekeeper.sh --timeout=90s

step "turning the rule ON: every Namespace must have an 'owner' label"
kubectl apply -f manifests/constraint.yaml
sleep 12   # give Gatekeeper a moment to start enforcing

step "TEST 1 — a Namespace WITHOUT the label (should be rejected):"
OUT="$(kubectl apply -f manifests/bad-namespace.yaml 2>&1 || true)"
echo "    ${OUT}"

step "TEST 2 — a Namespace WITH the label (should be allowed):"
kubectl apply -f manifests/good-namespace.yaml

title "Done"
info "Gatekeeper also audits EXISTING objects:  kubectl get k8srequiredlabels ns-must-have-owner -o yaml"
info "Clean up:  ./cleanup.sh"
