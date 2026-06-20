#!/usr/bin/env bash
# Configure an Ubuntu server to pull patches from the reposerver.
# Run on the CLIENT machine as root:
#   sudo ./setup-client.sh <stage> <reposerver-host> [release]
# Examples:
#   sudo ./setup-client.sh prod reposerver.example.com
#   sudo ./setup-client.sh test reposerver.example.com noble
#
# It installs the repo signing key and writes a deb822 .sources file. By default
# it does NOT disable the stock Ubuntu sources; pass --replace-default to comment
# them out so the box patches exclusively from your mirror.
set -euo pipefail

REPLACE_DEFAULT="false"
args=()
for a in "$@"; do
  case "${a}" in
    --replace-default) REPLACE_DEFAULT="true" ;;
    -h|--help)
      sed -n '2,12p' "$0"; exit 0 ;;
    *) args+=("${a}") ;;
  esac
done
set -- "${args[@]}"

STAGE="${1:-}"
HOST="${2:-}"
RELEASE="${3:-$(. /etc/os-release 2>/dev/null && echo "${VERSION_CODENAME}")}"
COMPONENTS="main restricted universe multiverse"

if [ -z "${STAGE}" ] || [ -z "${HOST}" ]; then echo "usage: $0 <stage> <reposerver-host> [release] [--replace-default]"; exit 1; fi
[ -n "${RELEASE}" ] || { echo "ERROR: could not detect release codename; pass it explicitly"; exit 1; }
[ "$(id -u)" -eq 0 ] || { echo "ERROR: run as root"; exit 1; }

BASE_URL="http://${HOST}/${STAGE}"
KEY_URL="http://${HOST}/reposerver.gpg"   # key lives at web root, not under a stage
KEYRING="/etc/apt/keyrings/ubuntu-reposerver.gpg"

echo "==> Installing signing key from ${KEY_URL}"
install -d -m 0755 /etc/apt/keyrings
curl -fsSL "${KEY_URL}" -o "${KEYRING}"
chmod 0644 "${KEYRING}"

echo "==> Writing /etc/apt/sources.list.d/ubuntu-reposerver.sources"
cat > /etc/apt/sources.list.d/ubuntu-reposerver.sources <<EOF
# Managed by ubuntu-reposerver setup-client.sh
Types: deb
URIs: ${BASE_URL}
Suites: ${RELEASE} ${RELEASE}-updates ${RELEASE}-security
Components: ${COMPONENTS}
Signed-By: ${KEYRING}
EOF

if [ "${REPLACE_DEFAULT}" = "true" ]; then
  echo "==> Disabling stock Ubuntu sources"
  ts="$(date +%Y%m%d-%H%M%S)"
  for f in /etc/apt/sources.list /etc/apt/sources.list.d/ubuntu.sources; do
    [ -f "${f}" ] && ! grep -q ubuntu-reposerver "${f}" && mv "${f}" "${f}.disabled-${ts}" && echo "    moved ${f} -> ${f}.disabled-${ts}"
  done
fi

echo "==> Refreshing apt"
apt-get update

cat <<EOF

Client now pulls from stage '${STAGE}' on ${HOST} for ${RELEASE}.
Apply patches with:  sudo apt-get upgrade   (or unattended-upgrades)
EOF
