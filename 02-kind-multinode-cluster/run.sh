#!/usr/bin/env bash
#
# Chapter 2 — create the multi-node KinD cluster the whole course uses.

source "$(dirname "$0")/../lib.sh"
cd "$(dirname "$0")"

need docker kind kubectl
title "Chapter 2 — KinD multi-node cluster"

if kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
  step "cluster '$CLUSTER_NAME' already exists — nothing to do"
else
  step "creating cluster '$CLUSTER_NAME' (1 control-plane + 2 workers)"
  kind create cluster --config cluster-config.yaml --wait 120s
fi

step "the cluster's nodes"
kubectl get nodes -o wide

step "your kubectl context is now"
kubectl config current-context

title "Cluster ready"
info "Everything talks to it through kubectl. Next:"
info "  cd ../04-services-loadbalancing-network-policies && ./run.sh"
info "Want to see the HAProxy load balancer? Read cluster-config-ha.yaml."
