# Chapter 9 — Multitenancy with vCluster

## The idea (plain English)

How do you give five teams their own cluster without paying for five clusters?

- **One namespace each** is cheap but weak: they share one API server, can't
  install their own CRDs, and can see cluster-wide things.
- **Five real clusters** is strong isolation but expensive and slow to manage.

**vCluster** is the middle ground: a real, working Kubernetes cluster that runs
**inside a namespace** of your host cluster. Each team gets their own API server
and admin rights, but they all share the host's nodes. Cheap *and* isolated.

```
   Host cluster
   └── namespace team-a
        └── vCluster "team-a"  ← its own API server, CRDs, admin — the team's playground
```

## Run it

```bash
./run.sh
```

It installs the `vcluster` CLI (if missing), creates a virtual cluster **team-a**,
runs an app inside it, then shows the key point: the app is visible **inside** the
vCluster but **not** to the host — that's the isolation.

## Try it yourself

```bash
vcluster list                                   # your virtual clusters
vcluster connect team-a -n team-a               # switch kubectl INTO the tenant
kubectl get ns                                  #   ...you're now "admin" of team-a
vcluster disconnect                             # back to the host
```

## Clean up

```bash
./cleanup.sh
```

➡️ **Next:** [Chapter 10 — A Secured Kubernetes Dashboard](../10-secured-kubernetes-dashboard).
