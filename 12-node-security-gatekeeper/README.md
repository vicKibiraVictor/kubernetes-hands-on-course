# Chapter 12 — Node Security with Gatekeeper

## The idea (plain English)

Containers are *supposed* to be isolated from the node (the machine) they run on.
A few pod settings punch holes in that isolation — and attackers love them:

- **`privileged: true`** — the container can do almost anything the node can.
  Basically "root on the host". Almost never needed.
- **`hostPath` volumes** — mount the node's real filesystem into the pod. A path
  like `/` hands over the whole machine.

We use **Gatekeeper** (from Chapter 11) to **refuse any pod** that uses these.
Prevention beats detection.

## Run it

```bash
./run.sh        # needs Chapter 11 (it installs Gatekeeper)
```

It adds two rules and tests them:

| Pod | Result |
|-----|--------|
| privileged container | ❌ rejected |
| hostPath volume | ❌ rejected |
| normal pod | ✅ allowed |

## Try it yourself

```bash
kubectl apply -f manifests/bad-privileged.yaml   # denied, with the reason
kubectl get constraints                          # your active node-security rules
```

## Clean up

```bash
./cleanup.sh
```

➡️ **Next:** [Chapter 13 — Runtime Security with KubeArmor](../13-runtime-security-kubearmor).
