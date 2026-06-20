#!/usr/bin/env bash
# Pull the latest package metadata and .debs from upstream into every mirror.
# This is the network-heavy step. The first run downloads tens of GB per
# release; subsequent runs only fetch deltas.
source "$(dirname "$0")/lib.sh"

while read -r suite url; do
  log "updating mirror '${suite}' from ${url}"
  aptly mirror update "${suite}"
done < <(suites)

log "all mirrors updated"
