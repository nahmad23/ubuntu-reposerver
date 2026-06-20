#!/usr/bin/env bash
# Shared functions and derived configuration for all reposerver scripts.
# Source this at the top of every script: source "$(dirname "$0")/lib.sh"
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=../config/reposerver.env
source "${REPO_DIR}/config/reposerver.env"

# --- Derived paths -----------------------------------------------------------
export GNUPGHOME="${APTLY_HOME}/.gnupg"
export HOME="${APTLY_HOME}"           # so aptly finds ~/.aptly.conf when run by systemd
GPG_KEY_ID_FILE="${APTLY_HOME}/gpg-key-id"
STATE_DIR="${APTLY_ROOT}/state"

# --- Logging helpers ---------------------------------------------------------
log()  { echo "[$(date -Is)] $*"; }
warn() { echo "[$(date -Is)] WARN: $*" >&2; }
die()  { echo "[$(date -Is)] ERROR: $*" >&2; exit 1; }

# --- Small utilities ---------------------------------------------------------
# Comma-separated architecture list, e.g. "amd64,arm64".
arch_csv() { local IFS=,; echo "${ARCHES[*]}"; }

# The long GPG key id used for signing, or empty if not yet generated.
gpg_key_id() { if [ -f "${GPG_KEY_ID_FILE}" ]; then cat "${GPG_KEY_ID_FILE}"; fi; }

# Emit one line per suite to mirror: "<suite> <upstream-url>".
# Pockets: <release>, <release>-updates, <release>-security (+ -backports opt).
suites() {
  local rel
  for rel in "${RELEASES[@]}"; do
    echo "${rel}          ${ARCHIVE_URL}"
    echo "${rel}-updates  ${ARCHIVE_URL}"
    echo "${rel}-security ${SECURITY_URL}"
    if [ "${INCLUDE_BACKPORTS}" = "true" ]; then
      echo "${rel}-backports ${ARCHIVE_URL}"
    fi
  done
}

# Publish (first time) or switch (subsequent) a snapshot to a stage/suite,
# then record the pointer in the state dir for auditing and promotion.
#   publish_or_switch <stage> <suite> <snapshot>
publish_or_switch() {
  local stage="$1" suite="$2" snap="$3" key
  key="$(gpg_key_id)"
  [ -n "${key}" ] || die "GPG signing key not found (${GPG_KEY_ID_FILE}); run install.sh first."

  if aptly publish list -raw 2>/dev/null | awk '{print $1" "$2}' | grep -qx "${stage} ${suite}"; then
    log "switch ${stage}/${suite} -> ${snap}"
    aptly publish switch -gpg-key="${key}" "${suite}" "${stage}" "${snap}"
  else
    log "publish ${stage}/${suite} -> ${snap}"
    aptly publish snapshot -distribution="${suite}" -gpg-key="${key}" "${snap}" "${stage}"
  fi

  mkdir -p "${STATE_DIR}/${stage}"
  echo "${snap}" > "${STATE_DIR}/${stage}/${suite}"
  echo "$(date -Is) ${stage} ${suite} ${snap}" >> "${STATE_DIR}/history.log"
}

# The snapshot currently pointed at by a stage/suite, or empty.
current_snapshot() {
  local f="${STATE_DIR}/${1}/${2}"
  if [ -f "${f}" ]; then cat "${f}"; fi
}
