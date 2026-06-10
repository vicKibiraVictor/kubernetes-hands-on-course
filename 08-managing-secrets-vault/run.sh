#!/usr/bin/env bash
#
# Chapter 8 — Managing Secrets with Vault + External Secrets Operator (ESO).
# The real secret lives in Vault. ESO copies it into a normal Kubernetes Secret
# that your apps use — so the source of truth stays in Vault.

source "$(dirname "$0")/../lib.sh"
cd "$(dirname "$0")"

need kubectl helm
need_cluster
title "Chapter 8 — Managing Secrets with Vault"

# ── Vault (dev mode: unsealed, root token = 'root', for learning only) ─────
step "installing Vault (dev mode)"
helm repo add hashicorp https://helm.releases.hashicorp.com >/dev/null
helm repo update hashicorp >/dev/null
helm upgrade --install vault hashicorp/vault -n vault --create-namespace \
  --set "server.dev.enabled=true" \
  --set "server.dev.devRootToken=root" \
  --set "injector.enabled=false"
kubectl -n vault rollout status statefulset/vault --timeout=180s 2>/dev/null || \
  kubectl -n vault wait --for=condition=Ready pod/vault-0 --timeout=180s

step "storing a secret in Vault:  secret/demo  (password=s3cr3t)"
kubectl -n vault exec vault-0 -- sh -c \
  'VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=root vault kv put secret/demo username=appuser password=s3cr3t'

# ── External Secrets Operator ─────────────────────────────────────────────
step "installing the External Secrets Operator"
helm repo add external-secrets https://charts.external-secrets.io >/dev/null
helm repo update external-secrets >/dev/null
helm upgrade --install external-secrets external-secrets/external-secrets \
  -n external-secrets --create-namespace --set installCRDs=true
kubectl -n external-secrets rollout status deploy/external-secrets --timeout=180s

# ── Wire Vault -> ESO -> a Kubernetes Secret ──────────────────────────────
step "connecting ESO to Vault and asking it to sync secret/demo"
kubectl create namespace app --dry-run=client -o yaml | kubectl apply -f -
kubectl -n app create secret generic vault-token --from-literal=token=root \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f manifests/external-secret.yaml

step "waiting for ESO to create the Kubernetes Secret..."
kubectl -n app wait --for=condition=Ready externalsecret/app-secret --timeout=120s || true
sleep 3

step "RESULT — the Secret ESO created, decoded:"
VAL="$(kubectl -n app get secret app-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || true)"
info "app-secret.password = ${VAL:-<not synced yet>}   (expect: s3cr3t)"

title "Done"
info "Change it in Vault and ESO re-syncs within 15s:"
info "  kubectl -n vault exec vault-0 -- sh -c 'VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=root vault kv put secret/demo password=NEW'"
info "Clean up:  ./cleanup.sh"
