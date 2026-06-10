#!/usr/bin/env bash
#
# Chapter 6 — Authentication: "who are you?"
# We create a real user, "jane", using a client certificate signed by the
# cluster. Then we prove the cluster recognises her. (Authorisation — what she's
# ALLOWED to do — is the next chapter.)

source "$(dirname "$0")/../lib.sh"
cd "$(dirname "$0")"

need kubectl openssl
need_cluster
title "Chapter 6 — Authentication"

step "1) create a private key + certificate request for user 'jane' (group: developers)"
openssl genrsa -out jane.key 2048 2>/dev/null
openssl req -new -key jane.key -out jane.csr -subj "/CN=jane/O=developers"

step "2) ask the cluster to sign it (the CertificateSigningRequest API)"
kubectl delete csr jane --ignore-not-found >/dev/null 2>&1 || true
kubectl apply -f - <<EOF
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: jane
spec:
  request: $(base64 -w0 jane.csr 2>/dev/null || base64 jane.csr | tr -d '\n')
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 86400
  usages: ["client auth"]
EOF

step "3) approve the request (you, the admin, vouch for her)"
kubectl certificate approve jane
kubectl get csr jane

step "4) collect her signed certificate + build her kubeconfig"
kubectl get csr jane -o jsonpath='{.status.certificate}' | base64 -d > jane.crt
SERVER="$(kubectl config view --minify --raw -o jsonpath='{.clusters[0].cluster.server}')"
kubectl config view --minify --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d > ca.crt
kubectl --kubeconfig=jane.kubeconfig config set-cluster "$CLUSTER_NAME" --server="$SERVER" --certificate-authority=ca.crt --embed-certs=true >/dev/null
kubectl --kubeconfig=jane.kubeconfig config set-credentials jane --client-certificate=jane.crt --client-key=jane.key --embed-certs=true >/dev/null
kubectl --kubeconfig=jane.kubeconfig config set-context jane --cluster="$CLUSTER_NAME" --user=jane >/dev/null
kubectl --kubeconfig=jane.kubeconfig config use-context jane >/dev/null

step "5) TEST — does the cluster know who she is?"
kubectl --kubeconfig=jane.kubeconfig auth whoami || warn "auth whoami needs a recent kubectl"

step "6) ...but can she do anything yet?"
OUT="$(kubectl --kubeconfig=jane.kubeconfig get pods 2>&1 || true)"
info "kubectl get pods (as jane) -> ${OUT}"
info "She is authenticated, but NOT authorised. We fix that in Chapter 7 (RBAC)."

title "Done"
info "Her kubeconfig is saved as ./jane.kubeconfig (used again in Chapter 7)."
info "Clean up:  ./cleanup.sh"
