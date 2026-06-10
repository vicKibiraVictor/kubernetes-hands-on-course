#!/usr/bin/env bash
source "$(dirname "$0")/../lib.sh"
need docker
step "removing container, image and demo volume"
docker rm -f hello-docker >/dev/null 2>&1 || true
docker rmi hello-docker:1.0 >/dev/null 2>&1 || true
docker volume rm demo-data >/dev/null 2>&1 || true
info "done"
