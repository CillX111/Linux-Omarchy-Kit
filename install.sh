#!/bin/bash
# Linux-Omarchy-Kit installieren.
# Alles, was ersetzt wird, kommt vorher nach ~/.local/share/omarchy-kit-backup/<zeit>/.
#
#   ./install.sh            alles installieren
#   ./install.sh --ohne-teams   ohne die Teams-Erweiterung
set -euo pipefail

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFG="$HOME/.config"
BIN="$HOME/.local/bin"
BK="$HOME/.local/share/omarchy-kit-backup/$(date +%Y%m%d-%H%M%S)"
TEAMS=1
[[ ${1:-} == "--ohne-teams" ]] && TEAMS=0

need() { command -v "$1" >/dev/null 2>&1 || { echo "Fehlt: $1 – bitte zuerst installieren." >&2; exit 1; }; }
need jq
need omarchy
need omarchy-shell
need hyprctl

# backup <pfad>: Kopie ins Backup-Verzeichnis (gleicher Pfad unter $HOME)
backup() {
  [[ -e $1 || -L $1 ]] || return 0
  local rel="${1#"$HOME"/}"
  mkdir -p "$BK/$(dirname "$rel")"
  cp -a "$1" "$BK/$rel"
}

echo "==> Backup nach $BK"
mkdir -p "$BK"

# 1) Glas-Stil "Rauchglas" (gilt für jedes Theme)
echo "==> Glas-Stil (shell.toml)"
backup "$CFG/omarchy/shell.toml"
install -Dm644 "$KIT/config/omarchy/shell.toml" "$CFG/omarchy/shell.toml"

# 2) Fenster-Look (Ecken, Schatten, Blur, Animationen, drehender Rand, Blur-Regeln)
echo "==> Fenster-Look (looknfeel.lua)"
backup "$CFG/hypr/looknfeel.lua"
install -Dm644 "$KIT/config/hypr/looknfeel.lua" "$CFG/hypr/looknfeel.lua"

# 3) Plugins + Helfer-Skripte
echo "==> Plugins"
mkdir -p "$CFG/omarchy/plugins"
for dir in "$KIT"/config/omarchy/plugins/*/; do
  id="$(basename "$dir")"
  backup "$CFG/omarchy/plugins/$id"
  rm -rf "$CFG/omarchy/plugins/$id"
  cp -a "$dir" "$CFG/omarchy/plugins/$id"
  echo "    $id"
done

mkdir -p "$BIN"
for f in "$KIT"/bin/*; do
  backup "$BIN/$(basename "$f")"
  install -m755 "$f" "$BIN/"
done

# Startmenü: Beispiel-Favoriten nur, wenn noch keine eigenen da sind
mkdir -p "$CFG/cillian-start"
for f in pins.json extra-apps.json; do
  [[ -e $CFG/cillian-start/$f ]] || cp "$KIT/config/cillian-start/$f" "$CFG/cillian-start/$f"
done

# Tasten: SUPER+SPACE Startmenü, Page_Up Musik, SUPER+ALT+D Monitore (nur einmal anhängen)
BIND="$CFG/hypr/bindings.lua"
if ! grep -qF ">>> Linux-Omarchy-Kit" "$BIND" 2>/dev/null; then
  echo "==> Tasten (bindings.lua)"
  backup "$BIND"
  printf '\n%s\n' "$(cat "$KIT/config/hypr/bindings-kit.lua")" >> "$BIND"
fi

# Plugins in der Shell anmelden. "omarchy plugin enable" ersetzt bei Klonen
# (cillian.agents, cillian.background) automatisch das Omarchy-Original.
echo "==> Plugins einschalten"
backup "$CFG/omarchy/shell.json"
omarchy-shell shell rescanPlugins >/dev/null
for _ in $(seq 40); do
  omarchy plugin list --json | jq -e 'any(.[]; .id == "cillian.start")' >/dev/null && break
  sleep 0.1
done
for id in cillian.background cillian.music cillian.monitore cillian.start cillian.leiste cillian.agents; do
  omarchy plugin enable "$id" || echo "    (Warnung: $id liess sich nicht einschalten)"
done
omarchy plugin enable cillian.kalender --section center --after omarchy.clock ||
  omarchy plugin enable cillian.kalender --section center || echo "    (Warnung: cillian.kalender liess sich nicht einschalten)"

# Leistentext immer in Theme-Farbe (das Glas kommt vom Plugin cillian.leiste)
SJ="$CFG/omarchy/shell.json"
if [[ -s $SJ ]]; then
  tmp="$(mktemp)"
  jq '.bar.transparent = false' "$SJ" > "$tmp" && mv "$tmp" "$SJ"
fi

# 5) Teams im Rauchglas-Look (Brave/Chromium-Erweiterung, nur CSS)
if (( TEAMS )); then
  echo "==> Teams-Erweiterung"
  EXT="$HOME/.local/share/omarchy-kit/teams-schoen"
  rm -rf "$EXT"
  mkdir -p "$(dirname "$EXT")"
  cp -a "$KIT/teams-schoen" "$EXT"
  found=0
  for flags in "$CFG/brave-flags.conf" "$CFG/chromium-flags.conf"; do
    [[ -e $flags ]] || continue
    found=1
    grep -qF "$EXT" "$flags" && continue
    backup "$flags"
    if grep -q '^--load-extension=' "$flags"; then
      sed -i "s|^--load-extension=.*|&,$EXT|" "$flags"
    else
      echo "--load-extension=$EXT" >> "$flags"
    fi
    echo "    eingetragen in $(basename "$flags") – wirkt nach Browser-Neustart"
  done
  (( found )) || echo "    Keine brave-flags.conf / chromium-flags.conf gefunden – siehe README."
fi

echo "==> Neu laden"
hyprctl reload >/dev/null || true
omarchy restart shell || echo "Bitte selbst ausführen: omarchy restart shell"

echo
echo "Fertig. Backup: $BK"
echo "SUPER+SPACE = Startmenü, Page_Up = Musik, SUPER+ALT+D = Monitore, Kalender oben neben der Uhr."
