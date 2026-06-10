# Chapter 7 — RBAC & Auditing

## The idea (plain English)

Now that the cluster knows **who** jane is (Chapter 6), RBAC decides **what** she
may do. Four objects, two pairs:

- **Role** (namespace) / **ClusterRole** (whole cluster) — a list of *allowed
  actions*, e.g. "get and list pods".
- **RoleBinding** / **ClusterRoleBinding** — *gives* a Role to a user, group, or
  ServiceAccount.

RBAC is **additive and deny-by-default**: nobody can do anything until a binding
grants it. You build up from zero.

## Run it

```bash
./run.sh
```

It gives **jane** read-only pods in the **`dev`** namespace, then tests the edges:

| jane tries to… | result |
|----------------|--------|
| list pods in `dev` | ✅ yes |
| delete pods in `dev` | ❌ no (read-only) |
| list pods in `default` | ❌ no (her Role only covers `dev`) |

`kubectl auth can-i <verb> <resource> --as=jane` is the tool to test any
permission without logging in as her.

## Optional — turn on auditing (who did what)

Auditing records every request to the API server. It needs a one-time cluster
change, so it's not in `run.sh`. Recreate the cluster mounting
[`manifests/audit-policy.yaml`](manifests/audit-policy.yaml) and adding API-server
flags. Add this to a copy of Chapter 2's `cluster-config.yaml` (Kubernetes 1.31+):

```yaml
nodes:
  - role: control-plane
    extraMounts:
      - hostPath: ./manifests/audit-policy.yaml
        containerPath: /etc/kubernetes/audit-policy.yaml
    kubeadmConfigPatches:
      - |
        kind: ClusterConfiguration
        apiServer:
          extraArgs:
            - name: audit-policy-file
              value: /etc/kubernetes/audit-policy.yaml
            - name: audit-log-path
              value: /var/log/kubernetes/audit.log
          extraVolumes:
            - name: audit
              hostPath: /etc/kubernetes/audit-policy.yaml
              mountPath: /etc/kubernetes/audit-policy.yaml
              readOnly: true
              pathType: File
```

Then read the log inside the control-plane node:
`docker exec k8s-course-control-plane tail -f /var/log/kubernetes/audit.log`.

## Clean up

```bash
./cleanup.sh
```

➡️ **Next:** [Chapter 8 — Managing Secrets with Vault](../08-managing-secrets-vault).
