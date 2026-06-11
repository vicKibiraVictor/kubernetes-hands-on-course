#!/usr/bin/env bash
#
# Chapter 4 — Services, Load Balancing & Network Policies.
#   - MetalLB     : gives LoadBalancer services a real IP (Layer 4)
#   - ingress-nginx: routes HTTP by hostname            (Layer 7)
#   - kube-network-policies: actually enforces NetworkPolicies on kindnet
# Then deploys a sample app and proves each piece works.

source "$(dirname "$0")/../lib.sh"
cd "$(dirname "$0")"

need kubectl docker curl
need_cluster
title "Chapter 4 — Services, Load Balancing & Network Policies"

# small helper: retry a command a few times (webhooks need a moment to wake up)
retry() { local n=0; until "$@"; do n=$((n+1)); [ "$n" -ge 6 ] && return 1; sleep 5; done; }

# ── MetalLB (Layer 4 load balancer) ───────────────────────────────────────
step "installing MetalLB"
MLB="$(latest_tag metallb/metallb)"; info "version ${MLB}"
kubectl apply -f "https://raw.githubusercontent.com/metallb/metallb/${MLB}/config/manifests/metallb-native.yaml"
kubectl -n metallb-system rollout status deploy/controller --timeout=180s

step "giving MetalLB an IP range from the kind network"
# The kind network is often dual-stack (IPv4 + IPv6). Pick the IPv4 subnet — the
# one that looks like a.b.c.d/n — not the IPv6 one (fc00:...).
SUBNET="$(docker network inspect kind -f '{{range .IPAM.Config}}{{println .Subnet}}{{end}}' \
  | grep -E '^[0-9]+(\.[0-9]+){3}/' | head -1)"
[ -n "$SUBNET" ] || die "couldn't find an IPv4 subnet on the 'kind' docker network"
PREFIX="$(echo "$SUBNET" | cut -d. -f1-2)"                                        # e.g. 172.18
info "kind subnet ${SUBNET} -> pool ${PREFIX}.255.200-${PREFIX}.255.250"
# Write to a file first: the apply may need a retry while MetalLB's webhook wakes
# up, and a here-doc piped straight into 'retry' would be empty on the 2nd try.
POOL_FILE="$(mktemp)"
cat > "$POOL_FILE" <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: course-pool
  namespace: metallb-system
spec:
  addresses:
    - "${PREFIX}.255.200-${PREFIX}.255.250"
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: course-l2
  namespace: metallb-system
spec:
  ipAddressPools: [course-pool]
EOF
retry kubectl apply -f "$POOL_FILE"
rm -f "$POOL_FILE"

# ── ingress-nginx (Layer 7) ───────────────────────────────────────────────
step "installing the NGINX ingress controller"
ING="$(curl -fsSL https://api.github.com/repos/kubernetes/ingress-nginx/releases | sed -n 's/.*"tag_name": *"\(controller-[^"]*\)".*/\1/p' | head -1)"
info "version ${ING}"
kubectl apply -f "https://raw.githubusercontent.com/kubernetes/ingress-nginx/${ING}/deploy/static/provider/kind/deploy.yaml"
kubectl -n ingress-nginx rollout status deploy/ingress-nginx-controller --timeout=180s

# ── NetworkPolicy enforcement (kindnet doesn't do it alone) ────────────────
step "installing kube-network-policies (so NetworkPolicies are enforced)"
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/kube-network-policies/main/install.yaml
# On small/loaded clusters the API watch can blip ("client connection lost").
# That's harmless — keep going; the policy test will still work once pods are up.
kubectl -n kube-system rollout status ds/kube-network-policies --timeout=300s \
  || warn "kube-network-policies still rolling out — continuing (re-run if TEST 3 misbehaves)"

# ── the sample app ────────────────────────────────────────────────────────
step "deploying the sample web app + its Services"
kubectl apply -f manifests/web.yaml
kubectl apply -f manifests/ingress.yaml
kubectl -n ch4 rollout status deploy/web --timeout=120s

# ── prove: LoadBalancer ───────────────────────────────────────────────────
step "TEST 1 — LoadBalancer service got an external IP"
LB=""; for i in $(seq 1 20); do
  LB="$(kubectl -n ch4 get svc web-lb -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
  [ -n "$LB" ] && break; sleep 3
done
kubectl -n ch4 get svc web-lb
info "reaching ${LB} from inside the cluster:"
kubectl -n ch4 run lbtest --image=curlimages/curl:latest --restart=Never -i --rm --quiet -- \
  curl -s -m 5 -o /dev/null -w "  http code: %{http_code}\n" "http://${LB}" 2>/dev/null || warn "LB test skipped"

# ── prove: Ingress ────────────────────────────────────────────────────────
step "TEST 2 — Ingress routes web.local -> the app (kind maps it to localhost)"
sleep 3
CODE="$(curl -s -m 5 -o /dev/null -w '%{http_code}' -H 'Host: web.local' http://localhost || echo '000')"
info "curl -H 'Host: web.local' http://localhost  ->  ${CODE}  (200 = success)"

# ── prove: NetworkPolicy ──────────────────────────────────────────────────
step "TEST 3 — applying NetworkPolicies, then testing who can reach web"
kubectl apply -f manifests/netpol.yaml
sleep 5
ALLOWED="$(kubectl -n ch4 run client --image=curlimages/curl:latest --labels='role=client' --restart=Never -i --rm --quiet -- \
  sh -c 'curl -s -m 5 -o /dev/null -w "%{http_code}" http://web-clusterip || echo BLOCKED' 2>/dev/null | tail -1)"
BLOCKED="$(kubectl -n ch4 run stranger --image=curlimages/curl:latest --restart=Never -i --rm --quiet -- \
  sh -c 'curl -s -m 5 -o /dev/null -w "%{http_code}" http://web-clusterip || echo BLOCKED' 2>/dev/null | tail -1)"
info "pod labelled role=client  -> ${ALLOWED}   (expect 200)"
info "pod with no label         -> ${BLOCKED}   (expect BLOCKED)"

title "Done"
info "Open the app in your browser:  curl -H 'Host: web.local' http://localhost"
info "Clean up:  ./cleanup.sh"
