# Wilkommen zum EcoDMS Backup Tool

Es handelt sich hierbei um ein **einfaches** Script was euch das sichern eures EcoDMS leichter macht.
Das Script kann leicht automatisiert werden via Cronjob.

Funktionen des Scripts:
* Tägliches Backup in einen Vordifinierten Pfad
* Monatliches Backup in einen Vordifinierten Pfad
* Backup auf eine Gemountete Location (in meinem Fall eine Hetzner Storagebox)
* Manuelles Backup in einen eigenen Backuppfad (dieser muss bei jedem Run gesetzt werden)
* Direktes Backup mit Pfadangabe
* Initiales Setup (Gruppe und Berechtigung setzen für das ecoDMSBackupConsole Programm)

Das ganze Funktioniert dann auf Schalterbasis.

Ich übernehme keine Haftung wenn Ihr euch euer EcoDMS oder ein Backup mit dem Script zerschießt. Ebenso bin ich nicht der allwissende Bash Script schreiber. Vielleicht fällt euch ja noch eine verbesserung ein. Würde mich jedenfalls freuen.

Getestet wurde das Script auf Debian-basierten Betriebssystemen auf denen **SUDO** installiert war.
