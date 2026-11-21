<div align="center">

# 📦 ecobackup

**Ein robuster Bash-Wrapper rund um `ecoDMSBackupConsole`**
*Script-interne Retention · eingebettete Crontabs · Discord-Benachrichtigungen · wenig Abhängigkeiten*

[![License: GPL v3](https://img.shields.io/badge/Lizenz-GPLv3-blue.svg)](LICENSE)
[![Version](https://img.shields.io/badge/Version-1.3-blue.svg)](#-upgrade-von-v12)
[![Shell](https://img.shields.io/badge/shell-bash-1f425f.svg)](https://www.gnu.org/software/bash/)
[![ecoDMS](https://img.shields.io/badge/ecoDMS-26.01%20verifiziert-blue.svg)](https://www.ecodms.de/)
[![PRs willkommen](https://img.shields.io/badge/PRs-willkommen-brightgreen.svg)](#-mitmachen)
[![Made with Claude Code](https://img.shields.io/badge/Pair%20Programming-Claude%20Code-D97757?logo=anthropic&logoColor=white)](https://claude.com/claude-code)

</div>

> **English summary:** `ecobackup` is a single-file Bash wrapper around ecoDMS' `ecoDMSBackupConsole` (documentation is in German).
> It adds age-based retention, a simple lockfile, embedded crontabs (`ecobackup -i`) and optional Discord notifications.
> Needs Bash and GNU coreutils on the ecoDMS host; `curl` and `python3` are optional (Discord only).
> Built for dpkg-based (Debian) ecoDMS installs; verified with ecoDMS 26.01 only.
> **Warning:** `ecobackup -i` replaces the *entire* crontab — back it up (`crontab -l`) and preview with `ecobackup -i print user|root` first.

---

`ecoDMSBackupConsole` wird mit ecoDMS ausgeliefert und macht genau **eine** Sache: ein Zip in ein Verzeichnis schreiben. Keine Rotation. Keine Verifikation. Keine Benachrichtigungen. Kein dokumentierter Exit-Code-Vertrag.

Dieser Wrapper schließt die Lücke — ein einzelnes `bash`-Skript (knapp 500 Zeilen, keine Abhängigkeiten außer GNU-Standardwerkzeugen; `curl` und `python3` nur optional fürs Discord-Senden und JSON-Encoding), das in wenigen Minuten eingerichtet ist.

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
- [Voraussetzungen](#-voraussetzungen)
- [Quick Start](#-quick-start)
- [Upgrade von v1.2](#-upgrade-von-v12)
- [Konfiguration](#%EF%B8%8F-konfiguration)
- [Verwendung](#-verwendung)
- [Benachrichtigungen](#-benachrichtigungen)
- [Cron-Layout](#-cron-layout)
- [Architektur-Notizen](#-architektur-notizen)
- [Fehlersuche](#-fehlersuche)
- [Deinstallation](#-deinstallation)
- [Aus der Praxis: Ein sechs Wochen langes stilles Versagen](#-aus-der-praxis-ein-sechs-wochen-langes-stilles-versagen)
- [Roadmap](#-roadmap)
- [Mitmachen](#-mitmachen)
- [Credits](#-credits)
- [Lizenz](#-lizenz)

---

## ✨ Features

| | |
|---|---|
| 🔒 **Einfaches Lockfile** | `/tmp/ecobackup.lock` verhindert überlappende Läufe — bewusst simpel (check-then-touch, keine Stale-Lock-Recovery), Details im [Lock-Modell](#lock-modell) |
| 🗑️ **Script-interne Retention** | altersbasiert (`find -mtime +N` + `rm -f`), nur nach erfolgreichem Backup, entkoppelt vom Cron-Exit-Code (nie wieder "Cleanup lief nicht, weil das Logging fehlschlug") |
| 📣 **Discord-Benachrichtigungen** (weitere Kanäle vorbereitet) | Discord-Webhook ist fest verdrahtet; die generische `notify`-Schnittstelle ist auf weitere Kanäle (ntfy/Slack/…) erweiterbar — siehe [Roadmap](#-roadmap) |
| ⚙️ **Eingebettete Crontabs** | `ecobackup -i` installiert die Cron-Einträge diff-basiert — **ersetzt dabei aber die komplette Crontab** (siehe [Warnung](#-cron-layout)); keine separaten Cron-Files zu pflegen |
| 🧪 **Smoke-Test-freundlich** | `ecobackup -t` testet das Notify, `ecobackup -i print user` ist ein Dry-Run |
| 🛠 **Permissions-Self-Heal** | ein root-Cron stellt täglich um 03:10 `Owner/Mode` der `BackupConsole` wieder her, die der ecoDMS-`dpkg postinst` nach jedem Update auf `root:root 700` zurücksetzt — **nach** den Backups, siehe [Hinweis](#der-permissions-tanz-mit-ecodmsbackupconsole) |
| 📦 **Wenig Abhängigkeiten** | `bash` + GNU-Standardwerkzeuge; optional `curl` + `python3` für Discord, siehe [Voraussetzungen](#-voraussetzungen) |
| 🌐 **Konfigurierbare Pfade** | Pfade und Retention in `/etc/ecobackup/ecobackup.conf`; Uhrzeiten und die cups-Jobs der Root-Crontab sind im Skript fest verdrahtet |

---

## 📋 Voraussetzungen

- **ecoDMS-Server auf demselben Host** mit vorhandener `ecoDMSBackupConsole` (Default `/opt/ecodms/ecodmsserver/tools/ecoDMSBackupConsole`, anpassbar über `ECODMS_SERVER_DIR` / `BACKUP_TOOL`). Verifiziert ist das Verhalten nur mit **ecoDMS 26.01** (siehe [Exit-Code-Vertrag](#exit-code-vertrag)); bei anderen Versionen bitte vorher testen.
- **Linux mit dpkg-basierter ecoDMS-Installation.** Der Permissions-Workaround bezieht sich auf das ecoDMS-`dpkg postinst`; Pfade und Beispiele sind auf Debian ausgelegt. Einzelne Debian-Versionen sind nicht verifiziert.
- **`bash`**, **`cron`** (das Kommando `crontab`) und **`sudo`** — `sudo` braucht `ecobackup -s` (`chown`, `chmod`, `usermod`) sowie die Installation der Root-Crontab (`sudo ecobackup -i`). User und Gruppe `ecodms` müssen existieren.
- **GNU coreutils/findutils**: `numfmt`, `stat -c`, `find -newermt` (daneben `du`, `df`, `diff`, `realpath`). Fehlen `numfmt`, `stat -c` oder `find -newermt` (z. B. BSD/macOS), läuft das Backup trotzdem — nur die Größenangaben in Log und Meldung werden ungenau.
- **Optional `curl` + `python3`** für die Discord-Meldungen (`python3` baut das JSON). Fehlt eines davon, wird die Meldung **still übersprungen** — kein Fehler, keine Warnung. Nachinstallieren z. B. mit `sudo apt install curl python3`.
- Ein **normaler User** ("Cron-User"), unter dem die Backups per Cron laufen. Er muss in der Gruppe `ecodms` sein (macht `ecobackup -s`) und in die Zielverzeichnisse schreiben dürfen — das Skript legt sie nicht an.
- **Das Skript muss unter `/usr/bin/ecobackup` liegen.** Dieser Pfad ist in den generierten Cron-Zeilen und im Script-Mirror fest verdrahtet.

---

## 🚀 Quick Start

Alle Schritte als der User ausführen, der die Backups später per Cron fahren soll (nicht als root, nicht per `sudo -i`).

```bash
# 1. Skript auf den ecoDMS-Host bringen (der Pfad /usr/bin/ecobackup ist Pflicht)
sudo install -m 755 -o root -g root ecobackup /usr/bin/ecobackup

# 2. Pfade konfigurieren (siehe ecobackup.conf.example)
sudo install -d /etc/ecobackup
sudo cp ecobackup.conf.example /etc/ecobackup/ecobackup.conf
sudo $EDITOR /etc/ecobackup/ecobackup.conf

# 3. Zielverzeichnisse anlegen, in die der Cron-User schreiben darf
#    (Defaults — bei eigenen Pfaden in ecobackup.conf entsprechend anpassen)
sudo install -d -o "$USER" -g "$USER" /var/backups/ecodms/daily /var/backups/ecodms/monthly /var/backups/ecodms/remote

# 4. Logfile anlegen — VOR dem ersten "sudo ecobackup -i" / "sudo ecobackup …"!
#    /var/log ist für normale User nicht beschreibbar; ohne diese Datei fehlt das Log
#    stillschweigend (alternativ LOGFILE in der ecobackup.conf auf einen beschreibbaren Pfad setzen).
sudo install -m 664 -o root -g ecodms /dev/null /var/log/ecobackup.log

# 5. (Optional) Discord-Webhook einrichten
#    root:ecodms 640 — der Cron-User liest die Datei über die ecodms-Gruppe (Schritt 6).
#    root:root 600 würde die Cron-Läufe aussperren: es kämen keine Meldungen an.
sudo cp notify.conf.example /etc/ecobackup/notify.conf
sudo chown root:ecodms /etc/ecobackup/notify.conf
sudo chmod 640 /etc/ecobackup/notify.conf
sudo $EDITOR /etc/ecobackup/notify.conf

# 6. Einmaliges Permissions-Setup (chown + chmod + User in ecodms-Gruppe)
#    Als normaler User aufrufen, NICHT mit sudo — das Skript ruft sudo selbst.
ecobackup -s
# einmal aus- und wieder einloggen, damit die Gruppenmitgliedschaft greift
# Kontrolle (-s meldet immer "Rechte gesetzt!", auch wenn ein sudo-Schritt scheiterte):
ls -l /opt/ecodms/ecodmsserver/tools/ecoDMSBackupConsole   # erwartet: -rwx--x--- ecodms ecodms
id                                                         # enthält die Gruppe ecodms

# 7. Cron-Einträge installieren — ERST die Warnung im Abschnitt "Cron-Layout" lesen!
crontab -l > ~/crontab.bak                # Sicherung (Meldung "no crontab" ist ok)
sudo crontab -l > ~/crontab-root.bak
ecobackup -i print user                   # Vorschau
ecobackup -i print root                   # Vorschau (enthält standortspezifische cups-Jobs!)
sudo ecobackup -i                         # installiert User- UND Root-Crontab

# 8. Smoke-Test (als Cron-User, nicht per sudo)
ecobackup -t                 # schickt Discord-Test-Nachricht (nur mit konfiguriertem Webhook)
ecobackup -d                 # läuft das volle Daily-Backup
tail /var/log/ecobackup.log
```

Das Skript rotiert sein Log nicht selbst. Wer das möchte, legt eine logrotate-Regel mit `create 664 root ecodms` an, damit die Datei nach der Rotation für den Cron-User beschreibbar bleibt.

---

## 🔄 Upgrade von v1.2

**Was sich ändert:** Die Config-Schlüssel für das optionale zweite Off-Site-Ziel (`-a`-Cron-Slot) heißen jetzt `EXTRA_DIR` und `EXTRA_KEEP_DAYS` (vorher `TELEKOM_DIR` und `TELEKOM_KEEP_DAYS`). Neu ist außerdem `ecobackup -V`.

- Die Schlüssel werden nur beim **Erzeugen der Crontab** ausgewertet (`ecobackup -i`, `-i print`); der Pfad des `-a`-Slots steht fest in der installierten Cron-Zeile. Eine bereits installierte Crontab läuft deshalb unverändert weiter.
- Die alten Namen funktionieren in v1.3 weiter: ecobackup fällt auf sie zurück (die neuen Namen haben Vorrang) und warnt, z. B. `WARN: TELEKOM_DIR ist veraltet — bitte in EXTRA_DIR umbenennen (seit v1.3)` — auf stderr, bei `ecobackup -i` zusätzlich im Log. Ohne den Fallback würde ein erneutes `ecobackup -i` den `-a`-Slot aus der Crontab entfernen, weil `EXTRA_DIR` leer wäre.
- Das Umbenennen wird empfohlen:

```bash
# 1. Neues Skript installieren
sudo install -m 755 -o root -g root ecobackup /usr/bin/ecobackup

# 2. Alte Schlüssel in der Config finden und umbenennen
grep -n 'TELEKOM_' /etc/ecobackup/ecobackup.conf
sudo sed -i 's/^TELEKOM_/EXTRA_/' /etc/ecobackup/ecobackup.conf

# 3. Crontab prüfen — die generierten Zeilen sind in v1.3 dieselben wie in v1.2
ecobackup -i print user                   # mit `crontab -l` vergleichen; nach dem Umbenennen ohne Warnung
# Nur wenn du sie neu erzeugen willst (Warnung im Abschnitt "Cron-Layout" beachten!):
ecobackup -i                              # bzw. `sudo ecobackup -i` inkl. root-Crontab;
                                          # meldet "bereits aktuell", wenn nichts zu tun ist

# 4. Version prüfen
ecobackup -V                              # → ecobackup 1.3
```

Der `sed`-Aufruf erwischt nur Zeilen, die direkt mit `TELEKOM_` beginnen; auskommentierte Zeilen (`# TELEKOM_DIR=…`) bleiben unverändert.

---

## ⚙️ Konfiguration

Zwei Dateien, beide optional. Das Skript bringt sinnvolle Defaults mit; Configs überschreiben diese. Beide werden vom Skript als **Shell gesourct** — nur root darf sie schreiben. Der Cron-User muss sie lesen können: Ist eine Datei nicht lesbar, wird sie **stillschweigend ignoriert** (Defaults bzw. keine Meldungen).

### `/etc/ecobackup/ecobackup.conf` (Pfade, Retention) — Mode 644

```bash
DAILY_DIR=/mnt/backup/ecodms/daily
DAILY_KEEP_DAYS=7

MONTHLY_DIR=/mnt/backup/ecodms/monthly
MONTHLY_KEEP_DAYS=90

REMOTE_DIR=/mnt/remote/ecodms
REMOTE_KEEP_DAYS=14

# Optional: zweites Off-Site-/Cloud-Ziel über den `-a`-Cron-Slot (bis v1.2: TELEKOM_DIR / TELEKOM_KEEP_DAYS)
EXTRA_DIR="/mnt/cloud/EcoDMS Backup/monthly"
EXTRA_KEEP_DAYS=90

# Cron-Installer (nur nötig, wenn Default nicht passt: siehe Tabelle)
# CRON_USER=<user>
CRON_SNAPSHOT_DIR=/mnt/remote/ecodms/crons
# Komma-getrennte Liste von VERZEICHNISSEN (nicht Dateipfaden), keine Leerzeichen/Kommas in Pfaden
SCRIPT_MIRROR_DIRS=/mnt/remote/ecodms/ecobackuptool,/home/<user>/ecobackup-mirror
```

Alle Schlüssel und Defaults (vollständige Referenz mit Kommentaren: [`ecobackup.conf.example`](ecobackup.conf.example)):

| Schlüssel | Default | Bedeutung |
|---|---|---|
| `ECODMS_SERVER_DIR` | `/opt/ecodms/ecodmsserver` | ecoDMS-Serververzeichnis. Steckt auch in der Root-Crontab (Scaninput-Pfad `…/workdir/scaninput/` im Elternverzeichnis). **Wenn du es änderst, setze auch `BACKUP_TOOL`** — dessen Default wird vor dem Einlesen der Conf berechnet. |
| `BACKUP_TOOL` | `$ECODMS_SERVER_DIR/tools/ecoDMSBackupConsole` | Pfad zur `ecoDMSBackupConsole` |
| `LOGFILE` | `/var/log/ecobackup.log` | Logfile — der Cron-User muss schreiben können (Quick Start, Schritt 4) |
| `LOCKFILE` | `/tmp/ecobackup.lock` | Lockfile, siehe [Lock-Modell](#lock-modell) |
| `DAILY_DIR` / `DAILY_KEEP_DAYS` | `/var/backups/ecodms/daily` / `7` | Ziel und Retention für `-d` |
| `MONTHLY_DIR` / `MONTHLY_KEEP_DAYS` | `/var/backups/ecodms/monthly` / `90` | Ziel und Retention für `-m` |
| `REMOTE_DIR` / `REMOTE_KEEP_DAYS` | `/var/backups/ecodms/remote` / `14` | Ziel und Retention für `-r` |
| `EXTRA_DIR` / `EXTRA_KEEP_DAYS` | leer (= kein `-a`-Slot) / `90` | zweites Ziel für den `-a`-Cron-Slot (`TELEKOM_DIR` / `TELEKOM_KEEP_DAYS` bis v1.2, veraltet) |
| `CRON_USER` | `$SUDO_USER`, sonst aktueller User | wessen User-Crontab `ecobackup -i` installiert. Bei Login als echter root (ohne `sudo`) wäre der Default `root` — dann `CRON_USER` setzen. |
| `CRON_SNAPSHOT_DIR` | leer | Verzeichnis für tägliche Crontab-Snapshots (User und root); ohne Leerzeichen im Pfad |
| `SCRIPT_MIRROR_DIRS` | leer | Komma-getrennte Liste von **Verzeichnissen**, in die der root-Cron täglich `/usr/bin/ecobackup` kopiert (Disaster Recovery) |
| `NOTIFY_DISCORD_WEBHOOK` / `NOTIFY_ENABLED` | leer / `1` | in `notify.conf`, siehe unten |
| `ECOBACKUP_KEEP_DAYS` | — | **Umgebungsvariable** für einzelne Aufrufe, keine Conf-Option; überschreibt die Retention von `-d`, `-m`, `-r` und `-a` |

Werte, die in die generierten Crontabs einfließen — `EXTRA_*`, `CRON_USER`, `CRON_SNAPSHOT_DIR`, `SCRIPT_MIRROR_DIRS`, `ECODMS_SERVER_DIR`, `BACKUP_TOOL` — wirken erst nach erneutem `ecobackup -i` (Warnung im Abschnitt [Cron-Layout](#-cron-layout) beachten). Alle anderen Werte liest das Skript bei jedem Lauf neu.

### `/etc/ecobackup/notify.conf` (Webhook-Secrets) — **Mode 640, `root:ecodms`**

```bash
NOTIFY_DISCORD_WEBHOOK=https://discord.com/api/webhooks/<id>/<token>
NOTIFY_ENABLED=1
```

Die Backups laufen als Cron-User, nicht als root. Mit `root:root 600` wäre die Datei für den Cron-User unlesbar, und das Skript würde sie stillschweigend überspringen — es kämen keine Discord-Meldungen an. Deshalb `root:ecodms` + `640`: Lesen dürfen root und die Mitglieder der Gruppe `ecodms` (also der Cron-User, siehe `ecobackup -s`), schreiben nur root.

---

## 🧰 Verwendung

| Befehl | Wirkung |
|---|---|
| `ecobackup -d` | Tägliches Backup (Retention `DAILY_KEEP_DAYS`, Default 7 Tage) |
| `ecobackup -m` | Monatliches Backup (Retention `MONTHLY_KEEP_DAYS`, Default 90 Tage) |
| `ecobackup -r` | Remote Backup (Retention `REMOTE_KEEP_DAYS`, Default 14 Tage) |
| `ecobackup -a <pfad>` | Backup nach beliebigem Pfad (Retention Default 90 Tage; Override per `ECOBACKUP_KEEP_DAYS=N`) |
| `ecobackup -c` | Interaktiv: nach Pfad fragen, keine Auto-Retention, keine Erfolgs-/Fehler-Meldung |
| `ecobackup -s` | Einmaliger Permission-Fix (BackupConsole + Gruppenmitgliedschaft); ohne `sudo` aufrufen |
| `ecobackup -i` | User-Crontab installieren (+ root-Crontab wenn via `sudo`) — **ersetzt die komplette Crontab**, siehe [Warnung](#-cron-layout) |
| `ecobackup -i print user` | Dry-Run: zeigt die User-Crontab, die installiert würde |
| `ecobackup -i print root` | Dry-Run: zeigt die root-Crontab, die installiert würde |
| `ecobackup -t` | Test-Notification senden |
| `ecobackup -V` / `--version` | Version ausgeben (`ecobackup 1.3`) |
| `ecobackup -h` | Hilfe mit aktuell aufgelöster Konfiguration und Version |

### Retention im Detail

- Nach einem **erfolgreichen** Backup (BackupConsole `exit 0`) löscht ecobackup im Zielverzeichnis alle `DMSbackup*.zip`, die **älter als N Tage** sind (`find -mtime +N`, also mindestens N+1 volle Tage), per `rm -f`. Geprüft wird nur die oberste Ebene des Zielverzeichnisses (`-maxdepth 1`, nur reguläre Dateien); alles andere bleibt unberührt.
- `ECOBACKUP_KEEP_DAYS=N` überschreibt die Aufbewahrung für **`-d`, `-m`, `-r` und `-a`** — nicht nur für `-a`. Ohne Override gilt je Slot `DAILY_/MONTHLY_/REMOTE_KEEP_DAYS`, für `-a` der Default von 90 Tagen. `-c` löscht nie.
- Nach einem fehlgeschlagenen Backup wird nicht aufgeräumt. Ein fehlendes Zielverzeichnis beim Prune wird nur geloggt.
- Jeder Slot räumt nach seiner **eigenen** Frist auf — teile deshalb ein Zielverzeichnis nicht zwischen Slots.

---

## 📣 Benachrichtigungen

Läufe mit `-d`, `-m`, `-r` und `-a` schicken — sofern ein Webhook konfiguriert ist — ein Discord-Embed. Es besteht aus einem Titel mit farbigem Balken (grün/gelb/rot/blau, ohne Emoji), einem Textfeld und einer Fußzeile:

```
┌──────────────────────────────────────────────────────────┐
│ Tägliches Backup ok                                      │
├──────────────────────────────────────────────────────────┤
│ Ziel: `/mnt/backup/ecodms/daily`                         │
│ Dauer: 27s                                               │
│ Größe: 5.4G                                              │
│ prune: 1 gelöscht (>7d), 5.3GB frei                      │
│                                                          │
│ ecobackup on ecodms · <Zeitstempel>                      │
└──────────────────────────────────────────────────────────┘
```

Farbcodierung nach Level:
- grün (`ok`) — Backup hat geklappt, Retention angewendet
- gelb (`warn`) — wenig Speicher (< 500 MB frei, das Backup läuft trotzdem), Lock-Kollision
- rot (`err`) — Backup fehlgeschlagen (mit BackupConsole-Exit-Code und Log-Pfad)
- blau (`info`) — nur die Test-Nachricht von `ecobackup -t`

**Wann wird *nicht* gemeldet?**

| Situation | Verhalten |
|---|---|
| `ecobackup -c` | meldet **nie** Erfolg oder Fehler (nur `warn` bei Lock-Kollision / wenig Speicher) |
| `ecobackup -a <pfad>` mit nicht existierendem Verzeichnis (z. B. nicht gemountetes Ziel) | nur eine Log-Zeile, Exit 1 — **keine** Meldung |
| `-s`, `-i` | keine Meldungen |
| `NOTIFY_ENABLED=0`, kein Webhook gesetzt, `notify.conf` nicht lesbar, `curl`/`python3` fehlt | Meldung wird still übersprungen |
| Webhook-URL falsch, Discord/Netzwerk nicht erreichbar (Timeout 10 s) | Fehler wird verschluckt, das Backup bleibt unbeeinflusst |

`ecobackup -t` meldet "Gesendet", sobald die Nachricht abgeschickt wurde — nicht, ob sie angekommen ist. Entscheidend ist der Discord-Channel.

Der Aufruf `notify <ok|warn|err|info> "<Titel>" "<Body>"` ist generisch gehalten, aber **derzeit ist nur Discord implementiert** (`notify()` ruft fest `_notify_discord()` auf). Weitere Kanäle (ntfy/Slack/Telegram) wären eine eigene Funktion plus ein Aufruf in `notify()` — siehe [Roadmap](#-roadmap).

---

## ⏰ Cron-Layout

ecobackup bringt seine Crontabs selbst mit und installiert sie via `ecobackup -i`. Der Installer arbeitet diff-basiert: Entspricht die aktuelle Crontab schon dem Soll, passiert nichts ("bereits aktuell"). Weicht sie ab, wird sie **komplett ersetzt**.

> [!WARNING]
> **`ecobackup -i` ersetzt die komplette Crontab — nicht nur die ecobackup-Zeilen.**
>
> - Weicht die aktuelle Crontab vom Soll ab, wird sie per `crontab -` vollständig überschrieben: die des Cron-Users, und mit `sudo` zusätzlich die von **root**. Eigene Jobs und manuelle Änderungen gehen verloren — ohne Rückfrage und ohne Backup.
> - **Vorher sichern und ansehen:** `crontab -l > ~/crontab.bak` (und `sudo crontab -l > ~/crontab-root.bak`), dann `ecobackup -i print user` bzw. `ecobackup -i print root`.
> - Die Zeitpläne sind **fest im Skript verdrahtet** (`_cron_user`, `_cron_root`). Manuelle Änderungen an den Crontab-Zeilen werden beim nächsten `ecobackup -i` überschrieben; dauerhaft ändern lässt sich nur das Skript.
> - Die Root-Crontab enthält **standortspezifische Jobs**: `MAILTO=""` (kein Cron-Mailversand für root), alle 2 Minuten ein `mv` aus dem cups-pdf-Spool (`/var/spool/cups-pdf/ANONYMOUS/*`) in den ecoDMS-Scaninput und um 05:00 ein `service cups restart`. Nutzt du cups-pdf nicht als Scan-Eingang, installiere die Root-Crontab **nicht** per `sudo ecobackup -i`, sondern übernimm nur die Zeilen, die du brauchst (vor allem die Permissions-Zeile), von Hand — oder passe `_cron_root` im Skript an.
> - `ecobackup -i` **ohne** `sudo` fasst nur die User-Crontab an.

**User-Crontab** (`crontab -l` nach `ecobackup -i`; die Zeilen für `-a` und Snapshot gibt es nur, wenn `EXTRA_DIR` bzw. `CRON_SNAPSHOT_DIR` gesetzt ist):

```cron
35 1 * * *   /usr/bin/ecobackup -d
55 1 * * *   /usr/bin/ecobackup -r
45 1 1 * *   /usr/bin/ecobackup -m
35 2 1 * *   ECOBACKUP_KEEP_DAYS=90 /usr/bin/ecobackup -a /mnt/cloud/EcoDMS\ Backup/monthly
5  3 * * *   /usr/bin/crontab -l > /mnt/remote/ecodms/crons/usercrons.txt
```

(Der Pfad in der `-a`-Zeile wird mit `printf %q` maskiert — Leerzeichen erscheinen als `\ `, nicht in Anführungszeichen.)

**Root-Crontab** (nach `sudo ecobackup -i`; Snapshot- und Mirror-Zeilen nur bei gesetztem `CRON_SNAPSHOT_DIR` bzw. `SCRIPT_MIRROR_DIRS`, Mirror: eine Zeile pro Verzeichnis):

```cron
MAILTO=""
*/2 * * * *  /bin/mv /var/spool/cups-pdf/ANONYMOUS/* /opt/ecodms/workdir/scaninput/
0  5 * * *   service cups restart
10 3 * * *   /bin/chown ecodms:ecodms /opt/ecodms/ecodmsserver/tools/ecoDMSBackupConsole && /bin/chmod 710 /opt/ecodms/ecodmsserver/tools/ecoDMSBackupConsole
5  3 * * *   /usr/bin/crontab -l > /mnt/remote/ecodms/crons/rootcrons.txt
0  3 * * *   /bin/cp /usr/bin/ecobackup /mnt/remote/ecodms/ecobackuptool
```

> **Retention hängt NICHT mehr an einer Cron-Chain.** Sie läuft *innerhalb* des Scripts und nur dann, wenn das Backup wirklich `exit 0` liefert. Warum das wichtig ist, steht weiter unten unter ["Aus der Praxis"](#-aus-der-praxis-ein-sechs-wochen-langes-stilles-versagen).

---

## 🏗 Architektur-Notizen

### Der Permissions-Tanz mit `ecoDMSBackupConsole`

Der ecoDMS-`dpkg postinst` setzt `/opt/ecodms/ecodmsserver/tools/ecoDMSBackupConsole` bei *jedem* Paket-Update auf `root:root 700` zurück und legt eine sudoers-Regel mit Passwort-Pflicht an (`ALL ALL = PASSWD:.../ecoDMSBackupConsole`). Beides ist cron-untauglich.

ecobackups Workaround:

1. Einmal `ecobackup -s` → `chown ecodms:ecodms` + `chmod 710` + `usermod -a -G ecodms $USER`
2. Der root-Cron (nur vorhanden, wenn die Root-Crontab per `sudo ecobackup -i` installiert wurde) wendet chown/chmod täglich um **03:10** erneut an
3. Backups laufen als dein User (Mitglied der `ecodms`-Gruppe) — kein sudo-Passwort nötig

**Zeitliche Lücke:** Der 03:10-Job läuft *nach* den Backups (01:35–02:35). Nach einem ecoDMS-Update können deshalb die nächsten Backups einmal fehlschlagen — typischerweise `Permission denied`, Exit 126 im Log und eine rote Meldung —, bevor der root-Cron die Rechte repariert. Wer nicht bis zur nächsten Nacht warten will, führt nach einem ecoDMS-Update direkt `ecobackup -s` aus.

### Lock-Modell

Ein einziges, globales Lockfile (`LOCKFILE`, Default `/tmp/ecobackup.lock`) für alle Backup-Slots — bewusst einfach gehalten:

- Beim Start prüft das Skript, ob die Datei existiert, und legt sie dann per `touch` an (**check-then-touch**, nicht atomar). Beim Beenden räumt ein `trap … EXIT` sie wieder weg. Zwei exakt gleichzeitig startende Läufe könnten theoretisch beide durchrutschen.
- Existiert das Lockfile, bricht der Lauf mit Warnung ab: Log-Zeile, Discord-`warn`, Exit 1. Es gibt keinen Retry und kein Nachholen. Ein langer Lauf lässt also die nachfolgenden Cron-Slots ausfallen — sie liegen nur 10 bis 20 Minuten auseinander.
- **Keine Stale-Lock-Recovery:** Nach einem Absturz, `kill -9` oder Stromausfall bleibt das Lockfile liegen, und **jeder weitere Lauf überspringt sich mit Warnung**, bis du es von Hand entfernst: `rm /tmp/ecobackup.lock` (zuvor prüfen, dass wirklich kein ecobackup mehr läuft; hat root die Datei angelegt, ist `sudo rm` nötig).

Lockfile pro Ziel + Stale-Lock-Recovery stehen auf der [Roadmap](#-roadmap).

### Exit-Code-Vertrag

**`ecoDMSBackupConsole`** (empirisch verifiziert auf ecoDMS 26.01):

| BackupConsole exit | Bedeutung |
|---|---|
| `0` | Erfolg |
| `2` | Fehler (ungültiger Pfad, fehlendes Argument, kein Schreibrecht) |

Ältere Community-Quellen sagen "kein errorlevel" — das ist für 26.01 **veraltet**. ecobackup verlässt sich auf den Exit-Code; bei älteren ecoDMS-Versionen bitte vorher testen.

**`ecobackup` selbst** (für Cron, Skripte und Monitoring):

| ecobackup exit | Bedeutung |
|---|---|
| `0` | Erfolg — auch bei `-h`, `-V`, `-t` |
| `1` | Fehler: BackupConsole lieferte ≠ 0 (ecobackup gibt immer `1` weiter, der Original-Code steht nur im Log und in der Meldung), Lockfile vorhanden, ungültige Option, Verzeichnis bei `-a`/`-c` fehlt, `-t` ohne Webhook, ungültiges Ziel bei `-i print` |

Achtung: `ecobackup -s` und `ecobackup -i` beenden sich mit `0`, **auch wenn ein Teilschritt scheiterte** (`-s` gibt immer "Rechte gesetzt!" aus). Das Ergebnis selbst prüfen (`ls -l`, `crontab -l`).

### Restore

Das Zurückspielen ist **nicht Teil von ecobackup**. Die erzeugten `DMSbackup*.zip` werden mit den von ecoDMS vorgesehenen Restore-Mitteln wiederhergestellt — siehe die offizielle ecoDMS-Dokumentation. ecobackup prüft die Zips nicht auf Integrität (steht auf der [Roadmap](#-roadmap)); ein Test-Restore auf einem Testsystem ist daher ratsam.

---

## 🩺 Fehlersuche

| Symptom | Ursache und Abhilfe |
|---|---|
| `Permission denied` / `BackupConsole exit 126` im Log | Rechte der BackupConsole oder Gruppenmitgliedschaft fehlen — typisch direkt nach einem ecoDMS-Update (siehe [Zeitliche Lücke](#der-permissions-tanz-mit-ecodmsbackupconsole)). `ecobackup -s` erneut als Cron-User ausführen und neu einloggen. Prüfen: `ls -l /opt/ecodms/ecodmsserver/tools/ecoDMSBackupConsole` (erwartet `-rwx--x--- ecodms ecodms`) und `id` (enthält `ecodms`). |
| `BackupConsole exit 2` | Zielverzeichnis existiert nicht oder ist für den Cron-User nicht beschreibbar (laut [Exit-Code-Vertrag](#exit-code-vertrag)). |
| `Backup läuft bereits (lockfile: …)` / "Lockfile vorhanden" | Läuft ein anderer Slot noch (`pgrep -af ecobackup`)? Falls nicht, ist das Lockfile ein Überbleibsel: `rm /tmp/ecobackup.lock` (ggf. mit `sudo`). Siehe [Lock-Modell](#lock-modell). |
| Keine Discord-Meldung | 1. `ls -l /etc/ecobackup/notify.conf` — muss für den Cron-User lesbar sein (`root:ecodms 640`, Cron-User in Gruppe `ecodms`). 2. `NOTIFY_ENABLED` nicht `0`, Webhook-URL gesetzt. 3. `curl` und `python3` installiert (`command -v curl python3`). 4. `ecobackup -t` als Cron-User (nicht per `sudo`) ausführen; "Kein NOTIFY_DISCORD_WEBHOOK konfiguriert" heißt: Datei nicht lesbar oder Variable leer. 5. Bleibt der Channel leer, die Webhook-URL in Discord prüfen — Zustellfehler werden nicht gemeldet. |
| Kein Logfile / Log bleibt leer | `/var/log/ecobackup.log` existiert nicht oder ist für den Cron-User nicht beschreibbar; der Fehler wird bewusst unterdrückt. Datei anlegen (Quick Start, Schritt 4) oder `LOGFILE` in der Conf auf einen beschreibbaren Pfad setzen. Nicht per `sudo` laufen lassen, bevor die Datei existiert — root legt sie sonst als `root:root 644` an. |
| `-a`-Slot läuft, meldet aber nichts | Zielverzeichnis fehlt (z. B. Mount nicht da) — nur Log-Zeile `Fehler: Verzeichnis … existiert nicht!`, Exit 1, keine Meldung. |
| `ecobackup -i`: "root-crontab nicht installiert" | Ohne `sudo` aufgerufen — für die Root-Crontab `sudo ecobackup -i` (Warnung im Abschnitt [Cron-Layout](#-cron-layout) beachten). |
| `ecobackup -i`: "skip: … nur als … oder root installierbar" | `CRON_USER` ist nicht der aktuelle User — als dieser User oder per `sudo` aufrufen. |
| Config-Werte greifen nicht | `/etc/ecobackup/ecobackup.conf` für den Cron-User nicht lesbar (wird dann stillschweigend ignoriert), oder der Wert fließt in die Crontab ein und braucht erneutes `ecobackup -i`. |

---

## 🧹 Deinstallation

```bash
# 1. Cron-Einträge entfernen (als Cron-User und als root)
crontab -l            # prüfen, was drinsteht
crontab -e            # ecobackup-Zeilen löschen (oder, wenn nichts anderes drinsteht: crontab -r)
sudo crontab -e       # ebenso; die Root-Crontab enthält auch die cups-Jobs

# 2. Skript, Config und Hilfsdateien entfernen
sudo rm /usr/bin/ecobackup
sudo rm -r /etc/ecobackup
sudo rm -f /var/log/ecobackup.log /tmp/ecobackup.lock /etc/logrotate.d/ecobackup   # soweit vorhanden

# 3. Gruppenmitgliedschaft zurücknehmen
sudo gpasswd -d <user> ecodms
```

`ecobackup -s` hat Owner und Mode der `ecoDMSBackupConsole` auf `ecodms:ecodms 710` gesetzt; das ecoDMS-Paket stellt beim nächsten Update wieder `root:root 700` her. Die bisher erzeugten Backups in den Zielverzeichnissen bleiben unangetastet.

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

### Was in v1.x geändert wurde

| Version | Änderung |
|---|---|
| **Hotfix** (interner Zwischenstand, nicht getaggt) | `tee -a "$LOGFILE" 2>/dev/null; return 0` — `log()` kann den Exit-Status nicht mehr kippen. Logfile chown auf den Cron-User. |
| **v1.1** (interner Zwischenstand, nicht getaggt) | Retention in das Script gezogen; `&&`-Chains aus dem Cron raus. Bug-Klasse strukturell weg. |
| **v1.2** | Pfade konfig-driven, eingebettete Crontabs, Discord-Notify, generisches User-Refactoring fürs Public Release. |
| **v1.3** | Kompatibilitäts-Shim: `TELEKOM_DIR`/`TELEKOM_KEEP_DAYS` → `EXTRA_DIR`/`EXTRA_KEEP_DAYS` (alte Namen funktionieren weiter, mit Deprecation-Warnung); neu `ecobackup -V`/`--version`; Doku-Korrekturen (Lock-Modell, Crontab-Warnung, Voraussetzungen, Rechte für `notify.conf` und Logfile, Retention, Exit-Codes, Fehlersuche, Deinstallation). |

Die Logfile-Falle gilt auch heute noch: Deshalb legt der [Quick Start](#-quick-start) das Logfile mit passenden Rechten an, bevor irgendetwas als root läuft.

### Lehre

> **Ein Logging-Aufruf darf niemals den Exit-Status eines Skripts ändern können.** Die "fail loud"-Schule hat im Geist recht — aber wenn dein "fail loud"-Mechanismus über denselben Kanal läuft wie das Ding, das versagt hat (ein Side-Effect beim Logging), dann fällst du stattdessen *still* um.

---

## 🗺 Roadmap

- [ ] **Integritäts-Verifikation** — `unzip -tq` + SQL-Header-Check vor Prune
- [ ] **`age`-verschlüsselte Off-Site-Backups** — Schutz vor Zugriff durch den Cloud-/Hosting-Anbieter
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
- Neue Notify-Adapter (eine kurze Funktion nach dem Vorbild von `_notify_discord` plus ein Aufruf in `notify()`)
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

Gebaut mit 🛠 von [@sgtsilver](https://github.com/sgtsilver) — v1.3, seit v1.2 in Pair-Programming-Sessions mit 🤖 [Claude Code](https://claude.com/claude-code).
*Wenn dieses Skript dein Backup gerettet hat, hinterlass einen ⭐.*

</div>
