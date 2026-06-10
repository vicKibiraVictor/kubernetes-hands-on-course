# Chapter 2 — A Real Cluster with KinD

## The idea (plain English)

**KinD** = "Kubernetes IN Docker". It runs each Kubernetes node as a Docker
container, so you get a real, multi-node cluster on one laptop — perfect for
learning. We build the cluster here **once**, and every later chapter uses it.

A cluster has two kinds of machines (nodes):

- **control-plane** — the brain (the API server, scheduler, the cluster's database).
- **workers** — where your apps actually run.

Our cluster: **1 control-plane + 2 workers**.

### What about HAProxy?

When a cluster has **more than one control-plane** (for high availability), KinD
automatically starts an **HAProxy** load balancer container in front of them, so
clients hit one stable address. See [`cluster-config-ha.yaml`](cluster-config-ha.yaml)
to try it — it's optional. (For load-balancing *application* traffic across
workers, we use MetalLB in Chapter 4.)

## Run it

```bash
./run.sh
```

Creates the cluster (re-running is safe — it skips creation if it already exists)
and points `kubectl` at it.

## Try it yourself

```bash
kubectl get nodes                 # the 3 nodes, all "Ready"
kubectl get pods -A               # the system pods that make the cluster work
docker ps                         # each node is a Docker container
```

## Clean up

```bash
./cleanup.sh        # deletes the cluster (only when you're completely done)
```

➡️ **Next:** [Chapter 3 — the objects cheat sheet](../03-kubernetes-bootcamp), then
[Chapter 4](../04-services-loadbalancing-network-policies).
