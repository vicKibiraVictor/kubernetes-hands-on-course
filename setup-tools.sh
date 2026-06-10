#!/usr/bin/env bash
#
# Installs the base tools the whole course needs: kubectl, kind, helm.
# Docker must already be installed (it needs the kernel + a daemon).
#
# Tested on Linux/macOS. Re-running is safe — it skips tools you already have.
#
#   chmod +x setup-tools.sh && ./setup-tools.sh

source "$(dirname "$0")/lib.sh"

title "Course setup — base tools"

# ---- Docker (must exist already) ------------------------------------------
if command -v docker >/dev/null 2>&1; then
  step "docker found: $(docker --version)"
else
  die "Docker is not installed. Install Docker Desktop (Mac/Win) or Docker Engine (Linux): https://docs.docker.com/get-docker/"
fi

OS="$(uname -s | tr '[:upper:]' '[:lower:]')"      # linux | darwin
ARCH="$(uname -m)"; [ "$ARCH" = "x86_64" ] && ARCH="amd64"; [ "$ARCH" = "aarch64" ] && ARCH="arm64"
BIN_DIR="/usr/local/bin"
SUDO=""; [ -w "$BIN_DIR" ] || SUDO="sudo"

# ---- kubectl --------------------------------------------------------------
if command -v kubectl >/dev/null 2>&1; then
  step "kubectl found: $(kubectl version --client -o yaml 2>/dev/null | sed -n 's/.*gitVersion: *//p' | head -1)"
else
  step "installing kubectl..."
  KVER="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
  curl -fsSL -o kubectl "https://dl.k8s.io/release/${KVER}/bin/${OS}/${ARCH}/kubectl"
  chmod +x kubectl && $SUDO mv kubectl "${BIN_DIR}/kubectl"
  info "installed kubectl ${KVER}"
fi

# ---- kind -----------------------------------------------------------------
if command -v kind >/dev/null 2>&1; then
  step "kind found: $(kind --version)"
else
  step "installing kind..."
  KIND_VER="$(latest_tag kubernetes-sigs/kind)"
  curl -fsSL -o kind "https://kind.sigs.k8s.io/dl/${KIND_VER}/kind-${OS}-${ARCH}"
  chmod +x kind && $SUDO mv kind "${BIN_DIR}/kind"
  info "installed kind ${KIND_VER}"
fi

# ---- helm -----------------------------------------------------------------
if command -v helm >/dev/null 2>&1; then
  step "helm found: $(helm version --short)"
else
  step "installing helm..."
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

title "All set"
info "Next: cd 02-kind-multinode-cluster && ./run.sh   (creates the cluster the chapters use)"
