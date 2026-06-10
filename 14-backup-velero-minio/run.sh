#!/usr/bin/env bash
#
# Chapter 14 — Backups with Velero + MinIO.
# We back up a namespace to object storage, DELETE it (simulating disaster),
# then restore it from the backup.

source "$(dirname "$0")/../lib.sh"
cd "$(dirname "$0")"

need kubectl curl tar
need_cluster
title "Chapter 14 — Backups with Velero"

# ── install the velero CLI if missing (pinned to match the AWS plugin) ─────
VELERO_VER="v1.14.1"
if ! command -v velero >/dev/null 2>&1; then
  step "installing the velero CLI ${VELERO_VER}"
  OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
  ARCH="$(uname -m)"; [ "$ARCH" = "x86_64" ] && ARCH="amd64"; [ "$ARCH" = "aarch64" ] && ARCH="arm64"
  curl -fsSL "https://github.com/vmware-tanzu/velero/releases/download/${VELERO_VER}/velero-${VELERO_VER}-${OS}-${ARCH}.tar.gz" -o velero.tgz
  tar xzf velero.tgz
  SUDO=""; [ -w /usr/local/bin ] || SUDO="sudo"; $SUDO mv "velero-${VELERO_VER}-${OS}-${ARCH}/velero" /usr/local/bin/
  rm -rf velero.tgz "velero-${VELERO_VER}-${OS}-${ARCH}"
fi
info "velero $(velero version --client-only 2>/dev/null | sed -n 's/Version: //p' | head -1)"

# ── MinIO (the S3 store) ───────────────────────────────────────────────────
step "deploying MinIO + creating the 'velero' bucket"
kubectl apply -f manifests/minio.yaml
kubectl -n velero rollout status deploy/minio --timeout=180s
kubectl -n velero wait --for=condition=complete job/minio-create-bucket --timeout=180s

# ── install Velero, pointed at MinIO ───────────────────────────────────────
step "installing Velero (backups go to MinIO)"
cat > credentials-velero <<'EOF'
[default]
aws_access_key_id=minio
aws_secret_access_key=minio123
EOF
velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.10.0 \
  --bucket velero \
  --secret-file ./credentials-velero \
  --use-volume-snapshots=false \
  --backup-location-config region=minio,s3ForcePathStyle="true",s3Url=http://minio.velero.svc:9000 \
  --wait
rm -f credentials-velero

# ── the demo: back up -> delete -> restore ─────────────────────────────────
step "deploying the demo app we'll back up"
kubectl apply -f manifests/demo-app.yaml
kubectl -n demo-app rollout status deploy/web --timeout=120s

step "BACKUP — saving namespace demo-app to MinIO"
velero backup create demo-backup --include-namespaces demo-app --wait

step "DISASTER — deleting the whole namespace"
kubectl delete namespace demo-app --wait=true
info "gone:  $(kubectl get ns demo-app 2>&1 || true)"

step "RESTORE — bringing it back from the backup"
velero restore create demo-restore --from-backup demo-backup --wait

step "TEST — is the data back?"
sleep 5
kubectl get ns demo-app
MSG="$(kubectl -n demo-app get configmap important-data -o jsonpath='{.data.message}' 2>/dev/null || true)"
info "recovered configmap says: \"${MSG}\"   (expect: please don't lose me)"

title "Done"
info "List backups:  velero backup get      Describe:  velero backup describe demo-backup"
info "Clean up:  ./cleanup.sh"
