# Chapter 14 — Backups with Velero

## The idea (plain English)

Clusters fail. People delete the wrong thing. You migrate to a new cluster.
**Velero** backs up your Kubernetes objects (and optionally disk data) to **object
storage**, and restores them on demand.

Here the object storage is **MinIO** — a small, S3-compatible store we run in the
cluster. In the cloud you'd point Velero at real **AWS S3** instead; the commands
are identical.

```
   your namespace  ──velero backup──►  MinIO (S3)  ──velero restore──►  your namespace
```

## Run it

```bash
./run.sh
```

It installs the `velero` CLI, deploys MinIO, installs Velero, then runs the full
story:

1. **back up** the `demo-app` namespace,
2. **delete** it (a pretend disaster),
3. **restore** it from the backup,
4. **verify** the data (a ConfigMap) came back.

## Try it yourself

```bash
velero backup get                       # your backups
velero backup describe demo-backup      # details + what was saved
velero restore get                      # your restores
```

## Clean up

```bash
./cleanup.sh
```

➡️ **Next:** [Chapter 15 — Monitoring & Logging](../15-monitoring-prometheus-loki).
