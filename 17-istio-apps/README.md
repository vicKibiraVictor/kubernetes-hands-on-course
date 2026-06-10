# Chapter 17 — Building & Securing Apps on Istio

## The idea (plain English)

Now we *use* the mesh from Chapter 16. Three superpowers, all without touching app
code:

1. **Gateway + VirtualService** — expose a service to the outside and route to it.
2. **mTLS (STRICT)** — every call between pods is mutually authenticated and
   encrypted. Anything *not* in the mesh is refused.
3. **AuthorizationPolicy** — fine-grained "who/what may call this" rules, e.g.
   "productpage accepts **GET only**".

> Monolith vs microservices: a monolith is one big app; microservices split it
> into small services that call each other. The mesh is what makes that web of
> calls secure and observable.

## Run it

```bash
./run.sh        # needs Chapter 16 (Bookinfo + Istio) running
```

It adds a gateway, switches on STRICT mTLS, and adds a GET-only rule — testing
each from a client **inside** the mesh and a plain pod **outside** it:

| Test | Expected |
|------|----------|
| in-mesh GET productpage | ✅ 200 |
| outside-mesh request (no sidecar) | ❌ blocked (mTLS required) |
| in-mesh GET (after authz) | ✅ 200 |
| in-mesh POST (after authz) | ❌ 403 denied |

## Try it yourself

```bash
kubectl -n istio-system port-forward svc/istio-ingressgateway 8080:80
curl http://localhost:8080/productpage          # through the gateway
```

## Clean up

```bash
./cleanup.sh
```

➡️ **Next:** [Chapter 18 — Your Own Registry with Harbor](../18-harbor-image-registry).
