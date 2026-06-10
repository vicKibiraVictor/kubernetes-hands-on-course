# Chapter 10 — A Secured Kubernetes Dashboard

## The idea (plain English)

The **Kubernetes Dashboard** is a friendly web UI for your cluster. It's also the
**first thing people deploy insecurely**. The dashboard itself isn't dangerous —
the *permissions you give it* are.

The golden rules:

1. **Never** give the dashboard `cluster-admin`.
2. **Never** enable "skip login" / anonymous access.
3. Log in as a user with **only the access they need** (here: read-only).
4. Don't expose it to the internet — reach it through `kubectl port-forward`.

## Run it

```bash
./run.sh
```

It installs the dashboard and creates a **read-only** login (`viewer`, bound to
the built-in `view` role), then prints a token. Follow the printed steps to
port-forward and log in.

## The anti-pattern (what NOT to do)

You'll see tutorials bind the dashboard SA to `cluster-admin`:

```yaml
# DON'T do this — anyone with the token now owns your cluster
roleRef: { kind: ClusterRole, name: cluster-admin }
```

If that token leaks, the whole cluster is gone. Always scope it down, like
[`manifests/viewer.yaml`](manifests/viewer.yaml) does.

## Clean up

```bash
./cleanup.sh
```

➡️ **Next:** [Chapter 11 — Policies with OPA Gatekeeper](../11-opa-gatekeeper-policies).
