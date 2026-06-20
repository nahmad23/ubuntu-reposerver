#!/usr/bin/env bash
# Create the aptly mirrors (one per suite/pocket) if they do not yet exist.
# Idempotent: safe to re-run after editing RELEASES/COMPONENTS in the config.
source "$(dirname "$0")/lib.sh"

while read -r suite url; do
  if aptly mirror list -raw 2>/dev/null | grep -qx "${suite}"; then
    log "mirror '${suite}' already exists, leaving as-is"
  else
    log "creating mirror '${suite}' (${url} ${suite} ${COMPONENTS[*]})"
    aptly mirror create \
      -architectures="$(arch_csv)" \
      "${suite}" "${url}" "${suite}" "${COMPONENTS[@]}"
  fi
done < <(suites)

log "mirror set ready"
