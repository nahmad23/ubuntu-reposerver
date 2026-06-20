#!/usr/bin/env bash
# =============================================================================
# install.sh - provision this host as an Ubuntu apt mirror / patch reposerver.
# Run as root on a fresh Ubuntu 22.04/24.04 server:  sudo ./install.sh
#
# It is idempotent: safe to re-run after changing config/reposerver.env.
# It does NOT start the (large) initial sync - it prints how to do that at the
# end so you can run it under tmux/screen.
# =============================================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config/reposerver.env
source "${REPO_DIR}/config/reposerver.env"

INSTALL_DIR="/opt/ubuntu-reposerver"

[ "$(id -u)" -eq 0 ] || { echo "ERROR: run as root (sudo ./install.sh)"; exit 1; }

echo "==> Installing packages (aptly, nginx, gnupg)"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y aptly nginx gnupg ca-certificates

echo "==> Creating system user '${APTLY_USER}' (home ${APTLY_HOME})"
if ! id "${APTLY_USER}" >/dev/null 2>&1; then
  useradd --system --create-home --home-dir "${APTLY_HOME}" \
          --shell /usr/sbin/nologin "${APTLY_USER}"
fi
install -d -o "${APTLY_USER}" -g "${APTLY_USER}" -m 0755 \
  "${APTLY_HOME}" "${APTLY_ROOT}" "${APTLY_ROOT}/public" "${APTLY_ROOT}/state"
install -d -o "${APTLY_USER}" -g "${APTLY_USER}" -m 0700 "${APTLY_HOME}/.gnupg"

echo "==> Deploying code to ${INSTALL_DIR}"
mkdir -p "${INSTALL_DIR}"
cp -a "${REPO_DIR}/." "${INSTALL_DIR}/"
chmod +x "${INSTALL_DIR}"/scripts/*.sh "${INSTALL_DIR}"/bin/* "${INSTALL_DIR}"/install.sh "${INSTALL_DIR}"/client/*.sh
ln -sf "${INSTALL_DIR}/bin/repoctl" /usr/local/bin/repoctl

echo "==> Writing aptly config (~${APTLY_HOME}/.aptly.conf)"
arch_json="$(printf '"%s",' "${ARCHES[@]}")"; arch_json="[${arch_json%,}]"
cat > "${APTLY_HOME}/.aptly.conf" <<EOF
{
  "rootDir": "${APTLY_ROOT}",
  "downloadConcurrency": 8,
  "downloadSpeedLimit": 0,
  "architectures": ${arch_json},
  "dependencyFollowSuggests": false,
  "dependencyFollowRecommends": false,
  "gpgDisableSign": false,
  "gpgDisableVerify": false,
  "FileSystemPublishEndpoints": {}
}
EOF
chown "${APTLY_USER}:${APTLY_USER}" "${APTLY_HOME}/.aptly.conf"

echo "==> Ensuring GPG signing key exists"
if ! sudo -u "${APTLY_USER}" GNUPGHOME="${APTLY_HOME}/.gnupg" \
       gpg --list-keys "${GPG_KEY_EMAIL}" >/dev/null 2>&1; then
  echo "    generating new 4096-bit signing key for ${GPG_KEY_EMAIL}"
  sudo -u "${APTLY_USER}" GNUPGHOME="${APTLY_HOME}/.gnupg" gpg --batch --gen-key <<EOF
%no-protection
Key-Type: RSA
Key-Length: 4096
Name-Real: ${GPG_KEY_NAME}
Name-Email: ${GPG_KEY_EMAIL}
Expire-Date: 0
%commit
EOF
fi
KEY_ID="$(sudo -u "${APTLY_USER}" GNUPGHOME="${APTLY_HOME}/.gnupg" \
  gpg --list-keys --with-colons "${GPG_KEY_EMAIL}" | awk -F: '/^pub/{print $5; exit}')"
[ -n "${KEY_ID}" ] || { echo "ERROR: could not determine GPG key id"; exit 1; }
echo "${KEY_ID}" | sudo -u "${APTLY_USER}" tee "${APTLY_HOME}/gpg-key-id" >/dev/null
echo "    signing key id: ${KEY_ID}"

echo "==> Exporting public key for clients (-> ${APTLY_ROOT}/public/reposerver.gpg)"
# Dearmored key for /etc/apt/keyrings + signed-by (preferred on modern Ubuntu).
sudo -u "${APTLY_USER}" GNUPGHOME="${APTLY_HOME}/.gnupg" \
  gpg --export "${KEY_ID}" | sudo -u "${APTLY_USER}" tee "${APTLY_ROOT}/public/reposerver.gpg" >/dev/null
# ASCII-armored copy for convenience.
sudo -u "${APTLY_USER}" GNUPGHOME="${APTLY_HOME}/.gnupg" \
  gpg --armor --export "${KEY_ID}" | sudo -u "${APTLY_USER}" tee "${APTLY_ROOT}/public/reposerver.asc" >/dev/null

echo "==> Installing systemd units"
install -m 0644 "${INSTALL_DIR}/systemd/aptly-sync.service" /etc/systemd/system/
install -m 0644 "${INSTALL_DIR}/systemd/aptly-sync.timer"   /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now aptly-sync.timer

echo "==> Configuring nginx"
install -m 0644 "${INSTALL_DIR}/nginx/reposerver.conf" /etc/nginx/sites-available/reposerver.conf
ln -sf /etc/nginx/sites-available/reposerver.conf /etc/nginx/sites-enabled/reposerver.conf
# Drop the stock default site if present so our default_server wins.
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl reload nginx

echo "==> Creating mirrors from config"
sudo -u "${APTLY_USER}" HOME="${APTLY_HOME}" "${INSTALL_DIR}/scripts/create-mirrors.sh"

cat <<EOF

=============================================================================
 Ubuntu reposerver installed.

 Releases : ${RELEASES[*]}
 Arches   : ${ARCHES[*]}
 Stages   : ${STAGES[*]}
 Web root : http://${REPOSERVER_HOST}/   (served from ${APTLY_ROOT}/public)
 Signing  : ${KEY_ID}

 NEXT STEPS
 ----------
 1. Run the first sync NOW (downloads many GB - use tmux/screen):
        sudo -u ${APTLY_USER} HOME=${APTLY_HOME} ${INSTALL_DIR}/scripts/daily-sync.sh

    After it finishes, the '${STAGES[0]}' channel is live. Check it with:
        repoctl status

 2. Validate, then promote to later stages:
        sudo -u ${APTLY_USER} repoctl promote ${STAGES[0]} ${STAGES[1]}
        sudo -u ${APTLY_USER} repoctl promote ${STAGES[1]} ${STAGES[2]:-${STAGES[1]}}

 3. Point a client server at the mirror:
        sudo ./client/setup-client.sh <stage> ${REPOSERVER_HOST}
    (see client/setup-client.sh --help)

 The nightly timer 'aptly-sync.timer' is enabled and will keep '${STAGES[0]}'
 fresh. test/prod only move when you promote.
=============================================================================
EOF
