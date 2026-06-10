#!/usr/bin/env bash
#
# Chapter 18 — Your own container registry with Harbor.
# Harbor is a private registry: it stores your images, organises them into
# projects, scans them for vulnerabilities, and controls who can pull/push.

source "$(dirname "$0")/../lib.sh"
cd "$(dirname "$0")"

need kubectl helm curl
need_cluster
title "Chapter 18 — Harbor image registry"
warn "Harbor has several components — give Docker a bit of room and a few minutes."

step "installing Harbor (HTTP, no persistence — for learning)"
helm repo add harbor https://helm.goharbor.io >/dev/null
helm repo update harbor >/dev/null
helm upgrade --install harbor harbor/harbor -n harbor --create-namespace \
  --set expose.type=clusterIP \
  --set expose.tls.enabled=false \
  --set externalURL=http://localhost:8080 \
  --set harborAdminPassword=Harbor12345 \
  --set persistence.enabled=false \
  --set trivy.enabled=false

step "waiting for Harbor (core + portal)"
kubectl -n harbor rollout status deploy/harbor-core --timeout=300s
kubectl -n harbor rollout status deploy/harbor-portal --timeout=300s

step "creating a project called 'course-demo' (via the Harbor API)"
kubectl -n harbor port-forward svc/harbor 8080:80 >/dev/null 2>&1 &
PF=$!; sleep 6
curl -s -u admin:Harbor12345 -X POST http://localhost:8080/api/v2.0/projects \
  -H 'Content-Type: application/json' \
  -d '{"project_name":"course-demo","metadata":{"public":"true"}}' \
  -o /dev/null -w "    create project -> HTTP %{http_code}  (201 created, 409 already exists)\n" || true
kill "$PF" 2>/dev/null || true

title "Harbor is ready"
info "Open the UI:"
info "  kubectl -n harbor port-forward svc/harbor 8080:80"
info "  http://localhost:8080   (login: admin / Harbor12345)"
echo
info "Push an image into your project (keep the port-forward running):"
info "  docker pull nginx:alpine"
info "  docker tag nginx:alpine localhost:8080/course-demo/nginx:1.0"
info "  docker login localhost:8080 -u admin -p Harbor12345"
info "  docker push localhost:8080/course-demo/nginx:1.0"
info "(Docker trusts 'localhost' registries over HTTP automatically — no extra config.)"
info "Clean up:  ./cleanup.sh"
