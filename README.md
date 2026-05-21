<div align="center">

# 📦 ecobackup

**Ein robuster Bash-Wrapper rund um `ecoDMSBackupConsole`**
*Script-interne Retention · eingebettete Crontabs · Discord-Benachrichtigungen · keine externen Abhängigkeiten*

[![License: GPL v3](https://img.shields.io/badge/Lizenz-GPLv3-blue.svg)](LICENSE)
[![Shell](https://img.shields.io/badge/shell-bash%205%2B-1f425f.svg)](https://www.gnu.org/software/bash/)
[![ecoDMS](https://img.shields.io/badge/ecoDMS-22%20%7C%2024%20%7C%2026-blue.svg)](https://www.ecodms.de/)
[![Debian](https://img.shields.io/badge/Debian-11%20%7C%2012%20%7C%2013-a81d33.svg)](https://www.debian.org/)
[![PRs willkommen](https://img.shields.io/badge/PRs-willkommen-brightgreen.svg)](#-mitmachen)
[![Made with Claude Code](https://img.shields.io/badge/Pair%20Programming-Claude%20Code-D97757?logo=anthropic&logoColor=white)](https://claude.com/claude-code)

</div>

---

`ecoDMSBackupConsole` wird mit ecoDMS ausgeliefert und macht genau **eine** Sache: ein Zip in ein Verzeichnis schreiben. Keine Rotation. Keine Verifikation. Keine Benachrichtigungen. Kein dokumentierter Exit-Code-Vertrag.

Dieser Wrapper schließt die Lücke — ein einzelnes `bash`-Skript (~450 Zeilen, keine Abhängigkeiten außer `curl` und `python3` fürs JSON-Encoding), das in unter einer Minute deploybar ist.

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

## Inhaltsverzeichnis

- [Features](#-features)
- [Quick Start](#-quick-start)
- [Konfiguration](#%EF%B8%8F-konfiguration)
- [Verwendung](#-verwendung)
- [Benachrichtigungen](#-benachrichtigungen)
- [Cron-Layout](#-cron-layout)
- [Architektur-Notizen](#-architektur-notizen)
- [Aus der Praxis: Ein sechs Wochen langes stilles Versagen](#-aus-der-praxis-ein-sechs-wochen-langes-stilles-versagen)
- [Roadmap](#-roadmap)
- [Mitmachen](#-mitmachen)
- [Credits](#-credits)
- [Lizenz](#-lizenz)

---

## ✨ Features

| | |
|---|---|
| 🔒 **Atomares Locking** | Lockfile pro Host verhindert überlappende Läufe |
| 🗑️ **Script-interne Retention** | `find -mtime +N -delete`, entkoppelt vom Cron-Exit-Code (nie wieder "Cleanup lief nicht, weil das Logging fehlschlug") |
| 📣 **Pluggable Notifications** | Discord-Webhook out of the box, der Adapter ist auf ntfy/Slack/etc. erweiterbar |
| ⚙️ **Eingebettete Crontabs** | `ecobackup -i` installiert die Cron-Einträge idempotent — keine separaten Cron-Files zu pflegen |
| 🧪 **Smoke-Test-freundlich** | `ecobackup -t` testet das Notify, `ecobackup -i print user` ist ein Dry-Run |
| 🛠 **Self-Healing Permissions** | umgeht den ecoDMS-`dpkg postinst`, der `BackupConsole` nach jedem Update auf `root:root 700` zurücksetzt |
| 📦 **Null Abhängigkeiten** | `bash`, `curl`, `python3` (Debian-Standard-Installation) |
| 🌐 **Site-agnostisch** | alle Pfade in `/etc/ecobackup/ecobackup.conf` — forken und einsetzen ohne Umbenennen |

---

## 🚀 Quick Start

```bash
# 1. Skript auf den ecoDMS-Host bringen
sudo install -m 755 -o root -g root ecobackup /usr/bin/ecobackup

# 2. Pfade konfigurieren (siehe ecobackup.conf.example)
sudo install -d /etc/ecobackup
sudo cp ecobackup.conf.example /etc/ecobackup/ecobackup.conf
sudo $EDITOR /etc/ecobackup/ecobackup.conf

# 3. (Optional) Discord-Webhook einrichten
sudo cp notify.conf.example /etc/ecobackup/notify.conf
sudo chmod 600 /etc/ecobackup/notify.conf
sudo $EDITOR /etc/ecobackup/notify.conf

# 4. Einmaliges Permissions-Setup (chown + chmod + User in ecodms-Gruppe)
ecobackup -s
# einmal aus- und wieder einloggen, damit die Gruppenmitgliedschaft greift

# 5. Cron-Einträge installieren (idempotent — beliebig oft ausführbar)
sudo ecobackup -i

# 6. Smoke-Test
ecobackup -t                 # schickt Discord-Test-Nachricht
ecobackup -d                 # läuft das volle Daily-Backup
```

---

## ⚙️ Konfiguration

Zwei Dateien, beide optional. Das Skript bringt sinnvolle Defaults mit; Configs überschreiben diese.

### `/etc/ecobackup/ecobackup.conf` (Pfade, Retention)

```bash
DAILY_DIR=/mnt/backup/ecodms/daily
DAILY_KEEP_DAYS=7

MONTHLY_DIR=/mnt/backup/ecodms/monthly
MONTHLY_KEEP_DAYS=90

REMOTE_DIR=/mnt/remote/ecodms
REMOTE_KEEP_DAYS=14

# Optional: zweites Cloud-Ziel über den `-a`-Cron-Slot
EXTRA_DIR="/mnt/cloud/EcoDMS Backup/monthly"
EXTRA_KEEP_DAYS=90

# Cron-Installer
CRON_USER=deinuser
CRON_SNAPSHOT_DIR=/mnt/remote/ecodms/crons
SCRIPT_MIRROR_DIRS=/mnt/remote/ecodms/ecobackuptool/ecobackup
```

Vollständige Referenz: [`ecobackup.conf.example`](ecobackup.conf.example).

### `/etc/ecobackup/notify.conf` (Webhook-Secrets) — **Mode 600!**

```bash
NOTIFY_DISCORD_WEBHOOK=https://discord.com/api/webhooks/<id>/<token>
NOTIFY_ENABLED=1
```

---

## 🧰 Verwendung

| Befehl | Wirkung |
|---|---|
| `ecobackup -d` | Tägliches Backup (Retention `DAILY_KEEP_DAYS`) |
| `ecobackup -m` | Monatliches Backup |
| `ecobackup -r` | Remote Backup |
| `ecobackup -a <pfad>` | Backup nach beliebigem Pfad (`ECOBACKUP_KEEP_DAYS=N` für Retention-Override) |
| `ecobackup -c` | Interaktiv: nach Pfad fragen, keine Auto-Retention |
| `ecobackup -s` | Einmaliger Permission-Fix (BackupConsole + Gruppenmitgliedschaft) |
| `ecobackup -i` | User-Crontab installieren (+ root-Crontab wenn via `sudo`) |
| `ecobackup -i print user` | Dry-Run: zeigt die User-Crontab, die installiert würde |
| `ecobackup -i print root` | Dry-Run: zeigt die root-Crontab, die installiert würde |
| `ecobackup -t` | Test-Notification senden |
| `ecobackup -h` | Hilfe mit aktuell aufgelöster Konfiguration |

---

## 📣 Benachrichtigungen

Jeder Backup-Lauf produziert ein Discord-Embed:

```
┌──────────────────────────────────────────────────────────┐
│ 🟢 Tägliches Backup ok                                   │
├──────────────────────────────────────────────────────────┤
│ Ziel: `/mnt/backup/ecodms/daily`                         │
│ Dauer: 27s                                               │
│ Größe: 5.4G                                              │
│ prune: 1 gelöscht (>7d), 5.3GiB frei                     │
│                                                          │
│ ecobackup on ecodms · 21.05.2026 01:35:34 UTC            │
└──────────────────────────────────────────────────────────┘
```

Nach Level farbcodiert:
- 🟢 `ok` — Backup hat geklappt, Retention angewendet
- 🟡 `warn` — wenig Speicher, Lock-Kollision, etc.
- 🔴 `err` — Backup fehlgeschlagen (mit Exit-Code + Log-Pfad)

Der Discord-Transport ist ein kleiner Adapter. Ein Tausch gegen ntfy/Slack/Telegram sind ~20 Zeilen — siehe `_notify_discord()` im Script.

---

## ⏰ Cron-Layout

ecobackup bringt seine Crontabs selbst mit und installiert sie via `ecobackup -i`. Erneutes Ausführen ist idempotent (diff-basiert — schreibt nur, wenn sich Inhalt wirklich unterscheidet).

**User-Crontab** (`crontab -l` nach `ecobackup -i`):

```cron
35 1 * * *   /usr/bin/ecobackup -d
55 1 * * *   /usr/bin/ecobackup -r
45 1 1 * *   /usr/bin/ecobackup -m
35 2 1 * *   ECOBACKUP_KEEP_DAYS=90 /usr/bin/ecobackup -a "/mnt/cloud/EcoDMS Backup/monthly"
5  3 * * *   /usr/bin/crontab -l > /mnt/remote/ecodms/crons/usercrons.txt
```

**Root-Crontab** (nach `sudo ecobackup -i`):

```cron
*/2 * * * *  /bin/mv /var/spool/cups-pdf/ANONYMOUS/* /opt/ecodms/workdir/scaninput/
0  5 * * *   service cups restart
10 3 * * *   chown ecodms:ecodms /opt/.../ecoDMSBackupConsole && chmod 710 /opt/.../ecoDMSBackupConsole
5  3 * * *   /usr/bin/crontab -l > /mnt/remote/ecodms/crons/rootcrons.txt
0  3 * * *   cp /usr/bin/ecobackup /mnt/remote/ecodms/ecobackuptool/ecobackup
```

> **Retention hängt NICHT mehr an einer Cron-Chain.** Sie läuft *innerhalb* des Scripts und nur dann, wenn das Backup wirklich `exit 0` liefert. Warum das wichtig ist, steht weiter unten unter ["Aus der Praxis"](#-aus-der-praxis-ein-sechs-wochen-langes-stilles-versagen).

---

## 🏗 Architektur-Notizen

### Der Permissions-Tanz mit `ecoDMSBackupConsole`

Der ecoDMS-`dpkg postinst` setzt `/opt/ecodms/ecodmsserver/tools/ecoDMSBackupConsole` bei *jedem* Paket-Update auf `root:root 700` zurück und legt eine sudoers-Regel mit Passwort-Pflicht an (`ALL ALL = PASSWD:.../ecoDMSBackupConsole`). Beides ist cron-untauglich.

ecobackups Workaround:

1. Einmal `ecobackup -s` → `chown ecodms:ecodms` + `chmod 710` + `usermod -aG ecodms $USER`
2. Täglicher root-Cron wendet chown/chmod erneut an, damit das nächste ecoDMS-Update die Automation nicht killt
3. Backups laufen als dein User (Mitglied der `ecodms`-Gruppe) — kein sudo-Passwort nötig

### Lock-Modell

Ein globales Lockfile `/tmp/ecobackup.lock`, beim EXIT trap-gecleant. Wird vor dem BackupConsole-Aufruf geholt; eine Skip-Warnung löst einen Discord-`warn` aus, wenn zwei Slots kollidieren. Lockfile pro Ziel + Stale-Lock-Recovery stehen auf der Roadmap.

### Exit-Code-Vertrag (empirisch verifiziert auf ecoDMS 26.01)

| BackupConsole exit | Bedeutung |
|---|---|
| `0` | Erfolg |
| `2` | Fehler (ungültiger Pfad, fehlendes Argument, kein Schreibrecht) |

Ältere Community-Quellen (etwa Andy's Blog) sagen "kein errorlevel" — das ist für 26.01 **veraltet**. ecobackup verlässt sich auf den Exit-Code; bei älteren ecoDMS-Versionen bitte vorher testen.

---

## 📖 Aus der Praxis: Ein sechs Wochen langes stilles Versagen

Dieser Wrapper fing als 100-Zeilen-Skript an und lief jahrelang sauber — bis er es nicht mehr tat.

Im April 2026 begann das Daily-Backup-Verzeichnis ungebremst zu wachsen. Wir hatten **41 Zips in `daily/`**, obwohl das Limit eigentlich 7 war. Das Logfile zeigte nur zwei Einträge aus den letzten sechs Wochen. Beide aus manuellen `sudo`-Läufen.

### Root Cause

```bash
log() { echo "[$(date)] $*" | tee -a "$LOGFILE"; }
```

`tee -a` liefert non-zero zurück, wenn es nicht schreiben kann. Das Logfile war `root:root 644`; Cron lief das Script als nicht-root-User. Also lieferte jeder `log()`-Aufruf aus dem Cron-Lauf still exit 1 zurück.

Dieser non-zero Exit kaskadierte dann durch das klassische Idiom:

```bash
BackupConsole "$dest/" \
   && log "Backup ok" \
   || { log "Backup FAILED"; exit 1; }
```

Backup gelang → `log` fiel um → `||`-Zweig zündete → Script exit 1 → sowohl das script-interne Prune *als auch* der cron-chained `&& find -mtime +N -delete` wurden übersprungen. Sechs Wochen lang.

### Was in v1.x gefixt wurde

| Version | Fix |
|---|---|
| **Hotfix** | `tee -a "$LOGFILE" 2>/dev/null; return 0` — `log()` kann den Exit-Status nicht mehr kippen. Logfile chown auf den Cron-User. |
| **v1.1** | Retention in das Script gezogen; `&&`-Chains aus dem Cron raus. Bug-Klasse strukturell weg. |
| **v1.2** | Pfade konfig-driven, eingebettete Crontabs, Discord-Notify, generisches User-Refactoring fürs Public Release. |

### Lehre

> **Ein Logging-Aufruf darf niemals den Exit-Status eines Skripts ändern können.** Die "fail loud"-Schule hat im Geist recht — aber wenn dein "fail loud"-Mechanismus über denselben Kanal läuft wie das Ding, das versagt hat (ein Side-Effect beim Logging), dann fällst du stattdessen *still* um.

---

## 🗺 Roadmap

- [ ] **Integritäts-Verifikation** — `unzip -tq` + SQL-Header-Check vor Prune
- [ ] **`age`-verschlüsselte Off-Site-Backups** — Schutz vor Hetzner-/Cloud-Provider-Zugriff
- [ ] **Pro-Ziel-Lockfiles** mit Stale-PID-Recovery
- [ ] **Atomic Write** — `<target>/.partial/` → `mv` nach Integritätsprüfung
- [ ] **Pre-Flight-Checks** — Mount live, ecoDMS-Service läuft, Source hat 2× Ziel frei
- [ ] **Automatisierter Restore-Drill** — monatlicher Test-Restore in eine Wegwerf-PostgreSQL-DB
- [ ] **Notify-Adapter** — ntfy.sh, Slack, Telegram, E-Mail via msmtp
- [ ] **Optionaler `pg_dump -Fc`-Schnellbackup-Slot** — für RPO < 6h zwischen den Vollbackups
- [ ] **systemd-Timer** als Alternative zu Cron

PRs zu allen Punkten willkommen.

---

## 🤝 Mitmachen

Dieses Tool fing als Single-Host-Skript an und ist gewachsen. Die Architektur ist bewusst simpel — bash plus Standard-Tools — und soll auch so bleiben.

**Gute PRs:**
- Kompatibilitäts-Fixes für ältere ecoDMS-Versionen (insbesondere Exit-Code-Verhalten vor 26)
- Neue Notify-Adapter (eine kurze Funktion, siehe `_notify_discord`)
- Pre-Flight-Checks, Integritäts-Verifikation
- Dokumentation, Beispiele, Install-Scripte für andere Distros

**Eher nicht:**
- Rewrites in Go/Python/Rust — der Wert liegt darin, ein 1-File-Drop-In zu sein
- Web-UI, Dashboard, REST-API
- Alles, was das Aufruf-Interface von `ecoDMSBackupConsole` ändert

Vor dem PR bitte `bash -n ecobackup` laufen lassen. Es gibt (noch) keine Test-Suite; manuelle Smoke-Tests über `ecobackup -t` und `ecobackup -i print user/root` sollten durchgehen.

---

## 🎉 Credits

<div align="center">

[![Anthropic](https://img.shields.io/badge/Anthropic-Claude%20Opus%204.7-D97757?logo=anthropic&logoColor=white&style=for-the-badge)](https://www.anthropic.com/claude)
[![Claude Code](https://img.shields.io/badge/Built%20with-Claude%20Code-D97757?logo=anthropic&logoColor=white&style=for-the-badge)](https://claude.com/claude-code)

</div>

Der v1.2-Rewrite — Bug-Forensik, Refactoring, Notify-Adapter, eingebettete Crontabs, README, Release — entstand in einer Pair-Programming-Session mit **[Claude Code](https://claude.com/claude-code)** (Modell: Claude Opus 4.7, 1M Context) als KI-Pair-Programmer.

| Mensch ([@sgtsilver](https://github.com/sgtsilver)) | KI ([Claude Code](https://claude.com/claude-code)) |
|---|---|
| Production-Hosts und ecoDMS-Wissen | Bug-Diagnose, Code-Refactoring, Doku |
| Architektur-Entscheidungen und Code-Review | Implementierung, Tests, Cron-Hygiene |
| Discord-Webhook und Lizenzwahl | Recherche der offiziellen ecoDMS-Doku, READMEs |
| "Mach das anders" / "Schmeiß weg" / "Verifizier das" | Vorschläge, Live-Verifikation, Pushback wenn nötig |

Die ursprüngliche v1.0 (Anfang 2023) ist 100% von Menschenhand entstanden — siehe `Initialer Upload des Skriptes` in der Git-History.

> *"Built with Claude Code" heißt: Claude hat den Code geschrieben, der Mensch hat entschieden, was geschrieben wird. Verantwortung für Korrektheit und Sicherheit liegt beim Maintainer.*

---

## 📄 Lizenz

[GNU GPL v3](LICENSE). Volltext in LICENSE. Forks und Derivate müssen unter GPLv3 bleiben.

ecoDMS und ecoDMSBackupConsole sind Marken/Produkte der [ecoDMS GmbH](https://www.ecodms.de/), Aachen. Dieses Projekt ist ein unabhängiger Open-Source-Wrapper und steht in keiner Verbindung mit der ecoDMS GmbH (kein Endorsement, kein Support).

---

<div align="center">

Gebaut mit 🛠 von [@sgtsilver](https://github.com/sgtsilver) — v1.2 in Pair-Programming-Session mit 🤖 [Claude Code](https://claude.com/claude-code).
*Wenn dieses Skript dein Backup gerettet hat, hinterlass einen ⭐.*

</div>
