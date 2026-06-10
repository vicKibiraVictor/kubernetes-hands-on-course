# ☸️ Hands-On Kubernetes — a teaching course

A folder-per-chapter course that takes you from **Docker basics** to a
**secured, observable, multi-tenant Kubernetes cluster**. Each chapter has:

- a short **README** written in plain English (what the idea is, why it matters),
- a tiny **sample project** so you *see* the idea working, and
- **one script — `run.sh`** — that does everything for that chapter. No typing
  commands one by one.

Every chapter builds on the one before it. Do them in order.

> Built for teaching. Read the chapter README, run `./run.sh`, then poke at the
> cluster with the commands the README lists.

---

## What you need first

| Tool      | Why | 
|-----------|-----|
| **Docker**  | runs the containers and the local cluster | 
| **kubectl** | talks to the cluster |
| **kind**    | creates the local Kubernetes cluster |
| **helm**    | installs packaged apps |

Docker you install yourself (https://docs.docker.com/get-docker/). The rest:

```bash
./setup-tools.sh        # installs kubectl, kind, helm if missing
```

Some chapters install one extra CLI (e.g. `istioctl`, `velero`, `vcluster`) —
their `run.sh` installs it automatically if it's missing.

**Recommended machine:** Linux or macOS, Docker with **at least 6 CPU / 8 GB RAM**
free. The monitoring (15), Istio (16–17), and Harbor (18) chapters are the heavy
ones — close the others first.

---

## How to use it

```bash
./setup-tools.sh                         # 1. one-time tool install
cd 02-kind-multinode-cluster && ./run.sh # 2. build the cluster (used by all later chapters)
cd ../04-services-loadbalancing-network-policies && ./run.sh   # 3. then go in order
```

Every `run.sh` is safe to re-run. Every chapter has a **Clean up** section, and
most ship a `cleanup.sh`.

---

## The chapters

| # | Folder | You'll learn |
|---|--------|--------------|
| 1 | [`01-docker-essentials`](01-docker-essentials) | Build, run, and inspect containers with the Docker CLI |
| 2 | [`02-kind-multinode-cluster`](02-kind-multinode-cluster) | Create a multi-node cluster with KinD + an HAProxy load balancer |
| 3 | [`03-kubernetes-bootcamp`](03-kubernetes-bootcamp) | A pocket guide to the core objects (notes only — no script) |
| 4 | [`04-services-loadbalancing-network-policies`](04-services-loadbalancing-network-policies) | Services, MetalLB (L4), Ingress (L7), and Network Policies |
| 5 | [`05-external-dns-global-loadbalancing`](05-external-dns-global-loadbalancing) | Automatic DNS records (external-dns) and global load balancing (K8GB) |
| 6 | [`06-authentication-oidc`](06-authentication-oidc) | How users log in — certificates, tokens, and OIDC |
| 7 | [`07-rbac-and-auditing`](07-rbac-and-auditing) | Limit what users can do with RBAC, and watch with auditing |
| 8 | [`08-managing-secrets-vault`](08-managing-secrets-vault) | Store secrets in HashiCorp Vault and sync them with the External Secrets Operator |
| 9 | [`09-multitenancy-vcluster`](09-multitenancy-vcluster) | Give each team its own virtual cluster with vCluster |
| 10 | [`10-secured-kubernetes-dashboard`](10-secured-kubernetes-dashboard) | Deploy the Kubernetes Dashboard the *safe* way |
| 11 | [`11-opa-gatekeeper-policies`](11-opa-gatekeeper-policies) | Enforce rules RBAC can't, with OPA Gatekeeper + Rego |
| 12 | [`12-node-security-gatekeeper`](12-node-security-gatekeeper) | Block risky pods (privileged, hostPath, root) with policy |
| 13 | [`13-runtime-security-kubearmor`](13-runtime-security-kubearmor) | Lock down what a running container may do with KubeArmor |
| 14 | [`14-backup-velero-minio`](14-backup-velero-minio) | Back up and restore workloads with Velero + MinIO |
| 15 | [`15-monitoring-prometheus-loki`](15-monitoring-prometheus-loki) | Metrics (Prometheus/Grafana) and lightweight logs (Loki) |
| 16 | [`16-istio-intro`](16-istio-intro) | Install Istio, deploy a sample app, see traffic in Kiali |
| 17 | [`17-istio-apps`](17-istio-apps) | Route traffic, require mTLS, and authorize service-to-service calls |
| 18 | [`18-harbor-image-registry`](18-harbor-image-registry) | Run your own container registry with Harbor and push an image |

---

## A note on reliability

These scripts use **current, official install methods** and, where a project
publishes versioned manifests, they fetch the **latest release tag automatically**
so they don't go stale. They target **Linux/macOS with Docker**. The cloud-native
ecosystem moves fast — if a chart or image ever moves, the README tells you the
exact command to adjust.

Tear the whole thing down anytime:

```bash
kind delete cluster --name k8s-course
```
