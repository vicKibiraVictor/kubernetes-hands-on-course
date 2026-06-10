# Chapter 8 — Managing Secrets with Vault

## The idea (plain English)

A Kubernetes **Secret** is only *base64-encoded* — not encrypted — and it sits in
the cluster's database. For real secrets (DB passwords, API keys) teams keep the
**source of truth outside** the cluster in a dedicated secrets manager like
**HashiCorp Vault**, which encrypts, audits, and rotates them.

But your apps still want a normal Kubernetes Secret. The **External Secrets
Operator (ESO)** bridges the two: it reads from Vault and **creates/updates a
Kubernetes Secret** for you. Change it in Vault → ESO re-syncs automatically.

```
   Vault (real secret)  ──read──►  ESO  ──creates──►  Kubernetes Secret  ──►  your app
```

## Run it

```bash
./run.sh
```

It installs **Vault** (dev mode — unsealed, easy), stores `secret/demo`, installs
**ESO**, then wires them together so a Kubernetes Secret named `app-secret`
appears holding the value from Vault.

> Dev mode keeps Vault unsealed with a root token of `root` — great for learning,
> **never** for production. Real Vault is sealed and uses Kubernetes auth instead
> of a static token.

## Try it yourself

```bash
kubectl -n app get externalsecret                       # status: SecretSynced
kubectl -n app get secret app-secret -o jsonpath='{.data.password}' | base64 -d   # s3cr3t

# change it in Vault, then watch ESO update the Secret within ~15s:
kubectl -n vault exec vault-0 -- sh -c \
  'VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=root vault kv put secret/demo password=changed'
```

## Clean up

```bash
./cleanup.sh
```

➡️ **Next:** [Chapter 9 — Multitenancy with vCluster](../09-multitenancy-vcluster).
