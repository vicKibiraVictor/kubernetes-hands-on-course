#!/usr/bin/env bash
source "$(dirname "$0")/../lib.sh"
need kubectl
step "removing external-dns + sample"
kubectl delete -f manifests/sample.yaml --ignore-not-found
kubectl delete clusterrole external-dns-ch5 --ignore-not-found
kubectl delete clusterrolebinding external-dns-ch5 --ignore-not-found
kubectl delete namespace ch5 --ignore-not-found
info "done"
