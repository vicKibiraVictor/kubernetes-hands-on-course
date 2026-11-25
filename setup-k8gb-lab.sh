#!/usr/bin/env bash
# setup-k8gb-lab.sh
# Run this ONE script — it creates the full k8gb-multicluster project
# folder structure and writes every file with content automatically.
# Usage: bash setup-k8gb-lab.sh

set -euo pipefail

# ── colours ───────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

PROJECT="k8gb-multicluster"   # root folder name

echo -e "${CYAN}=========================================================${NC}"
echo -e "${CYAN}  k8gb Multi-Cluster Lab — Project Generator             ${NC}"
echo -e "${CYAN}=========================================================${NC}"
echo ""

# ── 1. create folder structure ────────────────────────────────────────────────
echo -e "${YELLOW}>>> Creating folder structure...${NC}"

mkdir -p "$PROJECT/clusters"    # kind cluster configs (one per simulated region)
mkdir -p "$PROJECT/manifests"   # k8s manifests: deployment, service, gslb CRD
mkdir -p "$PROJECT/scripts"     # numbered runbook scripts

echo -e "${GREEN}  ✓ Folders created${NC}"
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# 2. WRITE ALL FILES
# Each section below uses a heredoc (cat << 'EOF' ... EOF) to write a file.
# Single-quoted 'EOF' means NO variable expansion inside the heredoc —
# dollar signs are written literally, which is what we want for bash scripts.
# ══════════════════════════════════════════════════════════════════════════════

# ── README.md ─────────────────────────────────────────────────────────────────
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
│   ├── cluster-us.yaml        # kind config for US cluster
│   ├── cluster-eu.yaml        # kind config for EU cluster
│   └── cluster-ap.yaml        # kind config for AP cluster
├── manifests/
│   ├── deployment.yaml        # nginx test app
│   ├── service.yaml           # ClusterIP service
│   └── gslb.yaml             # k8gb Gslb CRD — the global LB rule
└── scripts/
    ├── 01-create-clusters.sh  # spin up all 3 kind clusters
    ├── 02-install-k8gb.sh     # install k8gb via Helm on each cluster
    ├── 03-deploy-app.sh       # deploy nginx test app on each cluster
    ├── 04-apply-gslb.sh       # apply the Gslb routing rule
    ├── 05-verify.sh           # health check everything
    ├── 06-failover-demo.sh    # simulate cluster failure + DNS failover
    └── 99-cleanup.sh          # tear everything down
```

## Quick Start

```bash
chmod +x scripts/*.sh

./scripts/01-create-clusters.sh
./scripts/02-install-k8gb.sh
./scripts/03-deploy-app.sh
./scripts/04-apply-gslb.sh
./scripts/05-verify.sh
./scripts/06-failover-demo.sh   # optional — watch failover happen live

./scripts/99-cleanup.sh         # when done
```

## Prerequisites

- `kind` >= 0.24.0
- `kubectl`
- `helm` >= 3.x

## Key Concepts Covered

- Multi-cluster context switching with kubectl
- Helm-based operator installation
- k8gb GeoTag configuration per cluster
- Gslb CRD — custom resource for global DNS routing
- Round-robin vs failover traffic strategies
- Live DNS failover simulation
EOF
echo -e "${GREEN}  ✓ README.md${NC}"

# ── .gitignore ────────────────────────────────────────────────────────────────
echo -e "${YELLOW}>>> Writing .gitignore...${NC}"
cat << 'EOF' > "$PROJECT/.gitignore"
# local kubeconfig overrides created during testing
kubeconfig
*.kubeconfig

# editor/IDE folders
.vscode/
.idea/

# OS clutter
.DS_Store
Thumbs.db

# temp files generated during the lab
*.log
*.tmp
EOF
echo -e "${GREEN}  ✓ .gitignore${NC}"

# ══════════════════════════════════════════════════════════════════════════════
# CLUSTER CONFIGS
# Each cluster needs unique pod and service subnets so IPs don't clash
# when k8gb peers the clusters together for health checking
# US → 10.1.x / 10.101.x | EU → 10.2.x / 10.102.x | AP → 10.3.x / 10.103.x
# ══════════════════════════════════════════════════════════════════════════════

echo -e "${YELLOW}>>> Writing cluster configs...${NC}"

# ── clusters/cluster-us.yaml ──────────────────────────────────────────────────
cat << 'EOF' > "$PROJECT/clusters/cluster-us.yaml"
# clusters/cluster-us.yaml
# kind cluster config for the simulated US region (e.g. GCP us-central1)

kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4    # required API version for kind >= 0.24

nodes:
  - role: control-plane                # k8s master node
  - role: worker                       # worker node 1
  - role: worker                       # worker node 2 — gives spread for realism

networking:
  podSubnet: "10.1.0.0/16"            # unique pod CIDR for US — avoids IP conflicts across clusters
  serviceSubnet: "10.101.0.0/16"      # unique service CIDR for US
EOF
echo -e "${GREEN}  ✓ clusters/cluster-us.yaml${NC}"

# ── clusters/cluster-eu.yaml ──────────────────────────────────────────────────
cat << 'EOF' > "$PROJECT/clusters/cluster-eu.yaml"
# clusters/cluster-eu.yaml
# kind cluster config for the simulated EU region (e.g. GCP europe-west1)

kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4

nodes:
  - role: control-plane                # k8s master node
  - role: worker                       # worker node 1
  - role: worker                       # worker node 2

networking:
  podSubnet: "10.2.0.0/16"            # EU pod CIDR — different from US (10.1) and AP (10.3)
  serviceSubnet: "10.102.0.0/16"      # EU service CIDR — different from US (10.101) and AP (10.103)
EOF
echo -e "${GREEN}  ✓ clusters/cluster-eu.yaml${NC}"

# ── clusters/cluster-ap.yaml ──────────────────────────────────────────────────
cat << 'EOF' > "$PROJECT/clusters/cluster-ap.yaml"
# clusters/cluster-ap.yaml
# kind cluster config for the simulated Asia-Pacific region (e.g. GCP asia-east1)

kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4

nodes:
  - role: control-plane                # k8s master node
  - role: worker                       # worker node 1
  - role: worker                       # worker node 2

networking:
  podSubnet: "10.3.0.0/16"            # AP pod CIDR — completes the trio
  serviceSubnet: "10.103.0.0/16"      # AP service CIDR
EOF
echo -e "${GREEN}  ✓ clusters/cluster-ap.yaml${NC}"

# ══════════════════════════════════════════════════════════════════════════════
# MANIFESTS
# ══════════════════════════════════════════════════════════════════════════════

echo -e "${YELLOW}>>> Writing manifests...${NC}"

# ── manifests/deployment.yaml ─────────────────────────────────────────────────
cat << 'EOF' > "$PROJECT/manifests/deployment.yaml"
# manifests/deployment.yaml
# nginx Deployment — the test workload k8gb will load-balance globally
# Same manifest applied on all 3 clusters

apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello-app                      # deployment name — same on every cluster
  namespace: default
  labels:
    app: hello-app                     # label that links this deployment to the Service

spec:
  replicas: 2                          # 2 pods so we see intra-cluster load spread too

  selector:
    matchLabels:
      app: hello-app                   # pods owned by this deployment must have this label

  template:
    metadata:
      labels:
        app: hello-app                 # pod label — must match selector above

    spec:
      containers:
        - name: hello-app
          image: nginx:stable-alpine   # lightweight nginx — alpine = small image, fast pull
          ports:
            - containerPort: 80        # nginx serves HTTP on port 80

          resources:
            requests:
              cpu: "50m"               # 50 millicores requested — very lightweight
              memory: "64Mi"
            limits:
              cpu: "100m"              # cap at 100m so we don't hammer the local machine
              memory: "128Mi"
EOF
echo -e "${GREEN}  ✓ manifests/deployment.yaml${NC}"

# ── manifests/service.yaml ────────────────────────────────────────────────────
cat << 'EOF' > "$PROJECT/manifests/service.yaml"
# manifests/service.yaml
# ClusterIP Service for hello-app
# k8gb's Gslb resource references this service by name when routing traffic

apiVersion: v1
kind: Service
metadata:
  name: hello-app                      # name referenced in gslb.yaml backend
  namespace: default

spec:
  type: ClusterIP                      # internal only — k8gb handles the external DNS layer

  selector:
    app: hello-app                     # routes to any pod with label app=hello-app

  ports:
    - name: http
      protocol: TCP
      port: 80                         # port exposed inside the cluster
      targetPort: 80                   # forwarded to port 80 on the nginx container
EOF
echo -e "${GREEN}  ✓ manifests/service.yaml${NC}"

# ── manifests/gslb.yaml ───────────────────────────────────────────────────────
cat << 'EOF' > "$PROJECT/manifests/gslb.yaml"
# manifests/gslb.yaml
# Gslb — Global Server Load Balancing custom resource
# This is the core of k8gb: tells it HOW to route DNS across clusters
# Apply this on EVERY cluster after k8gb is installed

apiVersion: k8gb.absa.oss/v1beta1     # k8gb's custom API group
kind: Gslb                             # custom resource type registered by k8gb operator

metadata:
  name: hello-gslb
  namespace: default                   # must match the namespace of the Service it targets

spec:
  ingress:
    rules:
      - host: hello.example.com        # the DNS name clients resolve — in real setup: your domain
        http:
          paths:
            - path: /
              pathType: Prefix
              backend:
                service:
                  name: hello-app      # points to the ClusterIP service in service.yaml
                  port:
                    number: 80

  strategy:
    type: roundRobin                   # roundRobin = DNS cycles through all healthy cluster IPs
                                       # alternatives: failover (primary + backup), geoip (closest)

    dnsTtlSeconds: 30                  # how long clients cache the DNS result
                                       # 30s = fast failover (lower = more DNS queries, faster detection)

    splitBrainThresholdSeconds: 300    # 5 min — how long a cluster must be unreachable before
                                       # k8gb removes it from DNS rotation (prevents flapping)
EOF
echo -e "${GREEN}  ✓ manifests/gslb.yaml${NC}"

# ══════════════════════════════════════════════════════════════════════════════
# SCRIPTS
# ══════════════════════════════════════════════════════════════════════════════

echo -e "${YELLOW}>>> Writing scripts...${NC}"

# ── scripts/01-create-clusters.sh ────────────────────────────────────────────
cat << 'EOF' > "$PROJECT/scripts/01-create-clusters.sh"
#!/usr/bin/env bash
# scripts/01-create-clusters.sh
# Creates 3 kind clusters simulating US, EU, and AP cloud regions
# Run this first — everything else depends on these clusters existing

set -euo pipefail   # exit on error, unset vars, and pipe failures

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

# resolve path to clusters/ dir relative to this script's location
CLUSTERS_DIR="$(dirname "$0")/../clusters"

echo -e "${YELLOW}>>> Creating 3 kind clusters...${NC}"

for region in us eu ap; do
  echo -e "${YELLOW}  Creating cluster-${region}...${NC}"

  kind create cluster \
    --name "cluster-${region}" \                       # context will be kind-cluster-${region}
    --config "$CLUSTERS_DIR/cluster-${region}.yaml"   # pass our custom subnet config

  echo -e "${GREEN}  ✓ cluster-${region} ready${NC}"
done

echo ""
echo -e "${GREEN}>>> All clusters created. kubectl contexts:${NC}"
kubectl config get-contexts | grep "kind-cluster"   # should show all 3
EOF

# ── scripts/02-install-k8gb.sh ────────────────────────────────────────────────
cat << 'EOF' > "$PROJECT/scripts/02-install-k8gb.sh"
#!/usr/bin/env bash
# scripts/02-install-k8gb.sh
# Installs the k8gb operator via Helm on all 3 clusters
# k8gb runs as a controller inside each cluster and watches Gslb resources

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

ALL_GEO_TAGS="us,eu,ap"   # all region tags as a comma list — k8gb needs to know all peers

echo -e "${YELLOW}>>> Adding k8gb Helm repo...${NC}"
helm repo add k8gb https://www.k8gb.io   # register the k8gb chart repo locally
helm repo update                          # pull latest chart index
echo -e "${GREEN}  ✓ Helm repo ready${NC}"
echo ""

for region in us eu ap; do
  echo -e "${YELLOW}>>> Installing k8gb on cluster-${region}...${NC}"

  kubectl config use-context "kind-cluster-${region}"   # switch to this cluster

  helm install k8gb k8gb/k8gb \
    --namespace k8gb \
    --create-namespace \                                      # create ns if not exists
    --set k8gb.dnsZone="example.com" \                        # DNS zone k8gb manages
    --set k8gb.edgeDNSZone="example.com" \                    # upstream/edge zone (same in local lab)
    --set k8gb.clusterGeoTag="${region}" \                    # THIS cluster's geo identity
    --set k8gb.extGslbClustersGeoTags="${ALL_GEO_TAGS}" \    # all clusters incl. this one
    --set k8gb.exposeCoreDNS=true                             # let kind's CoreDNS handle local DNS

  echo -e "${GREEN}  ✓ k8gb installed on cluster-${region}${NC}"
done

echo ""
echo -e "${YELLOW}>>> Waiting for k8gb pods to be Ready...${NC}"

for region in us eu ap; do
  kubectl config use-context "kind-cluster-${region}"

  kubectl rollout status deployment/k8gb \
    --namespace k8gb \
    --timeout=120s   # wait up to 2 min for operator to start

  echo -e "${GREEN}  ✓ k8gb running on cluster-${region}${NC}"
done

echo ""
echo -e "${GREEN}>>> k8gb installed on all clusters.${NC}"
EOF

# ── scripts/03-deploy-app.sh ──────────────────────────────────────────────────
cat << 'EOF' > "$PROJECT/scripts/03-deploy-app.sh"
#!/usr/bin/env bash
# scripts/03-deploy-app.sh
# Deploys the nginx test app + ClusterIP service on all 3 clusters
# This is the workload k8gb will globally load-balance

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

MANIFESTS_DIR="$(dirname "$0")/../manifests"   # path to manifests/ dir

echo -e "${YELLOW}>>> Deploying hello-app on all clusters...${NC}"

for region in us eu ap; do
  echo -e "${YELLOW}  cluster-${region}...${NC}"

  kubectl config use-context "kind-cluster-${region}"

  kubectl apply -f "$MANIFESTS_DIR/deployment.yaml"   # creates the nginx pods
  kubectl apply -f "$MANIFESTS_DIR/service.yaml"      # creates the ClusterIP service

  echo -e "${GREEN}  ✓ Manifests applied on cluster-${region}${NC}"
done

echo ""
echo -e "${YELLOW}>>> Waiting for pods to be Ready...${NC}"

for region in us eu ap; do
  kubectl config use-context "kind-cluster-${region}"

  kubectl rollout status deployment/hello-app \
    --namespace default \
    --timeout=90s   # give time for first-time image pull

  echo -e "${GREEN}  ✓ cluster-${region} pods running:${NC}"
  kubectl get pods -l app=hello-app --namespace default
done

echo ""
echo -e "${GREEN}>>> hello-app running on all 3 clusters.${NC}"
EOF

# ── scripts/04-apply-gslb.sh ──────────────────────────────────────────────────
cat << 'EOF' > "$PROJECT/scripts/04-apply-gslb.sh"
#!/usr/bin/env bash
# scripts/04-apply-gslb.sh
# Applies the Gslb CRD on all 3 clusters
# After this, k8gb starts managing DNS for hello.example.com across all clusters

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

MANIFESTS_DIR="$(dirname "$0")/../manifests"

echo -e "${YELLOW}>>> Applying Gslb resource on all clusters...${NC}"

for region in us eu ap; do
  kubectl config use-context "kind-cluster-${region}"

  kubectl apply -f "$MANIFESTS_DIR/gslb.yaml"   # same Gslb rule applied on every cluster

  echo -e "${GREEN}  ✓ Gslb applied on cluster-${region}${NC}"
done

echo ""
echo -e "${YELLOW}>>> Giving k8gb 10s to reconcile...${NC}"
sleep 10   # controller needs a moment to process and sync the new Gslb objects

echo ""
echo -e "${YELLOW}>>> Gslb status across all clusters:${NC}"

for region in us eu ap; do
  kubectl config use-context "kind-cluster-${region}"
  echo -e "${GREEN}  === cluster-${region} ===${NC}"
  kubectl get gslb hello-gslb --namespace default -o wide   # STATUS should show Healthy
done

echo ""
echo -e "${GREEN}>>> DNS routing active for hello.example.com (round-robin across 3 clusters).${NC}"
EOF

# ── scripts/05-verify.sh ──────────────────────────────────────────────────────
cat << 'EOF' > "$PROJECT/scripts/05-verify.sh"
#!/usr/bin/env bash
# scripts/05-verify.sh
# Full health check across all 3 clusters
# Checks: nodes, k8gb operator pods, app pods, service, Gslb status, DNS

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
  kubectl get nodes                                        # all should be Ready

  echo -e "${CYAN}  [k8gb Pods]${NC}"
  kubectl get pods --namespace k8gb -o wide               # operator pod should be Running

  echo -e "${CYAN}  [App Pods]${NC}"
  kubectl get pods -l app=hello-app --namespace default   # 2 nginx pods per cluster

  echo -e "${CYAN}  [Service]${NC}"
  kubectl get svc hello-app --namespace default

  echo -e "${CYAN}  [Gslb Status]${NC}"
  kubectl describe gslb hello-gslb --namespace default | grep -A 20 "Status:"
  echo ""
done

# ── DNS test from inside cluster-us ──────────────────────────────────────────
echo -e "${YELLOW}━━━ DNS Resolution Test ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
kubectl config use-context kind-cluster-us

echo "  Querying hello.example.com from inside cluster-us..."
kubectl run dns-test \
  --image=tutum/dnsutils \   # pod with dig pre-installed
  --rm \                      # auto-delete pod when done
  --restart=Never \
  -it \
  -- dig hello.example.com   # should return IPs from all 3 healthy clusters

echo ""
echo -e "${GREEN}>>> Verification done.${NC}"
echo "    Gslb STATUS=Healthy + DNS resolving = multi-cluster LB is working."
EOF

# ── scripts/06-failover-demo.sh ───────────────────────────────────────────────
cat << 'EOF' > "$PROJECT/scripts/06-failover-demo.sh"
#!/usr/bin/env bash
# scripts/06-failover-demo.sh
# Simulates a cluster failure and watches k8gb remove it from DNS rotation
# Shows the core value of k8gb: automatic DNS failover across clusters
#
# What happens:
#   1. Scale down hello-app on cluster-eu → simulates that "region" going down
#   2. Watch k8gb detect the unhealthy cluster and pull its IP from DNS
#   3. Scale it back up → watch k8gb re-add it to rotation

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'

echo -e "${CYAN}=========================================================${NC}"
echo -e "${CYAN}  k8gb Failover Demo                                     ${NC}"
echo -e "${CYAN}=========================================================${NC}"
echo ""

# ── baseline: show DNS resolves to all 3 clusters ────────────────────────────
echo -e "${YELLOW}>>> [BEFORE] DNS state — all 3 clusters healthy:${NC}"
kubectl config use-context kind-cluster-us
kubectl get gslb hello-gslb --namespace default -o wide
echo ""

# ── simulate failure: take down EU ───────────────────────────────────────────
echo -e "${RED}>>> Simulating EU cluster failure — scaling hello-app to 0 replicas...${NC}"
kubectl config use-context kind-cluster-eu

kubectl scale deployment hello-app \
  --replicas=0 \           # zero replicas = no healthy pods = k8gb marks cluster unhealthy
  --namespace default

echo -e "${RED}  ✗ cluster-eu: hello-app scaled to 0 (simulating region down)${NC}"
echo ""

# ── watch k8gb detect the failure ────────────────────────────────────────────
echo -e "${YELLOW}>>> Watching k8gb detect failure (checking every 10s for 90s)...${NC}"
echo "    k8gb health-check interval + DNS TTL means detection takes ~30-60s"
echo ""

for i in $(seq 1 9); do
  echo -e "${CYAN}  --- Check ${i}/9 ($(date +%H:%M:%S)) ---${NC}"

  for region in us eu ap; do
    kubectl config use-context "kind-cluster-${region}"
    STATUS=$(kubectl get gslb hello-gslb --namespace default -o jsonpath='{.status.geoTag}' 2>/dev/null || echo "unknown")
    HEALTHY=$(kubectl get gslb hello-gslb --namespace default -o jsonpath='{.status.healthyRecords}' 2>/dev/null || echo "unknown")
    echo "    cluster-${region}: geoTag=${STATUS} | healthyRecords=${HEALTHY}"
  done

  echo ""
  sleep 10   # poll every 10s — k8gb default health check is faster than dnsTtl
done

# ── DNS after failure ─────────────────────────────────────────────────────────
echo -e "${YELLOW}>>> [DURING FAILURE] DNS state — EU should be removed:${NC}"
kubectl config use-context kind-cluster-us

kubectl run dns-test-fail \
  --image=tutum/dnsutils \
  --rm \
  --restart=Never \
  -it \
  -- dig hello.example.com   # EU IP should no longer appear in the response
echo ""

# ── recover: bring EU back up ────────────────────────────────────────────────
echo -e "${GREEN}>>> Recovering EU cluster — scaling hello-app back to 2...${NC}"
kubectl config use-context kind-cluster-eu

kubectl scale deployment hello-app \
  --replicas=2 \
  --namespace default

kubectl rollout status deployment/hello-app \
  --namespace default \
  --timeout=60s

echo -e "${GREEN}  ✓ cluster-eu: hello-app back to 2 replicas${NC}"
echo ""

# ── wait for k8gb to re-add EU to DNS ────────────────────────────────────────
echo -e "${YELLOW}>>> Waiting 40s for k8gb to re-add EU to DNS rotation...${NC}"
sleep 40

# ── final DNS check ───────────────────────────────────────────────────────────
echo -e "${YELLOW}>>> [AFTER RECOVERY] DNS state — all 3 clusters back:${NC}"
kubectl config use-context kind-cluster-us

kubectl run dns-test-recover \
  --image=tutum/dnsutils \
  --rm \
  --restart=Never \
  -it \
  -- dig hello.example.com   # all 3 IPs should be back

echo ""
echo -e "${GREEN}>>> Failover demo complete.${NC}"
echo "    EU went down → removed from DNS. EU came back → re-added to DNS."
echo "    That's k8gb global load balancing in action."
EOF

# ── scripts/99-cleanup.sh ─────────────────────────────────────────────────────
cat << 'EOF' > "$PROJECT/scripts/99-cleanup.sh"
#!/usr/bin/env bash
# scripts/99-cleanup.sh
# Deletes all 3 kind clusters and removes the k8gb Helm repo
# Always run this when done — kind clusters consume RAM/CPU while running

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

echo -e "${RED}>>> Tearing down k8gb multi-cluster lab...${NC}"
echo ""

for region in us eu ap; do
  echo -e "${YELLOW}  Deleting cluster-${region}...${NC}"

  kind delete cluster --name "cluster-${region}"   # removes Docker containers + kubectl context

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

echo -e "${GREEN}  ✓ All scripts written${NC}"

# ── 3. make all scripts executable ───────────────────────────────────────────
echo ""
echo -e "${YELLOW}>>> Setting execute permissions on all scripts...${NC}"
chmod +x "$PROJECT"/scripts/*.sh
echo -e "${GREEN}  ✓ Permissions set${NC}"

# ── 4. print final summary ───────────────────────────────────────────────────
echo ""
echo -e "${CYAN}=========================================================${NC}"
echo -e "${GREEN}  Project ready: ./${PROJECT}/${NC}"
echo -e "${CYAN}=========================================================${NC}"
echo ""
echo "  Files created:"
find "$PROJECT" -type f | sort | sed 's/^/    /'   # list everything that was written

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
