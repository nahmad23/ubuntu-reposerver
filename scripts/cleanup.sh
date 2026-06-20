#!/usr/bin/env bash
# Retain the newest SNAPSHOT_KEEP snapshots per suite and drop older ones, then
# garbage-collect package files no longer referenced by any snapshot/publish.
# Published snapshots are never dropped (aptly refuses), so this is safe.
source "$(dirname "$0")/lib.sh"

keep="${SNAPSHOT_KEEP:-6}"

while read -r suite _; do
  # Snapshots for this suite are named "<suite>-<timestamp>"; list newest first.
  mapfile -t snaps < <(aptly snapshot list -raw 2>/dev/null \
    | grep -E "^${suite}-[0-9]" | sort -r)

  if [ "${#snaps[@]}" -le "${keep}" ]; then
    continue
  fi

  for snap in "${snaps[@]:${keep}}"; do
    if aptly snapshot drop "${snap}" 2>/dev/null; then
      log "dropped old snapshot '${snap}'"
    else
      log "keeping '${snap}' (still published)"
    fi
  done
done < <(suites)

log "running aptly db cleanup"
aptly db cleanup
log "cleanup complete"
