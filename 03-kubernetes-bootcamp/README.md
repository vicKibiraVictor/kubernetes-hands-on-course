# Chapter 3 — Kubernetes Bootcamp (pocket guide)

No script here — this is your **cheat sheet** to the objects you'll meet in every
later chapter. Skim it now, come back when you need it.

Mental model: **you describe what you want; Kubernetes makes it happen and keeps
it that way.** You write that "want" as YAML objects.

## The objects, in plain English

| Object | What it is |
|--------|-----------|
| **Pod** | The smallest unit — one or more containers that live and die together. You rarely make these by hand. |
| **ReplicaSet** | Keeps *N* identical Pods alive. Managed for you by a Deployment. |
| **Deployment** | The everyday workhorse for **stateless** apps. Runs N Pods, does rolling updates and rollbacks. |
| **StatefulSet** | Like a Deployment but for apps that need a stable name and their own disk (databases). |
| **DaemonSet** | Runs one Pod on **every node** (agents: logging, monitoring, security). |
| **Job / CronJob** | Run-to-completion task / on a schedule. |
| **Service** | A stable name + IP that load-balances across Pods. Types: ClusterIP (internal), NodePort, LoadBalancer. |
| **Ingress** | HTTP routing from outside, by hostname/path, into Services. Needs an ingress controller. |
| **ConfigMap** | Non-secret configuration (key/values, files) injected into Pods. |
| **Secret** | Like a ConfigMap, but for passwords/tokens/keys. |
| **Namespace** | A folder that groups objects (e.g. `team-a`, `monitoring`). |
| **PersistentVolume (PV)** | A real piece of storage in the cluster. |
| **PersistentVolumeClaim (PVC)** | A request for storage ("I need 1Gi") that binds to a PV. |
| **StorageClass** | A template that creates PVs on demand. |
| **ServiceAccount** | An identity for Pods/automation (how things authenticate). |
| **Role / ClusterRole** | A list of allowed actions (in a namespace / cluster-wide). |
| **RoleBinding / ClusterRoleBinding** | Grants a Role to a user, group, or ServiceAccount. |
| **NetworkPolicy** | A firewall for Pods — who may talk to whom. |

## The shapes you'll see again and again

- **Labels & selectors** — Pods get labels like `app: web`; Services and policies
  find Pods *by* those labels. This is the glue that connects everything.
- **Probes** — health checks: *readiness* (ready for traffic?), *liveness* (still
  alive?), *startup* (finished booting?).
- **requests / limits** — how much CPU & memory a Pod is guaranteed / capped at.

## The kubectl verbs you'll use

```bash
kubectl get <kind>            # list (add -A for all namespaces, -o wide for detail)
kubectl describe <kind>/<name>   # full detail + Events (best debugging tool)
kubectl logs <pod> [-f]       # a Pod's logs (-f = follow)
kubectl exec -it <pod> -- sh  # a shell inside a Pod
kubectl apply -f file.yaml    # create/update from YAML (the normal way)
kubectl delete -f file.yaml   # remove it
kubectl get events --sort-by=.lastTimestamp   # what just happened
```

➡️ **Next:** [Chapter 4 — Services, Load Balancing & Network Policies](../04-services-loadbalancing-network-policies).
