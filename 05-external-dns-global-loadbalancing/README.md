# Chapter 5 — External DNS & Global Load Balancing

## The idea (plain English)

When you create a Service or Ingress, it gets an IP — but humans use **names**,
not IPs. **external-dns** watches your Services/Ingresses and **automatically
creates the matching DNS records** in your DNS provider (Route53, Cloudflare,
Google, ...). You add one annotation; it does the rest.

**Global load balancing** (with **K8GB**) goes one step further: it sends users to
the *nearest healthy cluster*, across regions — so if one cluster goes down,
traffic flows to another.

## Run it

```bash
./run.sh
```

Real DNS needs a provider account, so to keep this **reliable and free** we run
external-dns with its **`inmemory`** provider. It does the full job — watches the
service, computes the record — but logs the record instead of calling a real DNS
API. You'll see it decide to create `shop.example.com`.

## Try it yourself

```bash
kubectl -n ch5 logs deploy/external-dns | grep shop.example.com
kubectl -n ch5 get svc shop          # the LoadBalancer IP the record points to
```

To use **real** DNS, you'd change the args to e.g. `--provider=aws` and give it
credentials — then those records appear in your real zone.

## Optional bonus — K8GB (global load balancing)

Full global load balancing needs **two or more clusters** and DNS delegation, so
it's not in `run.sh`. To explore it on one cluster:

```bash
helm repo add k8gb https://www.k8gb.io
helm repo update
helm -n k8gb install k8gb k8gb/k8gb --create-namespace
# then create a Gslb resource that wraps your Ingress — see https://www.k8gb.io/docs/
```

## Clean up

```bash
./cleanup.sh
```

➡️ **Next:** [Chapter 6 — Authentication](../06-authentication-oidc).
