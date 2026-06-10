#!/usr/bin/env bash
#
# Chapter 13 — Runtime Security with KubeArmor.
# Gatekeeper (Ch 11-12) stops bad pods from being CREATED. KubeArmor stops bad
# actions while a pod is RUNNING — e.g. running a package manager, reading a
# sensitive file, or making a network call it shouldn't.

source "$(dirname "$0")/../lib.sh"
cd "$(dirname "$0")"

need kubectl helm
need_cluster
title "Chapter 13 — Runtime Security with KubeArmor"

step "installing the KubeArmor operator"
helm repo add kubearmor https://kubearmor.github.io/charts >/dev/null
helm repo update kubearmor >/dev/null
helm upgrade --install kubearmor-operator kubearmor/kubearmor-operator -n kubearmor --create-namespace
kubectl -n kubearmor rollout status deploy/kubearmor-operator --timeout=180s

step "applying the sample config (tells the operator to deploy KubeArmor)"
kubectl apply -f https://raw.githubusercontent.com/kubearmor/KubeArmor/main/pkg/KubeArmorOperator/config/samples/sample-config.yml
info "waiting for KubeArmor to come up..."
sleep 25
kubectl -n kubearmor wait --for=condition=Ready pods --all --timeout=300s || true

step "deploying a target app"
kubectl apply -f manifests/app.yaml
kubectl -n ch13 rollout status deploy/web --timeout=120s

step "BEFORE the policy — the app can run apk:"
kubectl -n ch13 exec deploy/web -- apk --version 2>&1 | head -1 || true

step "applying the runtime policy: block the package manager"
kubectl apply -f manifests/policy.yaml
sleep 8

step "AFTER the policy — try again (should be blocked):"
OUT="$(kubectl -n ch13 exec deploy/web -- apk --version 2>&1 || true)"
echo "    ${OUT}"

title "Done"
info "If you saw 'Permission denied', enforcement is active. 🎉"
warn "If apk still ran, your host lacks an enforcing LSM (common on Docker Desktop"
warn "for Mac/Windows). KubeArmor then runs in OBSERVE mode — see violations with:"
info "  kubectl -n kubearmor logs -l kubearmor-app=kubearmor-relay | grep -i apk"
info "Enforcement is reliable on Linux hosts with AppArmor or BPF-LSM."
info "Clean up:  ./cleanup.sh"
