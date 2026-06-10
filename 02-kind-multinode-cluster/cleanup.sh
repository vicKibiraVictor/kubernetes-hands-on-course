#!/usr/bin/env bash
source "$(dirname "$0")/../lib.sh"
need kind
warn "this deletes the whole course cluster '$CLUSTER_NAME'"
kind delete cluster --name "$CLUSTER_NAME"
info "done"
