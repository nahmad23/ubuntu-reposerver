#!/usr/bin/env bash
# Take an immutable, timestamped snapshot of every mirror and publish it to the
# first stage (dev). Snapshots are how staged promotion works: dev always gets
# the freshest snapshot here; test/prod are advanced to it later via promote.sh.
source "$(dirname "$0")/lib.sh"

stamp="$(date +%Y%m%d-%H%M%S)"
first_stage="${STAGES[0]}"

while read -r suite _; do
  snap="${suite}-${stamp}"
  log "creating snapshot '${snap}' from mirror '${suite}'"
  aptly snapshot create "${snap}" from mirror "${suite}"
  publish_or_switch "${first_stage}" "${suite}" "${snap}"
done < <(suites)

log "snapshots created and published to '${first_stage}'"
