# Linux-Omarchy-Kit

Meine Optik-Anpassungen für [Omarchy](https://omarchy.org) (Hyprland + Omarchy-Shell).
Alles im Stil **„Rauchglas"**: graphit, leicht durchsichtig, Hintergrund nur hinter der
Karte weichgezeichnet, feiner weisser Rand mit Licht oben rechts / unten links.
Nichts blinkt oder bewegt sich in der Leiste.

Getestet mit Omarchy **4.0.6** und dem Theme **Vantablack** (Standard-Theme von Omarchy).
Der Glas-Stil gilt aber für jedes Theme.

## Was ist drin

### 1. Glas-Stil „Rauchglas" – `config/omarchy/shell.toml`
Einheitliche Werte für alle Omarchy-Flächen:
- Graphit `#151413`, Deckkraft `0.70`, Rand weiss `0.14` mit Lichtverlauf (135°)
- Auswahl `0.11` Füllung + `0.32` Rand, Abdunkelung hinter Menüs nur `0.22`
- gilt für: Leisten-Fenster (Audio, WLAN, Bluetooth, Akku …), Omarchy-Menü, Apps-Starter,
  Zwischenablage, Emojis, Benachrichtigungen, Passwort-Fenster, Sperrbildschirm,
  Bilderauswahl, Tooltips, Knöpfe
- Leiste oben 32 px hoch und ohne eigenen Hintergrund (das Glas kommt von `cillian.leiste`)

### 2. Fenster-Look – `config/hypr/looknfeel.lua`
- runde Ecken (12), weiche Schatten, Blur (size 5, passes 2, vibrancy 0.25)
- schwungvollere Animationen (Pop-in, Slide-Fade zwischen Arbeitsflächen)
- langsam drehender weiss-grauer Rand ums aktive Fenster
- Spalten-Layout (`scrolling`): Fenster öffnen nebeneinander
- Blur-Regeln für alle Glas-Flächen (Startmenü, Leiste, Kalender, Musik, Menüs …)

### 3. Shell-Plugins – `config/omarchy/plugins/`
| Plugin | Was | Taste |
|---|---|---|
| `cillian.start` | Startmenü: Uhr, Suche, CPU/RAM/Akku, Favoriten + Ordner, Bearbeiten-Modus (ziehen, Ordner anlegen), Ein/Aus | `SUPER + SPACE` |
| `cillian.leiste` | Glas-Kapsel hinter der oberen Leiste (Schatten, Glanz, helle Rand-Enden) | – |
| `cillian.music` | Musik-Panel unten links: Cover, Titel, Fortschritt, Zurück / Play-Pause / Weiter / Stopp (MPRIS). Bleibt offen, bis man nochmal drückt | `Page_Up` |
| `cillian.agents` | Claude-Anzeige in der Leiste: Ring füllt sich mit dem Session-Limit, Panel mit Ringen (Session/Woche), Säulen der letzten 7 Tage, Modelle – ab 90 % rot | Klick in der Leiste |
| `cillian.monitore` | Bildschirme anordnen wie in Windows: ziehen, identifizieren, übernehmen (speichert in `monitors.lua`) | `SUPER + ALT + D` |
| `cillian.background` | Hintergrund, der auch **Videos** (mp4, mkv, webm …) als Hintergrund abspielen kann | – |
| `cillian.kalender` | Kalender-App mit Foto, siehe unten | Klick in der Leiste |

Favoriten des Startmenüs stehen in `~/.config/cillian-start/pins.json`, z. B.
`{"pins":["brave-browser", {"folder":"Spiele","apps":["steam"]}]}`.
Versteckte Apps (NoDisplay) zusätzlich in `~/.config/cillian-start/extra-apps.json` eintragen.
Rechtsklick auf eine App im Startmenü = Favorit an/aus.

### 4. Kalender-App mit Foto – `cillian.kalender` + `bin/kalender-foto`
Kalender-Zeichen oben in der Leiste neben der Uhr.
1. Am Morgen einen **Screenshot vom Outlook-Kalender** machen (Rechtsklick aufs Zeichen =
   Bereich aufnehmen, oder ein Bild aus der Zwischenablage einfügen).
2. **Claude liest die Woche** aus dem Bild (`claude -p`, Modell Sonnet) und macht daraus
   einen echten Kalender im Glas-Panel: Wochenleiste, Stundenraster, Jetzt-Linie, „Als Nächstes".
3. **Erinnerung** vor jedem Termin (Standard 10 Min, pro Termin einstellbar).
   **Gelbe Termine = Teams-Call** (eigenes Zeichen, Vorlaufzeit separat einstellbar).
- Termine anklicken = bearbeiten, leere Stelle = neuer Termin, ⚙ = Einstellungen.
- Solange das Foto für heute fehlt, zeigt das Zeichen ein „!".
- Fotos und Termine: `~/Pictures/Kalender/`, Einstellungen: `~/.config/kalender-foto/settings.json`.

### 5. Teams im Rauchglas-Look – `teams-schoen/`
Kleine Brave/Chromium-Erweiterung (nur CSS) für die Teams-Web-App:
graphit statt lila, Glas-Karten für Chatliste, Kopf und Chat, schönere Chat-Blasen,
auch der Teams-Kalender. Nur fürs **dunkle** Teams-Design gebaut.

## Voraussetzungen
- Omarchy 4.x (Hyprland mit Lua-Config, Omarchy-Shell)
- `jq`
- für den Kalender: `grim`, `slurp`, `wl-clipboard`, `imv`, `libnotify` und die
  [Claude Code](https://claude.com/claude-code) CLI (`claude`, eingeloggt)
- für Teams: Brave oder Chromium

## Installieren
```bash
git clone https://github.com/CillX111/Linux-Omarchy-Kit.git
cd Linux-Omarchy-Kit
./install.sh               # alles
./install.sh --ohne-teams  # ohne Teams-Erweiterung
```
Das Skript
- macht zuerst ein **Backup** von allem, was es ersetzt: `~/.local/share/omarchy-kit-backup/<zeit>/`
- kopiert `shell.toml`, `looknfeel.lua`, die Plugins und die Helfer nach `~/.local/bin`
- hängt die drei Tasten (SUPER+SPACE, Page_Up, SUPER+ALT+D) einmal an `bindings.lua` an
- schaltet die Plugins mit `omarchy plugin enable` ein (Klone ersetzen das Omarchy-Original)
- trägt die Teams-Erweiterung in `brave-flags.conf` / `chromium-flags.conf` ein
- lädt Hyprland und die Shell neu (`omarchy restart shell`)

Teams-Look wirkt erst nach einem **Neustart des Browsers**.

> Achtung: `looknfeel.lua` und `shell.toml` werden **ersetzt**, nicht zusammengeführt.
> Eigene Änderungen darin liegen danach im Backup.

## Rückgängig machen
```bash
# Plugins weg (Klone schalten auf das Omarchy-Original zurück)
for p in start leiste music monitore kalender agents background; do omarchy plugin remove cillian.$p --yes; done
# Dateien aus dem Backup zurückholen
cp -a ~/.local/share/omarchy-kit-backup/<zeit>/.config/. ~/.config/
omarchy restart shell
```
Dann noch den Block `>>> Linux-Omarchy-Kit` aus `~/.config/hypr/bindings.lua` löschen und
den `teams-schoen`-Pfad aus `brave-flags.conf` nehmen.

## Hinweise
- Änderungen an Plugins brauchen `omarchy restart shell` (Hot-Reload greift nicht).
- `cillian.agents` und `cillian.background` sind Klone der Omarchy-Plugins `omarchy.agents`
  und `omarchy.background` (MIT-Lizenz, © Omarchy). Omarchy-Updates an diesen beiden
  Plugins kommen bei den Klonen nicht automatisch an.
- Hintergrundbilder sind nicht dabei (fremde Bilder).
