#!/usr/bin/env bash
# setup-k8gb-lab.sh
# Run this ONE script — it creates the full k8gb-multicluster project
# folder structure and writes every file with content automatically.
# Usage: bash setup-k8gb-lab.sh

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

PROJECT="k8gb-multicluster"

echo -e "${CYAN}=========================================================${NC}"
echo -e "${CYAN}  k8gb Multi-Cluster Lab — Project Generator             ${NC}"
echo -e "${CYAN}=========================================================${NC}"
echo ""

# ── 1. create folder structure ────────────────────────────────────────────────
echo -e "${YELLOW}>>> Creating folder structure...${NC}"
mkdir -p "$PROJECT/clusters"
mkdir -p "$PROJECT/manifests"
mkdir -p "$PROJECT/scripts"
echo -e "${GREEN}  ✓ Folders created${NC}"
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# README
# ══════════════════════════════════════════════════════════════════════════════
echo -e "${YELLOW}>>> Writing README.md...${NC}"
cat << 'EOF' > "$PROJECT/README.md"
# k8gb Multi-Cluster Local Lab

Simulates a **global Kubernetes load balancer** across 3 "cloud regions"
using [kind](https://kind.sigs.k8s.io/) clusters and [k8gb](https://www.k8gb.io/).

## Simulated Regions

| Cluster Name | Simulated Region           |
|--------------|----------------------------|
| `cluster-us` | US (e.g. GCP us-central1)  |
| `cluster-eu` | EU (e.g. GCP europe-west1) |
| `cluster-ap` | AP (e.g. GCP asia-east1)   |

## Project Structure

```
k8gb-multicluster/
├── README.md
├── .gitignore
├── clusters/
│   ├── cluster-us.yaml
│   ├── cluster-eu.yaml
│   └── cluster-ap.yaml
├── manifests/
│   ├── deployment.yaml
│   ├── service.yaml
│   └── gslb.yaml
└── scripts/
    ├── 01-create-clusters.sh
    ├── 02-install-k8gb.sh
    ├── 03-deploy-app.sh
    ├── 04-apply-gslb.sh
    ├── 05-verify.sh
    ├── 06-failover-demo.sh
    └── 99-cleanup.sh
```

## Quick Start

```bash
chmod +x scripts/*.sh
./scripts/01-create-clusters.sh
./scripts/02-install-k8gb.sh
./scripts/03-deploy-app.sh
./scripts/04-apply-gslb.sh
./scripts/05-verify.sh
./scripts/06-failover-demo.sh   # optional — watch failover live
./scripts/99-cleanup.sh         # when done
```

## Prerequisites

- `kind` >= 0.24.0
- `kubectl`
- `helm` >= 3.x
EOF
echo -e "${GREEN}  ✓ README.md${NC}"

# ── .gitignore ────────────────────────────────────────────────────────────────
echo -e "${YELLOW}>>> Writing .gitignore...${NC}"
cat << 'EOF' > "$PROJECT/.gitignore"
kubeconfig
*.kubeconfig
.vscode/
.idea/
.DS_Store
Thumbs.db
*.log
*.tmp
EOF
echo -e "${GREEN}  ✓ .gitignore${NC}"

# ══════════════════════════════════════════════════════════════════════════════
# CLUSTER CONFIGS
# unique pod/service subnets per cluster so IPs don't clash when k8gb peers them
# US: 10.1.x / 10.101.x  |  EU: 10.2.x / 10.102.x  |  AP: 10.3.x / 10.103.x
# ══════════════════════════════════════════════════════════════════════════════
echo -e "${YELLOW}>>> Writing cluster configs...${NC}"

cat << 'EOF' > "$PROJECT/clusters/cluster-us.yaml"
# kind cluster config — simulated US region (e.g. GCP us-central1)
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane   # k8s master
  - role: worker          # worker 1
  - role: worker          # worker 2
networking:
  podSubnet: "10.1.0.0/16"       # unique pod CIDR for US
  serviceSubnet: "10.101.0.0/16" # unique service CIDR for US
EOF
echo -e "${GREEN}  ✓ clusters/cluster-us.yaml${NC}"

cat << 'EOF' > "$PROJECT/clusters/cluster-eu.yaml"
# kind cluster config — simulated EU region (e.g. GCP europe-west1)
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane   # k8s master
  - role: worker          # worker 1
  - role: worker          # worker 2
networking:
  podSubnet: "10.2.0.0/16"       # unique pod CIDR for EU
  serviceSubnet: "10.102.0.0/16" # unique service CIDR for EU
EOF
echo -e "${GREEN}  ✓ clusters/cluster-eu.yaml${NC}"

cat << 'EOF' > "$PROJECT/clusters/cluster-ap.yaml"
# kind cluster config — simulated AP region (e.g. GCP asia-east1)
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane   # k8s master
  - role: worker          # worker 1
  - role: worker          # worker 2
networking:
  podSubnet: "10.3.0.0/16"       # unique pod CIDR for AP
  serviceSubnet: "10.103.0.0/16" # unique service CIDR for AP
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
  replicas: 2             # 2 pods so we see intra-cluster spread too
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
          image: nginx:stable-alpine   # lightweight nginx — fast pull
          ports:
            - containerPort: 80
          resources:
            requests:
              cpu: "50m"
              memory: "64Mi"
            limits:
              cpu: "100m"
              memory: "128Mi"
EOF
echo -e "${GREEN}  ✓ manifests/deployment.yaml${NC}"

cat << 'EOF' > "$PROJECT/manifests/service.yaml"
# ClusterIP Service — k8gb's Gslb resource references this by name
apiVersion: v1
kind: Service
metadata:
  name: hello-app
  namespace: default
spec:
  type: ClusterIP      # internal only — k8gb handles external DNS routing
  selector:
    app: hello-app     # routes to pods with label app=hello-app
  ports:
    - name: http
      protocol: TCP
      port: 80         # port exposed inside the cluster
      targetPort: 80   # forwarded to nginx container port 80
EOF
echo -e "${GREEN}  ✓ manifests/service.yaml${NC}"

cat << 'EOF' > "$PROJECT/manifests/gslb.yaml"
# Gslb — Global Server Load Balancing custom resource
# Core of k8gb: defines HOW DNS traffic is routed across clusters
# Apply this on EVERY cluster after k8gb is installed
apiVersion: k8gb.absa.oss/v1beta1
kind: Gslb
metadata:
  name: hello-gslb
  namespace: default   # must match the namespace of the target Service
spec:
  ingress:
    rules:
      - host: hello.example.com   # DNS name clients resolve
        http:
          paths:
            - path: /
              pathType: Prefix
              backend:
                service:
                  name: hello-app   # points to service.yaml
                  port:
                    number: 80
  strategy:
    # roundRobin: DNS cycles through all healthy cluster IPs
    # alternatives: failover (primary + backup), geoip (closest region)
    type: roundRobin

    # how long clients cache the DNS result
    # 30s = fast failover detection
    dnsTtlSeconds: 30

    # how long a cluster must be unreachable before k8gb removes it from DNS
    # 300s = 5 min, prevents flapping on temporary hiccups
    splitBrainThresholdSeconds: 300
EOF
echo -e "${GREEN}  ✓ manifests/gslb.yaml${NC}"

# ══════════════════════════════════════════════════════════════════════════════
# SCRIPTS
# NOTE: no inline comments after \ line continuations — they break bash parsing
# All comments are on their own lines above the command they describe
# ══════════════════════════════════════════════════════════════════════════════
echo -e "${YELLOW}>>> Writing scripts...${NC}"

# ── 01-create-clusters.sh ─────────────────────────────────────────────────────
cat << 'EOF' > "$PROJECT/scripts/01-create-clusters.sh"
#!/usr/bin/env bash
# 01-create-clusters.sh
# Creates 3 kind clusters simulating US, EU, and AP cloud regions
# Run this first — everything else depends on these clusters

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

# resolve path to clusters/ dir relative to this script
CLUSTERS_DIR="$(dirname "$0")/../clusters"

echo -e "${YELLOW}>>> Creating 3 kind clusters...${NC}"

for region in us eu ap; do
  echo -e "${YELLOW}  Creating cluster-${region}...${NC}"

  # create the cluster using its region-specific config (unique subnets per region)
  kind create cluster \
    --name "cluster-${region}" \
    --config "$CLUSTERS_DIR/cluster-${region}.yaml"

  echo -e "${GREEN}  ✓ cluster-${region} ready${NC}"
done

echo ""
echo -e "${GREEN}>>> All clusters created. kubectl contexts:${NC}"
# should show: kind-cluster-us, kind-cluster-eu, kind-cluster-ap
kubectl config get-contexts | grep "kind-cluster"
EOF

# ── 02-install-k8gb.sh ────────────────────────────────────────────────────────
cat << 'EOF' > "$PROJECT/scripts/02-install-k8gb.sh"
#!/usr/bin/env bash
# 02-install-k8gb.sh
# Installs the k8gb operator via Helm on all 3 clusters
# k8gb runs as a controller inside each cluster and watches Gslb resources

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

# all region geo tags as a comma list — k8gb needs to know all peers
ALL_GEO_TAGS="us,eu,ap"

echo -e "${YELLOW}>>> Adding k8gb Helm repo...${NC}"
helm repo add k8gb https://www.k8gb.io
helm repo update
echo -e "${GREEN}  ✓ Helm repo ready${NC}"
echo ""

for region in us eu ap; do
  echo -e "${YELLOW}>>> Installing k8gb on cluster-${region}...${NC}"

  # switch kubectl to this cluster before running helm
  kubectl config use-context "kind-cluster-${region}"

  # install k8gb operator into its own namespace
  # clusterGeoTag labels this cluster with its region identity
  # extGslbClustersGeoTags tells k8gb about all peer clusters
  # exposeCoreDNS lets kind's CoreDNS handle DNS resolution locally
  helm install k8gb k8gb/k8gb \
    --namespace k8gb \
    --create-namespace \
    --set k8gb.dnsZone="example.com" \
    --set k8gb.edgeDNSZone="example.com" \
    --set k8gb.clusterGeoTag="${region}" \
    --set k8gb.extGslbClustersGeoTags="${ALL_GEO_TAGS}" \
    --set k8gb.exposeCoreDNS=true

  echo -e "${GREEN}  ✓ k8gb installed on cluster-${region}${NC}"
done

echo ""
echo -e "${YELLOW}>>> Waiting for k8gb pods to be Ready...${NC}"

for region in us eu ap; do
  kubectl config use-context "kind-cluster-${region}"

  # wait up to 2 min for the operator deployment to fully roll out
  kubectl rollout status deployment/k8gb \
    --namespace k8gb \
    --timeout=120s

  echo -e "${GREEN}  ✓ k8gb running on cluster-${region}${NC}"
done

echo ""
echo -e "${GREEN}>>> k8gb installed on all clusters.${NC}"
EOF

# ── 03-deploy-app.sh ──────────────────────────────────────────────────────────
cat << 'EOF' > "$PROJECT/scripts/03-deploy-app.sh"
#!/usr/bin/env bash
# 03-deploy-app.sh
# Deploys the nginx test app + ClusterIP service on all 3 clusters
# This is the workload k8gb will globally load-balance

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

MANIFESTS_DIR="$(dirname "$0")/../manifests"

echo -e "${YELLOW}>>> Deploying hello-app on all clusters...${NC}"

for region in us eu ap; do
  echo -e "${YELLOW}  cluster-${region}...${NC}"

  kubectl config use-context "kind-cluster-${region}"

  # apply deployment (creates nginx pods) and service (ClusterIP k8gb routes to)
  kubectl apply -f "$MANIFESTS_DIR/deployment.yaml"
  kubectl apply -f "$MANIFESTS_DIR/service.yaml"

  echo -e "${GREEN}  ✓ Manifests applied on cluster-${region}${NC}"
done

echo ""
echo -e "${YELLOW}>>> Waiting for pods to be Ready...${NC}"

for region in us eu ap; do
  kubectl config use-context "kind-cluster-${region}"

  # wait until all replicas are running (90s allows for first-time image pull)
  kubectl rollout status deployment/hello-app \
    --namespace default \
    --timeout=90s

  echo -e "${GREEN}  ✓ cluster-${region} pods:${NC}"
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
# After this k8gb starts managing DNS for hello.example.com globally

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

MANIFESTS_DIR="$(dirname "$0")/../manifests"

echo -e "${YELLOW}>>> Applying Gslb resource on all clusters...${NC}"

for region in us eu ap; do
  kubectl config use-context "kind-cluster-${region}"

  # same Gslb manifest on every cluster
  # k8gb on each cluster reads this and participates in routing for hello.example.com
  kubectl apply -f "$MANIFESTS_DIR/gslb.yaml"

  echo -e "${GREEN}  ✓ Gslb applied on cluster-${region}${NC}"
done

echo ""
echo -e "${YELLOW}>>> Giving k8gb 10s to reconcile Gslb objects...${NC}"
sleep 10

echo ""
echo -e "${YELLOW}>>> Gslb status across all clusters:${NC}"

for region in us eu ap; do
  kubectl config use-context "kind-cluster-${region}"
  echo -e "${GREEN}  === cluster-${region} ===${NC}"
  # STATUS column should show Healthy once k8gb syncs across clusters
  kubectl get gslb hello-gslb --namespace default -o wide
done

echo ""
echo -e "${GREEN}>>> DNS routing active for hello.example.com (round-robin, 3 clusters).${NC}"
EOF

# ── 05-verify.sh ──────────────────────────────────────────────────────────────
cat << 'EOF' > "$PROJECT/scripts/05-verify.sh"
#!/usr/bin/env bash
# 05-verify.sh
# Full health check across all 3 clusters
# Checks: nodes, k8gb pods, app pods, service, Gslb status, DNS query

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

  echo -e "${CYAN}  [App Pods]${NC}"
  kubectl get pods -l app=hello-app --namespace default

  echo -e "${CYAN}  [Service]${NC}"
  kubectl get svc hello-app --namespace default

  echo -e "${CYAN}  [Gslb Status]${NC}"
  kubectl describe gslb hello-gslb --namespace default | grep -A 20 "Status:"
  echo ""
done

# run a DNS query from inside cluster-us using a temporary pod
echo -e "${YELLOW}━━━ DNS Resolution Test ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
kubectl config use-context kind-cluster-us

echo "  Querying hello.example.com from inside cluster-us..."

# tutum/dnsutils has dig pre-installed
# --rm auto-deletes the pod after it exits
# --restart=Never means don't restart the pod if it fails
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
# Simulates a cluster going down and watches k8gb pull it out of DNS
# Then recovers it and watches k8gb re-add it
#
# Flow:
#   1. Scale down hello-app on cluster-eu (simulates region failure)
#   2. Poll Gslb status every 10s — watch healthy endpoints drop to 2
#   3. Run a DNS query — EU IP should be gone from the response
#   4. Scale EU back up — watch k8gb re-add it to DNS rotation

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'

echo -e "${CYAN}=========================================================${NC}"
echo -e "${CYAN}  k8gb Failover Demo                                     ${NC}"
echo -e "${CYAN}=========================================================${NC}"
echo ""

# show baseline — all 3 clusters healthy
echo -e "${YELLOW}>>> [BEFORE] All 3 clusters healthy:${NC}"
kubectl config use-context kind-cluster-us
kubectl get gslb hello-gslb --namespace default -o wide
echo ""

# simulate EU going down by scaling app to 0 replicas
# k8gb monitors pod health — 0 running pods = cluster marked unhealthy
echo -e "${RED}>>> Simulating EU failure — scaling hello-app to 0 replicas...${NC}"
kubectl config use-context kind-cluster-eu

kubectl scale deployment hello-app \
  --replicas=0 \
  --namespace default

echo -e "${RED}  ✗ cluster-eu: hello-app scaled to 0${NC}"
echo ""

# poll every 10s — k8gb should detect failure within ~30-60s
# (health check interval + dnsTtlSeconds from gslb.yaml)
echo -e "${YELLOW}>>> Polling Gslb health every 10s (up to 90s)...${NC}"

for i in $(seq 1 9); do
  echo -e "${CYAN}  --- Check ${i}/9 ($(date +%H:%M:%S)) ---${NC}"

  for region in us eu ap; do
    kubectl config use-context "kind-cluster-${region}"

    # extract healthy endpoints from Gslb status
    HEALTHY=$(kubectl get gslb hello-gslb \
      --namespace default \
      -o jsonpath='{.status.healthyRecords}' 2>/dev/null || echo "pending")

    echo "    cluster-${region} healthyRecords: ${HEALTHY}"
  done

  echo ""
  sleep 10
done

# DNS check during failure — EU IP should be absent
echo -e "${YELLOW}>>> [DURING FAILURE] DNS query — EU should be removed:${NC}"
kubectl config use-context kind-cluster-us

kubectl run dns-test-fail \
  --image=tutum/dnsutils \
  --rm \
  --restart=Never \
  -it \
  -- dig hello.example.com

echo ""

# bring EU back up
echo -e "${GREEN}>>> Recovering EU — scaling hello-app back to 2...${NC}"
kubectl config use-context kind-cluster-eu

kubectl scale deployment hello-app \
  --replicas=2 \
  --namespace default

kubectl rollout status deployment/hello-app \
  --namespace default \
  --timeout=60s

echo -e "${GREEN}  ✓ cluster-eu: hello-app back to 2 replicas${NC}"
echo ""

# wait for k8gb to pick up the recovery and update DNS
echo -e "${YELLOW}>>> Waiting 40s for k8gb to re-add EU to DNS...${NC}"
sleep 40

# final DNS check — all 3 IPs should be back
echo -e "${YELLOW}>>> [AFTER RECOVERY] DNS query — all 3 clusters should be back:${NC}"
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
echo "    That is k8gb global load balancing in action."
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

  # removes Docker containers, networks, and the kubectl context for this cluster
  kind delete cluster --name "cluster-${region}"

  echo -e "${GREEN}  ✓ cluster-${region} deleted${NC}"
done

echo ""
echo -e "${YELLOW}>>> Removing k8gb Helm repo...${NC}"
helm repo remove k8gb
echo -e "${GREEN}  ✓ Helm repo removed${NC}"

echo ""
echo -e "${YELLOW}>>> Remaining kind clusters (should be empty):${NC}"
kind get clusters

echo ""
echo -e "${GREEN}>>> Cleanup complete.${NC}"
EOF

# ── set permissions ───────────────────────────────────────────────────────────
echo -e "${YELLOW}>>> Setting execute permissions on scripts...${NC}"
chmod +x "$PROJECT"/scripts/*.sh
echo -e "${GREEN}  ✓ Permissions set${NC}"

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
