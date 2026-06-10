#!/usr/bin/env bash
#
# Chapter 9 — Multitenancy with vCluster.
# A vCluster is a fully working Kubernetes cluster that runs *inside* a namespace
# of your real cluster. Each team gets their own "cluster" (own API server, own
# CRDs, own admin rights) without the cost of a separate real cluster.

source "$(dirname "$0")/../lib.sh"
cd "$(dirname "$0")"

need kubectl
need_cluster
title "Chapter 9 — Multitenancy with vCluster"

# install the vcluster CLI if it's missing
if ! command -v vcluster >/dev/null 2>&1; then
  step "installing the vcluster CLI"
  OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
  ARCH="$(uname -m)"; [ "$ARCH" = "x86_64" ] && ARCH="amd64"; [ "$ARCH" = "aarch64" ] && ARCH="arm64"
  curl -fsSL -o vcluster "https://github.com/loft-sh/vcluster/releases/latest/download/vcluster-${OS}-${ARCH}"
  chmod +x vcluster; SUDO=""; [ -w /usr/local/bin ] || SUDO="sudo"; $SUDO mv vcluster /usr/local/bin/
fi
info "vcluster $(vcluster version 2>/dev/null | head -1)"

step "create a virtual cluster 'team-a' (lives in namespace team-a on the host)"
if vcluster list 2>/dev/null | grep -q "team-a"; then
  info "vcluster 'team-a' already exists — reusing it"
else
  vcluster create team-a --namespace team-a --connect=false
fi

step "run an app INSIDE the virtual cluster"
vcluster connect team-a -n team-a -- kubectl create deployment hello --image=nginx:alpine 2>/dev/null || true
vcluster connect team-a -n team-a -- kubectl rollout status deploy/hello --timeout=90s

step "TEST — the virtual cluster sees its Deployment:"
vcluster connect team-a -n team-a -- kubectl get deploy

step "TEST — the HOST cluster does NOT see that Deployment (it's isolated):"
info "host 'kubectl -n team-a get deploy' ->"
kubectl -n team-a get deploy 2>/dev/null || true
info "(the host only runs vcluster's own pods; the tenant's objects stay inside)"

title "Done"
info "Enter the tenant any time:  vcluster connect team-a -n team-a"
info "Leave it:                   vcluster disconnect"
info "Clean up:  ./cleanup.sh"
