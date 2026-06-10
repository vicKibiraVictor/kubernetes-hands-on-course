#!/usr/bin/env bash
#
# Shared helpers used by every chapter's run.sh.
# Source it near the top of a script:  source "../lib.sh"
#
# It gives you: coloured output (title/step/info/warn/die), a tool checker
# (need), a cluster check (need_cluster), wait helpers, and latest_tag.

set -euo pipefail

# ---- pretty output --------------------------------------------------------
if [ -t 1 ]; then
  _B=$'\033[1m'; _G=$'\033[32m'; _Y=$'\033[33m'; _R=$'\033[31m'; _C=$'\033[36m'; _X=$'\033[0m'
else
  _B=""; _G=""; _Y=""; _R=""; _C=""; _X=""
fi

title() { echo; echo "${_B}${_C}=== $* ===${_X}"; echo; }   # big section header
step()  { echo "${_B}${_G}==> $*${_X}"; }                    # a step starting
info()  { echo "    $*"; }                                   # detail line
warn()  { echo "${_Y}!!  $*${_X}" >&2; }                     # warning
die()   { echo "${_R}xx  $*${_X}" >&2; exit 1; }             # fatal, stops here

# ---- tool / cluster checks ------------------------------------------------
# Usage: need kubectl helm docker
need() {
  local missing=0 t
  for t in "$@"; do
    if ! command -v "$t" >/dev/null 2>&1; then
      warn "required tool not found: $t"
      missing=1
    fi
  done
  [ "$missing" -eq 0 ] || die "install the tool(s) above first — run ../setup-tools.sh or see the root README."
}

# The kind cluster every chapter from 02 onward uses.
CLUSTER_NAME="${CLUSTER_NAME:-k8s-course}"

# Make sure kubectl can actually talk to a cluster.
need_cluster() {
  kubectl cluster-info >/dev/null 2>&1 \
    || die "no cluster reachable. Create it first:  cd ../02-kind-multinode-cluster && ./run.sh"
}

# ---- waits ----------------------------------------------------------------
# wait_rollout <namespace> <type/name> [timeout]
wait_rollout() { kubectl -n "$1" rollout status "$2" --timeout="${3:-180s}"; }

# wait_ready <namespace> <label-selector> [timeout]
wait_ready() { kubectl -n "$1" wait --for=condition=Ready pod -l "$2" --timeout="${3:-180s}"; }

# ---- misc -----------------------------------------------------------------
# latest_tag <owner/repo>  -> e.g. v0.16.1   (portable: no grep -P)
latest_tag() {
  curl -fsSL "https://api.github.com/repos/$1/releases/latest" \
    | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1
}

# Print the directory this lib lives in (the repo root).
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
