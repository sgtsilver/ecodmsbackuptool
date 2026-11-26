#!/bin/bash
# Regressionstest: ecobackup repariert die Rechte der BackupConsole vor dem Lauf
# (seit v1.4). Hintergrund: ecoDMS' dpkg-postinst setzt das Tool bei jedem
# Paket-Update auf mode 700 zurück; ohne Reparatur scheitert der nächste
# Cron-Lauf mit "BackupConsole exit 126".
#
# Läuft auf einem ecoDMS-Host als der Cron-User, vollständig in einer Sandbox
# unter mktemp: eigene Fake-BackupConsole (Kopie von /bin/true), eigenes Log-
# und Lockfile, Notifications werden abgefangen. Die echte BackupConsole, die
# Backup-Ziele, das echte Logfile und die Crontabs werden nicht angefasst.
#
# Voraussetzungen: sudo ohne Passwort; User und Gruppe "ecodms" existieren;
# der aufrufende User ist Mitglied der Gruppe ecodms.
#
# Usage: tests/selfrepair.sh [pfad/zu/ecobackup]      (Default: ../ecobackup)
# Exit:  0 = alle Fälle ok, 1 = mindestens ein Fall fehlgeschlagen,
#        2 = Voraussetzungen fehlen

SCRIPT="${1:-$(cd "$(dirname "$0")/.." && pwd)/ecobackup}"

for tool in sudo stat mktemp getent id; do
   command -v "$tool" >/dev/null 2>&1 || { echo "fehlt: $tool" >&2; exit 2; }
done
[ -r "$SCRIPT" ]                     || { echo "nicht lesbar: $SCRIPT" >&2; exit 2; }
[ -x /bin/true ]                     || { echo "fehlt: /bin/true" >&2; exit 2; }
sudo -n true 2>/dev/null             || { echo "sudo ohne Passwort nötig" >&2; exit 2; }
getent group ecodms >/dev/null       || { echo "Gruppe ecodms fehlt" >&2; exit 2; }
case " $(id -nG) " in
   *" ecodms "*) ;;
   *) echo "$(id -un) ist nicht in der Gruppe ecodms" >&2; exit 2;;
esac

SANDBOX=$(mktemp -d) || exit 2
trap 'rm -rf "$SANDBOX"' EXIT
REAL_PATH=$PATH

# Skript laden, ohne einen Modus zu starten (ohne Argumente gibt es nur die
# Hilfe aus). Danach alles auf die Sandbox umbiegen — nach dem Laden, damit
# die Site-Config die Werte nicht wieder überschreibt.
set --
# shellcheck disable=SC1090
source "$SCRIPT" >/dev/null
declare -F run_backup >/dev/null || { echo "run_backup nicht gefunden in $SCRIPT" >&2; exit 2; }

BACKUP_TOOL="$SANDBOX/fakeBackupConsole"
LOGFILE="$SANDBOX/ecobackup.log"
LOCKFILE="$SANDBOX/ecobackup.lock"
DEST="$SANDBOX/dest"
NOTIFY_LOG="$SANDBOX/notify.log"
SUDO_CALLS="$SANDBOX/sudo.calls"
unset HB_JOB
notify() { printf '%s|%s|%s\n' "$1" "$2" "${3//$'\n'/ ; }" >> "$NOTIFY_LOG"; return 0; }

# Fake-sudo-Varianten für die Fälle, in denen die Reparatur nicht gelingen darf.
mkdir -p "$SANDBOX/sudo-refuses" "$SANDBOX/sudo-noop" "$DEST"
cat > "$SANDBOX/sudo-refuses/sudo" <<EOF
#!/bin/bash
echo "\$*" >> "$SUDO_CALLS"
echo "sudo: a password is required" >&2
exit 1
EOF
cat > "$SANDBOX/sudo-noop/sudo" <<EOF
#!/bin/bash
echo "\$*" >> "$SUDO_CALLS"
exit 0
EOF
chmod 755 "$SANDBOX/sudo-refuses/sudo" "$SANDBOX/sudo-noop/sudo"

# Ausgangszustand herstellen: <owner:group> <mode>
reset_case()
{
   PATH=$REAL_PATH
   rm -f "$BACKUP_TOOL" "$LOGFILE" "$LOCKFILE" "$NOTIFY_LOG" "$SUDO_CALLS"
   cp /bin/true "$BACKUP_TOOL"
   sudo -n chown "$1" "$BACKUP_TOOL" && sudo -n chmod "$2" "$BACKUP_TOOL" \
      || { echo "Sandbox-Setup fehlgeschlagen" >&2; exit 2; }
}

tool_state() { stat -c '%U:%G %a' "$BACKUP_TOOL"; }
in_log()     { grep -qF -- "$1" "$LOGFILE" 2>/dev/null; }
in_notify()  { grep -qE -- "$1" "$NOTIFY_LOG" 2>/dev/null; }

FAILED=0
N=0
check()
{
   local name=$1; shift
   N=$((N + 1))
   if "$@"; then
      echo "ok $N - $name"
   else
      echo "not ok $N - $name"
      FAILED=1
   fi
}
is()  { [ "$1" = "$2" ] || { echo "    erwartet: '$2', bekommen: '$1'"; return 1; }; }
not() { ! "$@"; }

# --- Fall 1: Zustand nach einem ecoDMS-Paket-Update (root:root 700) -----------
reset_case root:root 700
( run_backup "$DEST" 7 "Testlauf" ) >/dev/null 2>&1; rc=$?
check "nach Paket-Update: Lauf endet mit exit 0"            is "$rc" 0
check "nach Paket-Update: BackupConsole wurde ausgeführt"   in_log "Backup erfolgreich! (exit 0"
check "nach Paket-Update: Rechte stehen auf ecodms:ecodms 710" is "$(tool_state)" "ecodms:ecodms 710"
check "nach Paket-Update: Reparatur steht im Log"           in_log "Rechte der BackupConsole repariert"
check "nach Paket-Update: ok-Meldung nennt die Reparatur"   in_notify '^ok\|.*Rechte der BackupConsole repariert'
check "nach Paket-Update: Lockfile ist wieder weg"          not test -e "$LOCKFILE"

# --- Fall 2: Rechte in Ordnung → keine Reparatur, kein sudo ------------------
reset_case ecodms:ecodms 710
PATH="$SANDBOX/sudo-refuses:$REAL_PATH"
( run_backup "$DEST" 7 "Testlauf" ) >/dev/null 2>&1; rc=$?
PATH=$REAL_PATH
check "Rechte ok: Lauf endet mit exit 0"                    is "$rc" 0
check "Rechte ok: sudo wurde nicht aufgerufen"              not test -e "$SUDO_CALLS"
check "Rechte ok: keine Reparatur im Log"                   not in_log "repariert"
check "Rechte ok: ok-Meldung ohne Reparatur-Hinweis"        not in_notify 'repariert'

# --- Fall 3: sudo verlangt ein Passwort → klarer Fehler statt exit 126 -------
reset_case root:root 700
PATH="$SANDBOX/sudo-refuses:$REAL_PATH"
( run_backup "$DEST" 7 "Testlauf" ) >/dev/null 2>&1; rc=$?
PATH=$REAL_PATH
check "sudo verweigert: Lauf endet mit exit 1"              is "$rc" 1
check "sudo verweigert: Fehlermarke im Log"                 in_log "Backup FEHLGESCHLAGEN!"
check "sudo verweigert: Log nennt die Ursache"              in_log "nicht ausführbar und nicht reparierbar"
check "sudo verweigert: Log enthält die sudo-Meldung"       in_log "a password is required"
check "sudo verweigert: kein nacktes exit 126"              not in_log "exit 126"
check "sudo verweigert: err-Meldung nennt die Ursache"      in_notify '^err\|.*nicht ausführbar'
check "sudo verweigert: Lockfile ist wieder weg"            not test -e "$LOCKFILE"

# --- Fall 4: sudo meldet Erfolg, Tool bleibt unausführbar (z. B. User nicht --
# --- in der Gruppe ecodms) → gleicher klarer Fehler --------------------------
reset_case root:root 700
PATH="$SANDBOX/sudo-noop:$REAL_PATH"
( run_backup "$DEST" 7 "Testlauf" ) >/dev/null 2>&1; rc=$?
PATH=$REAL_PATH
check "wirkungslose Reparatur: Lauf endet mit exit 1"       is "$rc" 1
check "wirkungslose Reparatur: Log nennt die Ursache"       in_log "nicht ausführbar und nicht reparierbar"
check "wirkungslose Reparatur: kein Erfolg gemeldet"        not in_log "Backup erfolgreich"

# --- Fall 5: fehlendes Tool → "nicht gefunden", kein Reparaturversuch --------
reset_case root:root 700
rm -f "$BACKUP_TOOL"
PATH="$SANDBOX/sudo-refuses:$REAL_PATH"
( run_backup "$DEST" 7 "Testlauf" ) >/dev/null 2>&1; rc=$?
PATH=$REAL_PATH
check "Tool fehlt: Lauf endet mit exit 1"                   is "$rc" 1
check "Tool fehlt: Log sagt 'nicht gefunden'"               in_log "BackupConsole nicht gefunden"
check "Tool fehlt: sudo wurde nicht aufgerufen"             not test -e "$SUDO_CALLS"

# --- Fall 6: interaktiver Modus (-c) repariert ebenfalls ---------------------
reset_case root:root 700
( Custom <<< "$DEST" ) >/dev/null 2>&1; rc=$?
check "-c nach Paket-Update: Lauf endet mit exit 0"         is "$rc" 0
check "-c nach Paket-Update: BackupConsole wurde ausgeführt" in_log "Backup erfolgreich! (exit 0"
check "-c nach Paket-Update: Rechte stehen auf ecodms:ecodms 710" is "$(tool_state)" "ecodms:ecodms 710"

echo "# $N Prüfungen, $([ "$FAILED" -eq 0 ] && echo "alle ok" || echo "FEHLER")"
exit "$FAILED"
