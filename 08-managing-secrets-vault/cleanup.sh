#!/usr/bin/env bash
source "$(dirname "$0")/../lib.sh"
need kubectl helm
step "removing ESO objects, Vault and ESO"
kubectl delete -f manifests/external-secret.yaml --ignore-not-found
kubectl delete namespace app --ignore-not-found
helm uninstall external-secrets -n external-secrets >/dev/null 2>&1 || true
helm uninstall vault -n vault >/dev/null 2>&1 || true
kubectl delete namespace external-secrets vault --ignore-not-found
info "done"
