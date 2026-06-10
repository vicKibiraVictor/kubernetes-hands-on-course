# Chapter 13 — Runtime Security with KubeArmor

## The idea (plain English)

So far we've stopped *bad pods from being created* (Gatekeeper). But what about a
pod that's already running and gets compromised? **KubeArmor** watches each
container **while it runs** and blocks actions you didn't allow:

- running programs it shouldn't (e.g. a package manager, `nc`, `curl`),
- reading sensitive files (e.g. `/etc/shadow`, mounted secrets),
- unexpected network connections.

So even if an attacker gets a shell in your container, they're stuck in a padded
room.

## Run it

```bash
./run.sh
```

It installs KubeArmor, deploys a web app, shows it *can* run the package manager,
then applies a policy that **blocks** it — and tries again.

## ⚠️ One honest caveat

KubeArmor enforces using the Linux kernel's security modules (**AppArmor** or
**BPF-LSM**). On a **Linux host** that's present → the block is real. On **Docker
Desktop (Mac/Windows)** the host VM may not expose an enforcing LSM, so KubeArmor
falls back to **observe mode**: it *reports* the violation instead of blocking it.
The script tells you which mode you got. The policy itself is identical either way.

## Try it yourself

```bash
kubectl -n ch13 exec deploy/web -- apk add curl     # blocked (or logged)
kubectl get kubearmorpolicy -n ch13                 # your runtime rules
```

## Clean up

```bash
./cleanup.sh
```

➡️ **Next:** [Chapter 14 — Backups with Velero](../14-backup-velero-minio).
