#!/usr/bin/env bash
source "$(dirname "$0")/../lib.sh"
need kubectl
kubectl delete csr jane --ignore-not-found
rm -f jane.key jane.csr jane.crt ca.crt jane.kubeconfig
info "removed jane's certificate request and local files"
