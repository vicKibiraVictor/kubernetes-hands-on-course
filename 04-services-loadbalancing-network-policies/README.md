# Chapter 4 — Services, Load Balancing & Network Policies

## The idea (plain English)

Pods are disposable and their IPs change. So we never talk to Pods directly — we
talk to a **Service**, a stable front door that load-balances across them.

Service types:

- **ClusterIP** — reachable only inside the cluster (app → database).
- **NodePort** — opens a port on every node.
- **LoadBalancer** — gives an external IP. On a cloud the cloud provides it; on
  our laptop **MetalLB** provides it (this is **Layer 4** — IP + port).

For HTTP we usually want to route by **hostname/path** — that's **Layer 7**, the
job of an **Ingress** + an ingress controller (we use **ingress-nginx**).

Finally, a **NetworkPolicy** is a firewall for Pods: by default any Pod can talk
to any Pod; a policy locks that down to only who you allow.

> ⚠️ KinD's built-in network plugin doesn't *enforce* NetworkPolicies, so the
> script also installs **kube-network-policies** (a tiny add-on that does). That's
> why the "blocked" test below actually blocks.

## Run it

```bash
./run.sh
```

It installs MetalLB, ingress-nginx, and the policy enforcer, deploys a sample app,
then runs three tests:

1. **LoadBalancer** — the `web-lb` service gets a real external IP.
2. **Ingress** — `web.local` is routed to the app (reached via a port-forward).
3. **NetworkPolicy** — a Pod labelled `role=client` can reach the app; a Pod
   without the label is **blocked**.

## Try it yourself

```bash
kubectl -n ch4 get svc                                   # see ClusterIP + LoadBalancer

# reach it through the Ingress (works on every platform):
kubectl -n ingress-nginx port-forward svc/ingress-nginx-controller 8080:80 &
curl -H "Host: web.local" http://localhost:8080

kubectl -n ch4 get networkpolicy                         # the firewall rules
```

> **Why port-forward and not `localhost:80`?** kind only maps host port 80 to the
> **control-plane** node, but the ingress controller often runs on a **worker** —
> so `localhost:80` may hit a dead end. Port-forward always works.
> On **Linux** you can also curl the LoadBalancer IP directly
> (`curl http://<EXTERNAL-IP>`); on **Docker Desktop (Mac/Win)** that IP lives in
> a VM, so use the port-forward.

## Clean up

```bash
./cleanup.sh        # removes the sample app; keeps MetalLB + ingress for later chapters
```

➡️ **Next:** [Chapter 5 — External DNS & Global Load Balancing](../05-external-dns-global-loadbalancing).
