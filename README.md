# ubuntu-reposerver

A self-hosted **Ubuntu apt mirror / patch server** built on
[`aptly`](https://www.aptly.info/), with **staged snapshot promotion**
(`dev → test → prod`) so your servers only ever install patches you have
validated. Mirrors are served over **Nginx** and kept fresh by **systemd
timers**.

```
                       nightly timer
 upstream Ubuntu  ──►  aptly mirrors  ──►  snapshot ──► [dev]
 (archive +            (per pocket)         (dated,      │  promote (manual)
  security)                                 immutable)   ▼
                                                        [test]
                                                         │  promote (manual)
                                                         ▼
                                                        [prod] ──► your servers
                                                                    (Nginx/HTTP)
```

## What you get

- Mirrors of **Ubuntu 24.04 (Noble)** and **22.04 (Jammy)** — the
  `release`, `-updates`, and `-security` pockets — for `amd64`.
  All configurable in [`config/reposerver.env`](config/reposerver.env).
- **Immutable, dated snapshots** and three promotion channels (`dev`,
  `test`, `prod`). Production never changes underneath you.
- A **GPG-signed** repository; clients trust one exported key.
- A nightly **systemd timer** that syncs, snapshots, publishes to `dev`,
  and prunes old snapshots.
- One-command **client onboarding**.

## Requirements

- A dedicated Ubuntu 22.04/24.04 host with plenty of disk. Budget roughly
  **~150 GB per release** if mirroring all components for `amd64` (much less
  if you trim `COMPONENTS` or set `INCLUDE_BACKPORTS=false`, which is the
  default). Snapshots are cheap — they share the package pool via hardlinks.
- Outbound HTTP to `archive.ubuntu.com` and `security.ubuntu.com` (or a
  closer mirror you set in the config).

## Install (on the reposerver host)

```bash
git clone https://github.com/nahmad23/ubuntu-reposerver.git
cd ubuntu-reposerver
# Review/edit config first (releases, arches, host, etc.)
$EDITOR config/reposerver.env
sudo ./install.sh
```

`install.sh` installs `aptly`/`nginx`/`gnupg`, creates the `aptly` system
user, generates a signing key, deploys the code to `/opt/ubuntu-reposerver`,
wires up the timer and Nginx, and creates the mirrors. It does **not** start
the large initial sync — do that yourself:

```bash
# Long-running: run inside tmux/screen.
sudo -u aptly HOME=/srv/aptly /opt/ubuntu-reposerver/scripts/daily-sync.sh
```

When it finishes, the `dev` channel is live.

## Day-to-day operations (`repoctl`)

`install.sh` symlinks `repoctl` into `/usr/local/bin`. Run it as the `aptly`
user:

```bash
sudo -u aptly repoctl status                 # mirrors, stages, snapshot counts
sudo -u aptly repoctl sync                   # pull upstream updates
sudo -u aptly repoctl snapshot               # snapshot + publish to dev
sudo -u aptly repoctl promote dev test       # advance test to dev's snapshot
sudo -u aptly repoctl promote test prod      # advance prod to test's snapshot
sudo -u aptly repoctl promote test prod noble-security   # one pocket only
sudo -u aptly repoctl cleanup                # prune old snapshots
```

The nightly timer runs the full `sync → snapshot → cleanup` pipeline and
keeps **only `dev`** current. `test` and `prod` move **only** when you
promote, which is the whole point: you test patches before production gets
them.

See [`docs/OPERATIONS.md`](docs/OPERATIONS.md) for the full runbook,
including rollback, disk management, and adding releases/architectures.

## Onboard a client server

On each Ubuntu server you want to patch from the mirror:

```bash
# From a checkout of this repo, or copy client/setup-client.sh over:
sudo ./client/setup-client.sh prod reposerver.example.com
# Optionally make the mirror the ONLY source:
sudo ./client/setup-client.sh prod reposerver.example.com --replace-default
```

This installs the signing key into `/etc/apt/keyrings/` and writes a deb822
`*.sources` file pointing at the chosen stage. Then patch as usual:

```bash
sudo apt-get update && sudo apt-get upgrade
```

A manual/example source file is in
[`client/ubuntu-reposerver.sources.example`](client/ubuntu-reposerver.sources.example).

## Repository layout

| Path | Purpose |
|------|---------|
| `config/reposerver.env` | Single source of truth for all settings |
| `install.sh` | One-shot host provisioning (run as root) |
| `scripts/` | mirror create/sync, snapshot, promote, cleanup, nightly pipeline |
| `bin/repoctl` | Operator CLI wrapper |
| `systemd/` | `aptly-sync.service` + `.timer` |
| `nginx/reposerver.conf` | Web server site serving the published tree |
| `client/` | Client onboarding script + example source |
| `docs/OPERATIONS.md` | Runbook |

## Notes

- Everything is driven by `config/reposerver.env`. Change releases,
  components, architectures, stages, retention, or upstream URLs there and
  re-run `repoctl init` / `install.sh`.
- Snapshots are immutable, so a bad upstream update can always be rolled
  back by re-promoting the previous snapshot (see the runbook).
- HTTP is used because apt verifies content via the repo's GPG signature.
  Put it behind TLS (terminate at Nginx or a load balancer) if you want
  transport encryption too.
