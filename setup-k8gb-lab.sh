#!/usr/bin/env bash
# setup-k8gb-lab.sh
# Generates the full k8gb-multicluster project — folders + all files
# Hardened for GitHub Codespaces / cgroup v2 environments
# Usage: bash setup-k8gb-lab.sh

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

PROJECT="k8gb-multicluster"

echo -e "${CYAN}=========================================================${NC}"
echo -e "${CYAN}  k8gb Multi-Cluster Lab — Project Generator             ${NC}"
echo -e "${CYAN}=========================================================${NC}"
echo ""

# ── folder structure ──────────────────────────────────────────────────────────
echo -e "${YELLOW}>>> Creating folder structure...${NC}"
mkdir -p "$PROJECT/clusters"
mkdir -p "$PROJECT/manifests"
mkdir -p "$PROJECT/scripts"
echo -e "${GREEN}  ✓ Folders created${NC}"
echo ""

# ── README ────────────────────────────────────────────────────────────────────
echo -e "${YELLOW}>>> Writing README.md...${NC}"
cat << 'EOF' > "$PROJECT/README.md"
# k8gb Multi-Cluster Local Lab

Simulates a global Kubernetes load balancer across 3 "cloud regions"
using [kind](https://kind.sigs.k8s.io/) and [k8gb](https://www.k8gb.io/).
Hardened for GitHub Codespaces and cgroup v2 environments.

## Simulated Regions

| Cluster      | Simulated Region          |
|--------------|---------------------------|
| `cluster-us` | US  (GCP us-central1)     |
| `cluster-eu` | EU  (GCP europe-west1)    |
| `cluster-ap` | AP  (GCP asia-east1)      |

## Quick Start

```bash
chmod +x scripts/*.sh
./scripts/01-create-clusters.sh
./scripts/02-install-k8gb.sh
./scripts/03-deploy-app.sh
./scripts/04-apply-gslb.sh
./scripts/05-verify.sh
./scripts/06-failover-demo.sh
./scripts/99-cleanup.sh
```

## Prerequisites

- `kind` >= 0.20.0
- `kubectl`
- `helm` >= 3.x
EOF
echo -e "${GREEN}  ✓ README.md${NC}"

# ── .gitignore ────────────────────────────────────────────────────────────────
cat << 'EOF' > "$PROJECT/.gitignore"
kubeconfig
*.kubeconfig
.vscode/
.idea/
.DS_Store
*.log
*.tmp
EOF
echo -e "${GREEN}  ✓ .gitignore${NC}"

# ══════════════════════════════════════════════════════════════════════════════
# CLUSTER CONFIGS
#
# Key decisions for Codespaces stability:
#
# 1. Single-node clusters (control-plane only, no separate workers)
#    - Workers are extra Docker containers; Codespaces has limited memory
#    - control-plane node CAN schedule workloads (taint is removed automatically by kind)
#    - 3 single-node clusters = 3 containers vs 9 containers with workers
#
# 2. Pinned node image: kindest/node:v1.31.0
#    - v1.31.0 has reliable cgroup v2 support
#    - v1.37.0 (kind's default) has a known "Reached target Multi-User System"
#      detection bug on some cgroup v2 hosts (GitHub Codespaces is cgroup v2)
#
# 3. Unique pod/service subnets per cluster
#    - Prevents IP conflicts when k8gb peers the clusters for health checking
# ══════════════════════════════════════════════════════════════════════════════
echo -e "${YELLOW}>>> Writing cluster configs...${NC}"

cat << 'EOF' > "$PROJECT/clusters/cluster-us.yaml"
# kind cluster config — simulated US region (GCP us-central1)
# Single-node: control-plane only — stable on Codespaces (cgroup v2)
# control-plane can run workloads; kind removes the NoSchedule taint automatically
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4

# pin to v1.31.0 — reliable cgroup v2 support, avoids v1.37 detection bug
nodes:
  - role: control-plane
    image: kindest/node:v1.31.0

networking:
  # unique subnets per cluster — prevents IP conflicts when k8gb peers them
  podSubnet: "10.1.0.0/16"
  serviceSubnet: "10.101.0.0/16"
EOF
echo -e "${GREEN}  ✓ clusters/cluster-us.yaml${NC}"

cat << 'EOF' > "$PROJECT/clusters/cluster-eu.yaml"
# kind cluster config — simulated EU region (GCP europe-west1)
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    image: kindest/node:v1.31.0
networking:
  podSubnet: "10.2.0.0/16"
  serviceSubnet: "10.102.0.0/16"
EOF
echo -e "${GREEN}  ✓ clusters/cluster-eu.yaml${NC}"

cat << 'EOF' > "$PROJECT/clusters/cluster-ap.yaml"
# kind cluster config — simulated AP region (GCP asia-east1)
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    image: kindest/node:v1.31.0
networking:
  podSubnet: "10.3.0.0/16"
  serviceSubnet: "10.103.0.0/16"
EOF
echo -e "${GREEN}  ✓ clusters/cluster-ap.yaml${NC}"

# ══════════════════════════════════════════════════════════════════════════════
# MANIFESTS
# ══════════════════════════════════════════════════════════════════════════════
echo -e "${YELLOW}>>> Writing manifests...${NC}"

cat << 'EOF' > "$PROJECT/manifests/deployment.yaml"
# nginx Deployment — test workload k8gb will load-balance globally
# Same manifest applied on all 3 clusters
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello-app
  namespace: default
  labels:
    app: hello-app
spec:
  replicas: 1             # 1 replica per cluster — keeps resource usage low on Codespaces
  selector:
    matchLabels:
      app: hello-app
  template:
    metadata:
      labels:
        app: hello-app
    spec:
      containers:
        - name: hello-app
          image: nginx:stable-alpine   # smallest nginx image — fast pull
          ports:
            - containerPort: 80
          resources:
            requests:
              cpu: "50m"
              memory: "32Mi"
            limits:
              cpu: "100m"
              memory: "64Mi"
EOF
echo -e "${GREEN}  ✓ manifests/deployment.yaml${NC}"

cat << 'EOF' > "$PROJECT/manifests/service.yaml"
# ClusterIP Service — k8gb Gslb references this service by name
apiVersion: v1
kind: Service
metadata:
  name: hello-app
  namespace: default
spec:
  type: ClusterIP      # internal only — k8gb handles external DNS routing
  selector:
    app: hello-app
  ports:
    - name: http
      protocol: TCP
      port: 80
      targetPort: 80
EOF
echo -e "${GREEN}  ✓ manifests/service.yaml${NC}"

cat << 'EOF' > "$PROJECT/manifests/gslb.yaml"
# Gslb — Global Server Load Balancing custom resource
# This is the core k8gb object: defines HOW DNS traffic routes across clusters
# Apply on EVERY cluster after k8gb is installed
apiVersion: k8gb.absa.oss/v1beta1
kind: Gslb
metadata:
  name: hello-gslb
  namespace: default
spec:
  ingress:
    rules:
      - host: hello.example.com   # DNS hostname clients resolve
        http:
          paths:
            - path: /
              pathType: Prefix
              backend:
                service:
                  name: hello-app   # must match service.yaml
                  port:
                    number: 80
  strategy:
    # roundRobin: DNS cycles through IPs of all healthy clusters
    # alternatives: failover (primary + backup), geoip (closest region)
    type: roundRobin

    # clients cache this DNS answer for 30s
    # lower = faster failover detection, more DNS queries
    dnsTtlSeconds: 30

    # cluster must be unreachable this long before k8gb drops it from DNS
    # 300s = 5 min, prevents flapping on brief hiccups
    splitBrainThresholdSeconds: 300
EOF
echo -e "${GREEN}  ✓ manifests/gslb.yaml${NC}"

# ══════════════════════════════════════════════════════════════════════════════
# SCRIPTS
# IMPORTANT: no inline comments after \ line continuations
#            bash parses anything after \ on the same line as part of the command
#            all comments go on their own line ABOVE the thing they describe
# ══════════════════════════════════════════════════════════════════════════════
echo -e "${YELLOW}>>> Writing scripts...${NC}"

# ── 01-create-clusters.sh ─────────────────────────────────────────────────────
cat << 'EOF' > "$PROJECT/scripts/01-create-clusters.sh"
#!/usr/bin/env bash
# 01-create-clusters.sh
# Creates 3 single-node kind clusters: cluster-us, cluster-eu, cluster-ap
# Uses pinned kindest/node:v1.31.0 image — stable on cgroup v2 (Codespaces)
# Single control-plane node per cluster keeps RAM usage low

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

CLUSTERS_DIR="$(dirname "$0")/../clusters"

echo -e "${YELLOW}>>> Creating 3 kind clusters...${NC}"

for region in us eu ap; do
  echo -e "${YELLOW}  Creating cluster-${region}...${NC}"

  # delete if already exists — prevents "cluster already exists" errors on re-runs
  if kind get clusters 2>/dev/null | grep -q "^cluster-${region}$"; then
    echo -e "${RED}  cluster-${region} already exists — deleting first...${NC}"
    kind delete cluster --name "cluster-${region}"
  fi

  # create cluster using its region config (pinned image + unique subnets)
  kind create cluster \
    --name "cluster-${region}" \
    --config "$CLUSTERS_DIR/cluster-${region}.yaml"

  echo -e "${GREEN}  ✓ cluster-${region} ready${NC}"
done

echo ""
echo -e "${GREEN}>>> All 3 clusters up. Contexts:${NC}"
kubectl config get-contexts | grep "kind-cluster"
EOF

# ── 02-install-k8gb.sh ────────────────────────────────────────────────────────
cat << 'EOF' > "$PROJECT/scripts/02-install-k8gb.sh"
#!/usr/bin/env bash
# 02-install-k8gb.sh
# Installs the k8gb operator via Helm on all 3 clusters
#
# Key flags explained:
#   clusterGeoTag        — labels THIS cluster with its region (us/eu/ap)
#   extGslbClustersGeoTags — tells k8gb about ALL peer clusters incl. itself
#   exposeCoreDNS        — lets kind's internal CoreDNS handle DNS in local lab
#   k8gb.reconcileRequeueSeconds — how often k8gb re-checks cluster health
#
# --wait makes helm block until all k8gb pods are Running before returning
# This prevents 03-deploy-app.sh from running before k8gb CRDs are registered

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

ALL_GEO_TAGS="us,eu,ap"

echo -e "${YELLOW}>>> Adding k8gb Helm repo...${NC}"
helm repo add k8gb https://www.k8gb.io 2>/dev/null || helm repo update k8gb
helm repo update
echo -e "${GREEN}  ✓ Helm repo ready${NC}"
echo ""

for region in us eu ap; do
  echo -e "${YELLOW}>>> Installing k8gb on cluster-${region}...${NC}"

  kubectl config use-context "kind-cluster-${region}"

  # uninstall first if already present — safe to re-run
  if helm status k8gb --namespace k8gb &>/dev/null; then
    echo -e "${RED}  k8gb already installed on cluster-${region} — reinstalling...${NC}"
    helm uninstall k8gb --namespace k8gb
    # wait for operator pod to fully terminate before reinstalling
    kubectl delete pods --all --namespace k8gb --ignore-not-found=true
    sleep 5
  fi

  # install k8gb operator
  # --wait: block until all pods in the release are Running/Ready
  # --timeout 3m: give it up to 3 minutes (image pull can be slow)
  helm install k8gb k8gb/k8gb \
    --namespace k8gb \
    --create-namespace \
    --wait \
    --timeout 3m \
    --set k8gb.dnsZone="example.com" \
    --set k8gb.edgeDNSZone="example.com" \
    --set k8gb.clusterGeoTag="${region}" \
    --set k8gb.extGslbClustersGeoTags="${ALL_GEO_TAGS}" \
    --set k8gb.exposeCoreDNS=true \
    --set k8gb.reconcileRequeueSeconds=30

  echo -e "${GREEN}  ✓ k8gb installed and ready on cluster-${region}${NC}"
  echo ""
done

echo -e "${GREEN}>>> k8gb installed on all 3 clusters.${NC}"
EOF

# ── 03-deploy-app.sh ──────────────────────────────────────────────────────────
cat << 'EOF' > "$PROJECT/scripts/03-deploy-app.sh"
#!/usr/bin/env bash
# 03-deploy-app.sh
# Deploys nginx test app + ClusterIP service on all 3 clusters
# This is the workload k8gb will globally load-balance via DNS

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

MANIFESTS_DIR="$(dirname "$0")/../manifests"

echo -e "${YELLOW}>>> Deploying hello-app on all clusters...${NC}"

for region in us eu ap; do
  echo -e "${YELLOW}  cluster-${region}...${NC}"

  kubectl config use-context "kind-cluster-${region}"

  # apply deployment (creates nginx pod) and service (ClusterIP k8gb routes to)
  kubectl apply -f "$MANIFESTS_DIR/deployment.yaml"
  kubectl apply -f "$MANIFESTS_DIR/service.yaml"

  echo -e "${GREEN}  ✓ Manifests applied on cluster-${region}${NC}"
done

echo ""
echo -e "${YELLOW}>>> Waiting for pods to be Ready on all clusters...${NC}"

for region in us eu ap; do
  kubectl config use-context "kind-cluster-${region}"

  # wait until the rollout completes — 90s covers first-time image pull
  kubectl rollout status deployment/hello-app \
    --namespace default \
    --timeout=90s

  echo -e "${GREEN}  ✓ cluster-${region}:${NC}"
  kubectl get pods -l app=hello-app --namespace default
done

echo ""
echo -e "${GREEN}>>> hello-app running on all 3 clusters.${NC}"
EOF

# ── 04-apply-gslb.sh ──────────────────────────────────────────────────────────
cat << 'EOF' > "$PROJECT/scripts/04-apply-gslb.sh"
#!/usr/bin/env bash
# 04-apply-gslb.sh
# Applies the Gslb CRD on all 3 clusters
# k8gb watches this resource and manages DNS records for hello.example.com

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

MANIFESTS_DIR="$(dirname "$0")/../manifests"

echo -e "${YELLOW}>>> Applying Gslb resource on all clusters...${NC}"

for region in us eu ap; do
  kubectl config use-context "kind-cluster-${region}"

  # same manifest on every cluster — k8gb on each one participates in routing
  kubectl apply -f "$MANIFESTS_DIR/gslb.yaml"

  echo -e "${GREEN}  ✓ Gslb applied on cluster-${region}${NC}"
done

# give the k8gb controller time to reconcile the new Gslb objects across clusters
echo ""
echo -e "${YELLOW}>>> Waiting 15s for k8gb to reconcile Gslb...${NC}"
sleep 15

echo ""
echo -e "${YELLOW}>>> Gslb status across all clusters:${NC}"

for region in us eu ap; do
  kubectl config use-context "kind-cluster-${region}"
  echo -e "${GREEN}  === cluster-${region} ===${NC}"
  # -o wide shows healthy endpoints and geo tags alongside status
  kubectl get gslb hello-gslb --namespace default -o wide
done

echo ""
echo -e "${GREEN}>>> DNS routing active for hello.example.com (round-robin, 3 clusters).${NC}"
EOF

# ── 05-verify.sh ──────────────────────────────────────────────────────────────
cat << 'EOF' > "$PROJECT/scripts/05-verify.sh"
#!/usr/bin/env bash
# 05-verify.sh
# Full health check: nodes, k8gb pods, app pods, service, Gslb status, DNS

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

echo -e "${CYAN}=========================================================${NC}"
echo -e "${CYAN}  k8gb Multi-Cluster Verification                        ${NC}"
echo -e "${CYAN}=========================================================${NC}"
echo ""

for region in us eu ap; do
  kubectl config use-context "kind-cluster-${region}"

  echo -e "${YELLOW}━━━ cluster-${region} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

  echo -e "${CYAN}  [Nodes]${NC}"
  kubectl get nodes

  echo -e "${CYAN}  [k8gb Pods]${NC}"
  kubectl get pods --namespace k8gb -o wide

  echo -e "${CYAN}  [App Pod]${NC}"
  kubectl get pods -l app=hello-app --namespace default

  echo -e "${CYAN}  [Service]${NC}"
  kubectl get svc hello-app --namespace default

  echo -e "${CYAN}  [Gslb Status]${NC}"
  kubectl describe gslb hello-gslb --namespace default | grep -A 20 "Status:"
  echo ""
done

# DNS test from inside cluster-us using a temporary pod with dig installed
echo -e "${YELLOW}━━━ DNS Resolution Test ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
kubectl config use-context kind-cluster-us

echo "  Querying hello.example.com from inside cluster-us..."

# tutum/dnsutils has dig pre-installed
# --rm: delete pod after exit  --restart=Never: don't retry on failure
kubectl run dns-test \
  --image=tutum/dnsutils \
  --rm \
  --restart=Never \
  -it \
  -- dig hello.example.com

echo ""
echo -e "${GREEN}>>> Verification done.${NC}"
echo "    Gslb STATUS=Healthy + DNS resolving = multi-cluster LB is working."
EOF

# ── 06-failover-demo.sh ───────────────────────────────────────────────────────
cat << 'EOF' > "$PROJECT/scripts/06-failover-demo.sh"
#!/usr/bin/env bash
# 06-failover-demo.sh
# Simulates a cluster going down and watches k8gb pull it from DNS
# Then recovers it and watches k8gb re-add it
#
# Flow:
#   1. Scale cluster-eu app to 0 — simulates region going down
#   2. Poll Gslb health every 10s — watch healthy endpoints drop
#   3. DNS query — EU IP should be absent from response
#   4. Scale EU back to 1 — k8gb re-adds it to DNS rotation

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'

echo -e "${CYAN}=========================================================${NC}"
echo -e "${CYAN}  k8gb Failover Demo                                     ${NC}"
echo -e "${CYAN}=========================================================${NC}"
echo ""

# baseline — show all 3 clusters healthy before the demo
echo -e "${YELLOW}>>> [BEFORE] All 3 clusters healthy:${NC}"
kubectl config use-context kind-cluster-us
kubectl get gslb hello-gslb --namespace default -o wide
echo ""

# simulate EU going down — 0 running pods = k8gb marks cluster unhealthy
echo -e "${RED}>>> Simulating EU region failure — scaling to 0 replicas...${NC}"
kubectl config use-context kind-cluster-eu

kubectl scale deployment hello-app \
  --replicas=0 \
  --namespace default

echo -e "${RED}  ✗ cluster-eu: hello-app scaled to 0 (region down)${NC}"
echo ""

# poll k8gb health status every 10s
# k8gb detects failure within ~30-60s (health check interval + dnsTtlSeconds)
echo -e "${YELLOW}>>> Polling Gslb health every 10s for 90s...${NC}"

for i in $(seq 1 9); do
  echo -e "${CYAN}  --- Check ${i}/9 at $(date +%H:%M:%S) ---${NC}"

  for region in us eu ap; do
    kubectl config use-context "kind-cluster-${region}"
    HEALTHY=$(kubectl get gslb hello-gslb \
      --namespace default \
      -o jsonpath='{.status.healthyRecords}' 2>/dev/null || echo "pending")
    echo "    cluster-${region} healthyRecords: ${HEALTHY}"
  done

  echo ""
  sleep 10
done

# DNS query during failure — EU IP should be absent from response
echo -e "${YELLOW}>>> [DURING FAILURE] DNS query — EU IP should be missing:${NC}"
kubectl config use-context kind-cluster-us

kubectl run dns-test-fail \
  --image=tutum/dnsutils \
  --rm \
  --restart=Never \
  -it \
  -- dig hello.example.com

echo ""

# recover EU
echo -e "${GREEN}>>> Recovering EU — scaling back to 1 replica...${NC}"
kubectl config use-context kind-cluster-eu

kubectl scale deployment hello-app \
  --replicas=1 \
  --namespace default

kubectl rollout status deployment/hello-app \
  --namespace default \
  --timeout=60s

echo -e "${GREEN}  ✓ cluster-eu: hello-app recovered${NC}"
echo ""

# wait for k8gb to pick up the recovery and re-add EU to DNS
echo -e "${YELLOW}>>> Waiting 40s for k8gb to re-add EU to DNS rotation...${NC}"
sleep 40

# final DNS check — all 3 IPs should be back
echo -e "${YELLOW}>>> [AFTER RECOVERY] DNS query — all 3 clusters back:${NC}"
kubectl config use-context kind-cluster-us

kubectl run dns-test-recover \
  --image=tutum/dnsutils \
  --rm \
  --restart=Never \
  -it \
  -- dig hello.example.com

echo ""
echo -e "${GREEN}>>> Failover demo complete.${NC}"
echo "    EU went down → removed from DNS. EU recovered → re-added to DNS."
EOF

# ── 99-cleanup.sh ─────────────────────────────────────────────────────────────
cat << 'EOF' > "$PROJECT/scripts/99-cleanup.sh"
#!/usr/bin/env bash
# 99-cleanup.sh
# Deletes all 3 kind clusters and removes the k8gb Helm repo
# Always run this when done — kind clusters consume RAM/CPU while running

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

echo -e "${RED}>>> Tearing down k8gb multi-cluster lab...${NC}"
echo ""

for region in us eu ap; do
  echo -e "${YELLOW}  Deleting cluster-${region}...${NC}"

  # skip gracefully if cluster doesn't exist
  if kind get clusters 2>/dev/null | grep -q "^cluster-${region}$"; then
    # removes Docker containers, networks, and the kubectl context
    kind delete cluster --name "cluster-${region}"
    echo -e "${GREEN}  ✓ cluster-${region} deleted${NC}"
  else
    echo -e "${GREEN}  cluster-${region} not found — skipping${NC}"
  fi
done

echo ""
echo -e "${YELLOW}>>> Removing k8gb Helm repo...${NC}"
helm repo remove k8gb 2>/dev/null || echo "  k8gb repo not found — skipping"
echo -e "${GREEN}  ✓ Done${NC}"

echo ""
echo -e "${YELLOW}>>> Remaining kind clusters:${NC}"
kind get clusters || echo "  none"

echo ""
echo -e "${GREEN}>>> Cleanup complete.${NC}"
EOF

# ── permissions ───────────────────────────────────────────────────────────────
chmod +x "$PROJECT"/scripts/*.sh

# ── summary ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}=========================================================${NC}"
echo -e "${GREEN}  Project ready: ./${PROJECT}/${NC}"
echo -e "${CYAN}=========================================================${NC}"
echo ""
echo "  Files created:"
find "$PROJECT" -type f | sort | sed 's/^/    /'
echo ""
echo -e "${YELLOW}  Next steps:${NC}"
echo "    cd ${PROJECT}"
echo "    ./scripts/01-create-clusters.sh"
echo "    ./scripts/02-install-k8gb.sh"
echo "    ./scripts/03-deploy-app.sh"
echo "    ./scripts/04-apply-gslb.sh"
echo "    ./scripts/05-verify.sh"
echo "    ./scripts/06-failover-demo.sh"
echo "    ./scripts/99-cleanup.sh"
echo ""
echo -e "${YELLOW}  To push to git:${NC}"
echo "    cd ${PROJECT} && git init && git add . && git commit -m 'feat: k8gb multi-cluster lab'"
echo ""
