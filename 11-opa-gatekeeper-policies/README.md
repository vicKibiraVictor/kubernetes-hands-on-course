# Chapter 11 — Policies with OPA Gatekeeper

## The idea (plain English)

RBAC answers *"who can do this?"* But some rules aren't about **who** — they're
about **what**. For example: "every namespace must have an `owner` label", or "no
container may run as root". RBAC can't express those.

**OPA Gatekeeper** can. It's an **admission controller**: it inspects every object
*as it's created* and rejects the ones that break your rules. Two pieces:

- **ConstraintTemplate** — defines a *type* of rule, written in **Rego** (OPA's
  policy language). Think of it as a reusable function.
- **Constraint** — *uses* that template with real values, e.g. "labels: [owner]".

## Run it

```bash
./run.sh
```

It installs Gatekeeper, defines a "required labels" rule, turns on "namespaces
need an `owner` label", then proves it:

- a namespace **without** the label → **rejected** ❌
- a namespace **with** it → **allowed** ✅

## Try it yourself

```bash
kubectl create ns whatever                 # rejected (no owner label)
kubectl get constraints                    # your active rules
kubectl get k8srequiredlabels ns-must-have-owner -o yaml   # see existing violations it found
```

## Clean up

```bash
./cleanup.sh      # keeps Gatekeeper installed — Chapter 12 builds on it
```

➡️ **Next:** [Chapter 12 — Node Security with Gatekeeper](../12-node-security-gatekeeper).
