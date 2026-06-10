# Chapter 16 — An Introduction to Istio

## The idea (plain English)

As you split an app into many small services, hard questions appear: How do they
talk *securely*? How do you route traffic for a canary release? How do you *see*
what's calling what?

A **service mesh** answers all three by putting a tiny proxy (the **sidecar**)
next to **every** pod. Your app talks to its local proxy; the proxies handle
encryption, routing, retries, and metrics — **no code changes**. **Istio** is the
most popular mesh.

> After injection, every pod shows **2/2** containers: your app **+** its sidecar.

## Run it

```bash
./run.sh
```

> ⚠️ Heavy chapter — give Docker ~6 GB RAM.

It downloads Istio, installs it (demo profile), deploys the classic **Bookinfo**
sample app, and installs **Kiali** (the mesh dashboard).

## Try it yourself

```bash
# 1) send some traffic
kubectl -n bookinfo port-forward svc/productpage 9080:9080
for i in $(seq 1 50); do curl -s -o /dev/null http://localhost:9080/productpage; done

# 2) watch it flow between services
istioctl dashboard kiali
```

In Kiali, open **Graph**, pick the `bookinfo` namespace, and you'll see the live
map of services calling each other.

## Clean up

```bash
./cleanup.sh        # Chapter 17 builds on this — only clean up when done with both
```

➡️ **Next:** [Chapter 17 — Building & Securing Apps on Istio](../17-istio-apps).
