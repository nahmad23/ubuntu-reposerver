#!/usr/bin/env bash
# Promote whatever snapshot is currently live in one stage into the next stage.
# This is the controlled-rollout gate: validate dev on a canary box, then
#   promote.sh dev test    # roll the same snapshot to your test fleet
#   promote.sh test prod    # finally to production
# Optionally restrict to a single suite (e.g. only the security pocket):
#   promote.sh test prod noble-security
source "$(dirname "$0")/lib.sh"

from="${1:-}"
to="${2:-}"
only_suite="${3:-}"

usage() { die "usage: $0 <from-stage> <to-stage> [suite]   (stages: ${STAGES[*]})"; }
if [ -z "${from}" ] || [ -z "${to}" ]; then usage; fi
printf '%s\n' "${STAGES[@]}" | grep -qx "${from}" || die "unknown stage '${from}'"
printf '%s\n' "${STAGES[@]}" | grep -qx "${to}"   || die "unknown stage '${to}'"

promoted=0
while read -r suite _; do
  [ -n "${only_suite}" ] && [ "${suite}" != "${only_suite}" ] && continue
  snap="$(current_snapshot "${from}" "${suite}")"
  if [ -z "${snap}" ]; then
    warn "no snapshot live in '${from}' for '${suite}', skipping"
    continue
  fi
  log "promoting '${suite}': ${from} -> ${to}  (${snap})"
  publish_or_switch "${to}" "${suite}" "${snap}"
  promoted=$((promoted + 1))
done < <(suites)

[ "${promoted}" -gt 0 ] || die "nothing promoted (does '${from}' have published snapshots yet?)"
log "promoted ${promoted} suite(s) from '${from}' to '${to}'"
