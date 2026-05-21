<div align="center">

# 📦 ecobackup

**A robust, log-aware Bash wrapper around `ecoDMSBackupConsole`**
*Battle-tested retention · embedded crontabs · Discord notifications · zero external dependencies*

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
[![Shell](https://img.shields.io/badge/shell-bash%205%2B-1f425f.svg)](https://www.gnu.org/software/bash/)
[![ecoDMS](https://img.shields.io/badge/ecoDMS-22%20%7C%2024%20%7C%2026-blue.svg)](https://www.ecodms.de/)
[![Debian](https://img.shields.io/badge/Debian-11%20%7C%2012%20%7C%2013-a81d33.svg)](https://www.debian.org/)
[![PRs welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](#contributing)

</div>

---

`ecoDMSBackupConsole` ships with ecoDMS but does **only one thing**: dump a zip into a directory. No rotation. No verification. No notifications. No exit-code contract.

This wrapper fills the gap with a single `bash` script (~450 lines, no deps beyond `curl` and `python3` for JSON encoding) you can deploy in under a minute.

```
   ┌─────────┐    ┌──────────────────────┐    ┌───────────────┐
   │  cron   │───▶│      ecobackup       │───▶│ BackupConsole │
   └─────────┘    └──────────┬───────────┘    └───────────────┘
                             │
                  ┌──────────┴──────────┐
                  ▼                     ▼
            ┌──────────┐          ┌──────────┐
            │  prune   │          │  notify  │ ─── Discord 🛰
            │ (mtime)  │          │ (webhook)│
            └──────────┘          └──────────┘
```

---

## Table of Contents

- [Features](#-features)
- [Quick Start](#-quick-start)
- [Configuration](#-configuration)
- [Usage](#-usage)
- [Notifications](#-notifications)
- [Cron Layout](#-cron-layout)
- [Architecture Notes](#-architecture-notes)
- [Production Story: A Six-Week Silent Failure](#-production-story-a-six-week-silent-failure)
- [Roadmap](#-roadmap)
- [Contributing](#-contributing)
- [License](#-license)

---

## ✨ Features

| | |
|---|---|
| 🔒 **Atomic locking** | per-host lockfile prevents overlapping runs |
| 🗑️ **Script-internal retention** | `find -mtime +N -delete`, decoupled from cron exit codes (no more "cleanup never ran because logging failed") |
| 📣 **Pluggable notifications** | Discord webhook out of the box; adapter-friendly for ntfy/Slack/etc. |
| ⚙️ **Embedded crontabs** | `ecobackup -i` installs cron entries idempotently, no separate cron files to maintain |
| 🧪 **Smoke-test friendly** | `ecobackup -t` validates notify, `ecobackup -i print user` is a dry-run |
| 🛠 **Permission self-healing** | works around ecoDMS' `dpkg postinst` resetting `BackupConsole` to `root:root 700` after every update |
| 📦 **Zero dependencies** | `bash`, `curl`, `python3` (Debian default install) |
| 🌐 **Site-agnostic** | all paths via `/etc/ecobackup/ecobackup.conf` — fork and ship without renaming |

---

## 🚀 Quick Start

```bash
# 1. Get the script onto your ecoDMS host
sudo install -m 755 -o root -g root ecobackup /usr/bin/ecobackup

# 2. Configure paths (see ecobackup.conf.example)
sudo install -d /etc/ecobackup
sudo cp ecobackup.conf.example /etc/ecobackup/ecobackup.conf
sudo $EDITOR /etc/ecobackup/ecobackup.conf

# 3. (Optional) configure Discord webhook
sudo cp notify.conf.example /etc/ecobackup/notify.conf
sudo chmod 600 /etc/ecobackup/notify.conf
sudo $EDITOR /etc/ecobackup/notify.conf

# 4. One-time permissions setup (chown + chmod + add user to ecodms group)
ecobackup -s
# log out + back in so group membership takes effect

# 5. Install cron entries (idempotent — safe to re-run)
sudo ecobackup -i

# 6. Smoke-test
ecobackup -t                 # sends a Discord test message
ecobackup -d                 # runs a full daily backup
```

---

## ⚙️ Configuration

Two files, both optional. The script ships with safe defaults; configs override.

### `/etc/ecobackup/ecobackup.conf` (paths, retention)

```bash
DAILY_DIR=/mnt/backup/ecodms/daily
DAILY_KEEP_DAYS=7

MONTHLY_DIR=/mnt/backup/ecodms/monthly
MONTHLY_KEEP_DAYS=90

REMOTE_DIR=/mnt/remote/ecodms
REMOTE_KEEP_DAYS=14

# Optional second cloud target driven via `-a` cron slot
TELEKOM_DIR="/mnt/cloud/EcoDMS Backup/monthly"
TELEKOM_KEEP_DAYS=90

# Cron installer
CRON_USER=youruser
CRON_SNAPSHOT_DIR=/mnt/remote/ecodms/crons
SCRIPT_MIRROR_DIRS=/mnt/remote/ecodms/ecobackuptool/ecobackup
```

See [`ecobackup.conf.example`](ecobackup.conf.example) for the full reference.

### `/etc/ecobackup/notify.conf` (webhook secrets) — **mode 600!**

```bash
NOTIFY_DISCORD_WEBHOOK=https://discord.com/api/webhooks/<id>/<token>
NOTIFY_ENABLED=1
```

---

## 🧰 Usage

| Command | Effect |
|---|---|
| `ecobackup -d` | Daily backup (retention `DAILY_KEEP_DAYS`) |
| `ecobackup -m` | Monthly backup |
| `ecobackup -r` | Remote backup |
| `ecobackup -a <path>` | Backup to arbitrary path (`ECOBACKUP_KEEP_DAYS=N` to override retention) |
| `ecobackup -c` | Interactive: prompt for path, no auto-prune |
| `ecobackup -s` | One-time permission fix (BackupConsole + group membership) |
| `ecobackup -i` | Install user crontab (and root crontab if run via `sudo`) |
| `ecobackup -i print user` | Dry-run: print the would-be user crontab |
| `ecobackup -i print root` | Dry-run: print the would-be root crontab |
| `ecobackup -t` | Send a test notification |
| `ecobackup -h` | Help with current resolved config |

---

## 📣 Notifications

Every backup run produces a Discord embed:

```
┌──────────────────────────────────────────────────────────┐
│ 🟢 Tägliches Backup ok                                   │
├──────────────────────────────────────────────────────────┤
│ Ziel: `/mnt/backup/ecodms/daily`                         │
│ Dauer: 27s                                               │
│ Größe: 5.4G                                              │
│ prune: 1 gelöscht (>7d), 5.3GiB frei                     │
│                                                          │
│ ecobackup on ecodms · 2026-05-21 01:35:34 UTC            │
└──────────────────────────────────────────────────────────┘
```

Color-coded by level:
- 🟢 `ok` — backup succeeded, retention applied
- 🟡 `warn` — low disk, lock contention, etc.
- 🔴 `err` — backup failed (includes exit code + log path)

The Discord transport is a small adapter. Swapping in ntfy/Slack/Telegram is ~20 lines — see `_notify_discord()` in the script.

---

## ⏰ Cron Layout

ecobackup ships its own crontabs and installs them via `ecobackup -i`. Re-running is idempotent (diff-based — only writes when content actually differs).

**User crontab** (`crontab -l` after `ecobackup -i`):

```cron
35 1 * * *   /usr/bin/ecobackup -d
55 1 * * *   /usr/bin/ecobackup -r
45 1 1 * *   /usr/bin/ecobackup -m
35 2 1 * *   ECOBACKUP_KEEP_DAYS=90 /usr/bin/ecobackup -a "/mnt/cloud/EcoDMS Backup/monthly"
5  3 * * *   /usr/bin/crontab -l > /mnt/remote/ecodms/crons/usercrons.txt
```

**Root crontab** (after `sudo ecobackup -i`):

```cron
*/2 * * * *  /bin/mv /var/spool/cups-pdf/ANONYMOUS/* /opt/ecodms/workdir/scaninput/
0  5 * * *   service cups restart
10 3 * * *   chown ecodms:ecodms /opt/.../ecoDMSBackupConsole && chmod 710 /opt/.../ecoDMSBackupConsole
5  3 * * *   /usr/bin/crontab -l > /mnt/remote/ecodms/crons/rootcrons.txt
0  3 * * *   cp /usr/bin/ecobackup /mnt/remote/ecodms/ecobackuptool/ecobackup
```

> **Retention is NOT chained in cron.** It runs *inside* the script, only when the backup actually succeeds (`exit 0`). See ["Production Story"](#-production-story-a-six-week-silent-failure) below for why this matters.

---

## 🏗 Architecture Notes

### The `ecoDMSBackupConsole` permission dance

ecoDMS' `dpkg postinst` resets `/opt/ecodms/ecodmsserver/tools/ecoDMSBackupConsole` to `root:root 700` on *every* package update, and installs a sudoers rule that requires an interactive password (`ALL ALL = PASSWD:.../ecoDMSBackupConsole`). Neither setup is cron-friendly.

ecobackup's workaround:

1. `ecobackup -s` once → `chown ecodms:ecodms` + `chmod 710` + `usermod -aG ecodms $USER`
2. Daily root-cron re-applies the chown/chmod so the next ecoDMS update doesn't break automation
3. Backup runs as your user (member of `ecodms` group), no sudo password needed

### Lock model

Single global lockfile `/tmp/ecobackup.lock`, trap-cleaned on EXIT. Acquired before the BackupConsole call; warned-on-skip raises a Discord `warn` if two slots collide. Per-target locks + stale-lock recovery are on the roadmap.

### Exit code contract (verified empirically on ecoDMS 26.01)

| BackupConsole exit | Meaning |
|---|---|
| `0` | Success |
| `2` | Failure (invalid path, missing arg, no write permission) |

Older community sources (e.g. Andy's Blog) report "no errorlevel" — that's outdated for 26.01. ecobackup relies on the exit code; if you're on an older ecoDMS, please test before trusting it.

---

## 📖 Production Story: A Six-Week Silent Failure

This wrapper started life as a 100-line script that worked fine for years — until it didn't.

In April 2026, the daily backup directory started growing without bound. We had **41 zips in `daily/`** when the limit was supposed to be 7. The log file showed only two entries from the last six weeks. Both were from manual `sudo` runs.

### Root cause

```bash
log() { echo "[$(date)] $*" | tee -a "$LOGFILE"; }
```

`tee -a` returns non-zero when it can't write. The log file was `root:root 644`; cron ran the script as a non-root user. So every `log()` call from cron silently exited with 1.

That non-zero exit then cascaded through the canonical idiom:

```bash
BackupConsole "$dest/" \
   && log "Backup ok" \
   || { log "Backup FAILED"; exit 1; }
```

Backup succeeded → `log` failed → `||` branch fired → script exited 1 → both the script-internal prune *and* the cron-chained `&& find -mtime +N -delete` were skipped. For six weeks.

### Fixes applied in v1.x

| Version | Fix |
|---|---|
| **Hotfix** | `tee -a "$LOGFILE" 2>/dev/null; return 0` — `log()` can never affect exit chains. Logfile chowned to the cron user. |
| **v1.1** | Retention moved *into* the script; `&&`-chains removed from cron. Bug class structurally eliminated. |
| **v1.2** | Config-driven paths, embedded crontabs, Discord notify, generic-user refactor for public release. |

### Lesson

> **A logging call must never be able to change a script's exit status.** The "fail loud" school is correct in spirit, but if your "fail loud" mechanism is the same channel as the thing that failed (a logging side-effect), you fail *silent* instead.

---

## 🗺 Roadmap

- [ ] **Integrity verification** — `unzip -tq` + SQL header check before prune
- [ ] **`age`-encrypted off-site backups** — defense against Hetzner/cloud provider access
- [ ] **Per-target lockfiles** with stale-PID recovery
- [ ] **Atomic write** — `<target>/.partial/` → `mv` after integrity check
- [ ] **Pre-flight checks** — mount alive, ecoDMS service running, source has 2× target free
- [ ] **Automated restore drill** — monthly test-restore into throwaway PostgreSQL database
- [ ] **Notify adapters** — ntfy.sh, Slack, Telegram, email via msmtp
- [ ] **Optional `pg_dump -Fc`-only fast backup slot** — for RPO < 6h between full backups
- [ ] **systemd timers** as alternative to cron

PRs welcome on any of these.

---

## 🤝 Contributing

This started as a single-host script and grew. The architecture is intentionally simple — bash + standard tools — and should stay that way.

**Good PRs:**
- Compatibility fixes for older ecoDMS versions (especially exit-code behavior pre-26)
- New notify adapters (one short function, see `_notify_discord`)
- Pre-flight checks, integrity verification
- Documentation, examples, install scripts for other distros

**Probably-not PRs:**
- Rewrites to Go/Python/Rust — the value is in being a 1-file drop-in
- Web UI, dashboard, REST API
- Anything that requires changing the call surface of `ecoDMSBackupConsole`

Run `bash -n ecobackup` before submitting. There's no test suite (yet); manual smoke-tests via `ecobackup -t` and `ecobackup -i print user/root` should pass.

---

## 📄 License

[GNU GPL v3](LICENSE). See LICENSE for full text. Forks and derivative works must remain under GPLv3.

ecoDMS and ecoDMSBackupConsole are trademarks/products of [ecoDMS GmbH](https://www.ecodms.de/), Aachen, Germany. This project is an independent open-source wrapper and is not affiliated with, endorsed by, or supported by ecoDMS GmbH.

---

<div align="center">

Made with 🛠 by [@sgtsilver](https://github.com/sgtsilver) and contributors.
*If this script saved your backup, give it a ⭐.*

</div>
