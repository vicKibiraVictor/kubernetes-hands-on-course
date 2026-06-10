# Chapter 6 — Authentication ("who are you?")

## The idea (plain English)

Two different questions guard a cluster:

1. **Authentication** — *who are you?* (this chapter)
2. **Authorisation** — *what are you allowed to do?* (Chapter 7)

Kubernetes itself has **no user database**. Instead it trusts identities proven
by one of:

- **Client certificates** — a cert signed by the cluster's CA (what we use here).
- **ServiceAccount tokens** — for Pods and automation/pipelines.
- **OIDC (OpenID Connect)** — for *human* logins via an identity provider
  (Google, Okta, Azure AD, Keycloak, OpenUnison). This is the recommended way for
  real teams, because you reuse your company logins and get groups + MFA for free.

## Why we use certificates in the script (and not OIDC)

OIDC needs a running identity provider **and** reconfiguring the API server with
`--oidc-issuer-url`, `--oidc-client-id`, etc. That's a lot of moving parts for a
laptop. Certificates prove the *exact same concept* — "the cluster verifies your
identity" — with zero extra services, so the demo always works.

> In real OIDC, the cluster trusts an **id_token** (a signed JWT) from your
> provider; the token's `sub`/`email` becomes your username and `groups` becomes
> your groups — which RBAC (Chapter 7) then uses.

## Run it

```bash
./run.sh
```

It creates user **jane** (group **developers**), has the cluster sign her
certificate, builds her `jane.kubeconfig`, and proves the cluster recognises her —
while showing she **can't do anything yet** (no permissions). Chapter 7 grants them.

## Try it yourself

```bash
kubectl --kubeconfig=jane.kubeconfig auth whoami     # Username: jane, Groups: developers
kubectl --kubeconfig=jane.kubeconfig get pods        # Forbidden — authn works, authz doesn't (yet)
```

## Clean up

```bash
./cleanup.sh
```

➡️ **Next:** [Chapter 7 — RBAC & Auditing](../07-rbac-and-auditing).
