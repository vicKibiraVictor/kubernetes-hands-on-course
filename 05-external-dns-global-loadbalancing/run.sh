#!/usr/bin/env bash
#
# Chapter 5 — External DNS.
# external-dns watches Services/Ingresses and creates DNS records for them.
# Real use needs a DNS provider (Route53, Cloudflare, ...) with credentials.
# To keep this account-free and reliable, we use the "inmemory" provider: it
# does everything except call a real DNS API — and logs the records it WOULD make.

source "$(dirname "$0")/../lib.sh"
cd "$(dirname "$0")"

need kubectl
need_cluster
title "Chapter 5 — External DNS"

step "deploying external-dns (inmemory provider)"
ED="$(latest_tag kubernetes-sigs/external-dns)"; info "version ${ED}"
kubectl create namespace ch5 --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata: { name: external-dns, namespace: ch5 }
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata: { name: external-dns-ch5 }
rules:
  - apiGroups: [""]
    resources: ["services","endpoints","pods","nodes"]
    verbs: ["get","watch","list"]
  - apiGroups: ["networking.k8s.io"]
    resources: ["ingresses"]
    verbs: ["get","watch","list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata: { name: external-dns-ch5 }
roleRef: { apiGroup: rbac.authorization.k8s.io, kind: ClusterRole, name: external-dns-ch5 }
subjects:
  - kind: ServiceAccount
    name: external-dns
    namespace: ch5
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: external-dns, namespace: ch5 }
spec:
  selector: { matchLabels: { app: external-dns } }
  template:
    metadata: { labels: { app: external-dns } }
    spec:
      serviceAccountName: external-dns
      containers:
        - name: external-dns
          image: registry.k8s.io/external-dns/external-dns:${ED}
          args:
            - --source=service
            - --source=ingress
            - --provider=inmemory
            - --registry=noop
            - --policy=upsert-only
            - --log-level=debug
            - --interval=10s
EOF
kubectl -n ch5 rollout status deploy/external-dns --timeout=120s

step "deploying a sample service that requests the name shop.example.com"
kubectl apply -f manifests/sample.yaml

step "waiting for external-dns to notice it..."
sleep 20

step "RESULT — records external-dns decided to create:"
kubectl -n ch5 logs deploy/external-dns | grep -iE "shop.example.com|CREATE|record" | tail -n 10 \
  || warn "no matching log lines yet — give it another few seconds and re-check the logs"

title "Done"
info "In production you'd swap --provider=inmemory for aws/cloudflare/google + credentials,"
info "and external-dns would create these records in your real DNS zone automatically."
info "Global load balancing across clusters (K8GB) — see the README (optional, needs 2 clusters)."
info "Clean up:  ./cleanup.sh"
