#!/usr/bin/env bash
# Nightly pipeline driven by the systemd timer:
#   1. sync mirrors from upstream
#   2. snapshot + publish to the first stage (dev)
#   3. prune old snapshots
# test/prod are intentionally NOT touched here; promotion stays a human decision.
source "$(dirname "$0")/lib.sh"

log "=== daily-sync start ==="
"${SCRIPT_DIR}/sync-mirrors.sh"
"${SCRIPT_DIR}/snapshot.sh"
"${SCRIPT_DIR}/cleanup.sh"
log "=== daily-sync done ==="
