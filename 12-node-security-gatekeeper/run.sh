#!/usr/bin/env bash
#
# Chapter 12 — Node Security with Gatekeeper.
# Uses the Gatekeeper from Chapter 11 to block the two pod settings that most
# often let an attacker escape a container and take over the node.

source "$(dirname "$0")/../lib.sh"
cd "$(dirname "$0")"

need kubectl
need_cluster
title "Chapter 12 — Node Security with Gatekeeper"

kubectl get deploy -n gatekeeper-system gatekeeper-controller-manager >/dev/null 2>&1 \
  || die "Gatekeeper not found. Run Chapter 11 first (it installs Gatekeeper)."

step "defining the rules: block privileged containers and hostPath volumes"
kubectl apply -f manifests/templates.yaml
kubectl wait --for condition=established crd/k8sblockprivileged.constraints.gatekeeper.sh --timeout=90s
kubectl wait --for condition=established crd/k8sblockhostpath.constraints.gatekeeper.sh --timeout=90s

step "turning the rules on"
kubectl apply -f manifests/constraints.yaml
sleep 12

step "TEST 1 — privileged pod (should be rejected):"
echo "    $(kubectl apply -f manifests/bad-privileged.yaml 2>&1 || true)"

step "TEST 2 — hostPath pod (should be rejected):"
echo "    $(kubectl apply -f manifests/bad-hostpath.yaml 2>&1 || true)"

step "TEST 3 — a normal pod (should be allowed):"
kubectl apply -f manifests/good-pod.yaml
kubectl wait --for=condition=Ready pod/good-pod --timeout=90s || true

title "Done"
info "Same idea scales to: no root, no hostNetwork, only approved registries, etc."
info "Clean up:  ./cleanup.sh"
