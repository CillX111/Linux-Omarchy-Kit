import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Commons as Commons

// Startmenü (SUPER + SPACE): Uhr + Begrüssung, Live-Werte (CPU/RAM/Akku),
// Suche (Apps, Aktionen, Rechner), Favoriten, Ordner (unten), Alle Apps,
// Ein/Aus-Knöpfe. Gerufen mit `omarchy-shell shell toggle cillian.start`.
//
// Tasten: tippen = suchen, Pfeile = auswählen, Enter = öffnen,
// Tab = Alle Apps / zurück, Ctrl+P = an-/losheften, Esc = schliessen.
// Maus: Rechtsklick auf eine App = an-/losheften.
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  // ---------------------------------------------------------------- Apps
  // Eigene kleine App-Bibliothek: die appLibrary der Shell bekommen
  // User-Plugins nicht, darum Desktop-Einträge direkt lesen.
  property var hiddenIds: ({})

  function sortedEntries(query) {
    var q = String(query || "").toLowerCase()
    var values = (DesktopEntries.applications.values || []).slice()
    // Versteckte Apps (NoDisplay, z.B. die CILLS-Apps) liefert Quickshell nicht in der
    // Liste: bekannte IDs (extra-apps.json + alles in Favoriten/Ordnern) einzeln holen.
    var wanted = root.knownHiddenIds()
    for (var w = 0; w < wanted.length; w++) {
      var he = DesktopEntries.byId(wanted[w])
      if (he) values.push(he)
    }
    var out = []
    var seen = ({})
    for (var i = 0; i < values.length; i++) {
      var e = values[i]
      var id = String((e && e.id) || "")
      var known = root.extraIds.indexOf(id) >= 0
      if (!e || seen[id] || (!known && i < values.length - wanted.length && (e.noDisplay || root.hiddenIds[id]))) continue
      seen[id] = true
      var name = String(e.name || "").toLowerCase()
      var score = 0
      if (q) {
        var hay = name + " " + String(e.genericName || "").toLowerCase() + " " + String(e.comment || "").toLowerCase()
          + " " + (e.keywords || []).join(" ").toLowerCase() + " " + id.toLowerCase()
        if (name.indexOf(q) === 0) score = 3
        else if (name.indexOf(" " + q) >= 0) score = 2.5
        else if (name.indexOf(q) >= 0) score = 2
        else if (hay.indexOf(q) >= 0) score = 1
        else continue
      }
      out.push({ e: e, score: score, name: name })
    }
    out.sort(function(a, b) { return b.score - a.score || a.name.localeCompare(b.name) })
    return out.map(function(x) { return x.e })
  }

  // Icon-Index wie die Omarchy-Shell: Qt findet viele App-Icons nicht über
  // das Theme, darum die Icon-Ordner einmal durchsuchen (SVG vor PNG).
  property var iconIndex: ({})
  property var pendingIconIndex: ({})

  property var extraIds: []
  function knownHiddenIds() {
    var ids = root.extraIds.slice()
    for (var i = 0; i < root.pins.length; i++) {
      var p = root.pins[i]
      if (typeof p === "string") ids.push(p)
      else if (p && Array.isArray(p.apps)) ids = ids.concat(p.apps)
    }
    return ids
  }

  FileView {
    id: extraFile
    path: Quickshell.env("HOME") + "/.config/cillian-start/extra-apps.json"
    printErrors: false
    onLoaded: {
      try { root.extraIds = JSON.parse(text()).apps || [] } catch (e) { root.extraIds = [] }
      if (root.opened) root.rebuild()
    }
  }

  function iconSource(icon) {
    var value = String(icon || "")
    if (value.length === 0) return Quickshell.iconPath("application-x-executable", true)
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return "file://" + value
    var found = root.iconIndex[value]
    if (found) return "file://" + found
    var themed = Quickshell.iconPath(value, true)
    return themed.length > 0 ? themed : Quickshell.iconPath("application-x-executable", true)
  }

  Process {
    id: iconScan
    running: true
    command: ["bash", "-c", [
      'dirs="$HOME/.icons $HOME/.local/share/icons";',
      'IFS=":"; for d in ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do dirs="$dirs $d/icons"; done; unset IFS;',
      'for ext in svg png; do',
      '  for base in $dirs; do',
      '    [[ -d $base ]] && find "$base" \\( -path "*/apps/*" -o -path "*/devices/*" \\) -name "*.$ext" 2>/dev/null;',
      '  done;',
      '  find /usr/share/pixmaps -maxdepth 1 -name "*.$ext" 2>/dev/null;',
      'done'
    ].join(" ")]
    onStarted: root.pendingIconIndex = ({})
    stdout: SplitParser {
      onRead: function(line) {
        var value = String(line || "").trim()
        var file = value.slice(value.lastIndexOf("/") + 1)
        var dot = file.lastIndexOf(".")
        var name = dot > 0 ? file.slice(0, dot) : file
        if (name && root.pendingIconIndex[name] === undefined) root.pendingIconIndex[name] = value
      }
    }
    onExited: root.iconIndex = root.pendingIconIndex
  }

  function loadHidden(raw) {
    var next = ({})
    for (var k in root.hiddenIds) next[k] = true
    var lines = String(raw || "").split(/\n/)
    for (var i = 0; i < lines.length; i++) {
      var id = lines[i].trim().replace(/\.desktop$/, "")
      if (id) next[id] = true
    }
    root.hiddenIds = next
  }

  FileView {
    path: root.omarchyPath + "/default/omarchy/launcher.hides"
    printErrors: false
    onLoaded: root.loadHidden(text())
  }

  Process {
    running: true
    command: ["bash", "-c", root.omarchyPath + "/shell/services/hidden-entries.sh Hyprland"]
    stdout: StdioCollector { onStreamFinished: root.loadHidden(text) }
  }

  // ------------------------------------------------------------- Zustand
  property bool opened: false
  property real reveal: opened ? 1 : 0
  Behavior on reveal { NumberAnimation { duration: root.opened ? 300 : 170; easing.type: root.opened ? Easing.OutQuint : Easing.InCubic } }
  property int openSerial: 0

  property string view: "start"          // start | all | edit | folder | folderEdit
  property int currentFolder: -1         // Index des offenen Ordners in pins
  property bool renaming: false
  property string renameText: ""
  property string filterText: ""
  property int selectedIndex: 0
  property var items: []
  property var sections: []
  property int appCount: 0
  property string toast: ""
  readonly property var emptyItem: ({ kind: "", id: "", name: "", detail: "", icon: "", glyph: "" })

  // Gemeinsam mit dem alten cillian.launcher: zuletzt / wie oft gestartet
  readonly property string statsPath: Quickshell.env("HOME") + "/.local/state/cillian-launcher/stats.json"
  property var stats: ({ recent: [], count: {} })
  readonly property string pinsPath: Quickshell.env("HOME") + "/.config/cillian-start/pins.json"
  property var pins: []
  property bool pinsLoaded: false

  // --------------------------------------------------------------- Farben
  readonly property color bg: Commons.Color.menu.background
  readonly property color fg: Commons.Color.menu.text
  readonly property color accent: Commons.Color.accent
  readonly property color glow: Commons.Color.foreground
  readonly property color scrimColor: Commons.Color.menu.scrim
  readonly property string fontFamily: Style.font.menuFamily

  // --------------------------------------------------------------- Masse
  // Grösse: höchstens 77 % des Designs und nie mehr als ~78 % der Bildschirmhöhe
  readonly property real k: Math.max(0.5, Math.min(0.77, panel.height * 0.78 / 900, panel.width * 0.62 / 880))
  function px(n) { return Math.round(n * root.k) }
  // Schrift schrumpft weniger mit, damit sie lesbar bleibt
  function fpx(n) { return Math.round(n * Math.max(0.8, root.k)) }

  readonly property int columns: 6
  readonly property int cardWidth: root.px(880)
  // Höhe passt sich dem Inhalt an (Kopf + Suche + Inhalt + Fuss), mit Unter- und Obergrenze
  readonly property int cardMax: Math.min(root.px(900), panel.height - root.px(70))
  readonly property int cardHeight: Math.max(root.px(560), Math.min(root.cardMax, root.px(212) + content.height + root.px(14) + root.px(76)))
  readonly property int pad: root.px(30)
  readonly property int innerWidth: cardWidth - pad * 2
  readonly property int cellWidth: Math.floor(innerWidth / columns)
  readonly property int cellHeight: root.px(112)
  readonly property int rowHeight: root.px(60)

  // ------------------------------------------------------------- Aktionen
  readonly property var actions: [
    { name: "Sperren", glyph: "󰌾", action: "omarchy-system-lock", keywords: "lock sperren bildschirm" },
    { name: "Screenshot", glyph: "󰹑", action: "omarchy-capture-screenshot", keywords: "screenshot bild foto capture" },
    { name: "Hintergrund", glyph: "󰸉", action: "omarchy-menu toggle background", keywords: "background wallpaper hintergrund" },
    { name: "Theme", glyph: "󰏘", action: "omarchy-menu toggle theme", keywords: "theme farben aussehen" },
    { name: "Omarchy-Menü", glyph: "󰣇", action: "omarchy-menu toggle root", keywords: "omarchy menu einstellungen settings system" },
    { name: "Monitore", glyph: "󰍹", action: "~/.local/bin/monitore-anordnen", keywords: "monitor bildschirm anordnen display" },
    { name: "Neustart", glyph: "󰜉", action: "omarchy-system-reboot", keywords: "reboot neustart restart", confirm: true },
    { name: "Ausschalten", glyph: "󰐥", action: "omarchy-system-shutdown", keywords: "shutdown ausschalten herunterfahren power", confirm: true }
  ]

  // --------------------------------------------------------------- Öffnen
  function open(payloadJson) {
    root.filterText = ""
    root.selectedIndex = 0
    root.view = "start"
    root.lastMouse = null
    root.confirmAction = ""
    statsFile.reload()
    pinsFile.reload()
    root.rebuild()
    root.opened = true
    flick.contentY = 0
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) {}
    // Test-Haken: '{"dragTest":[von, nach]}' spielt ein Ziehen ohne Maus nach
    if (Array.isArray(payload.dragTest)) Qt.callLater(function() {
      root.startDrag(payload.dragTest[0])
      var t = root.tileMap[payload.dragTest[1]]
      if (t) { var p = t.mapToItem(content, t.width * (payload.dragTest[2] || 0.5), t.height / 2); root.updateDrag(p.x, p.y) }
      root.finishDrag()
    })
    if (payload.folder !== undefined) root.currentFolder = payload.folder
    if (["all", "edit", "folder", "folderEdit"].indexOf(payload.view) >= 0) root.setView(payload.view)
    root.openSerial++
    sysProc.running = false
    sysProc.running = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() { root.opened = false }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "cillian.start")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  // ------------------------------------------------------------- Rechner
  function calc(text) {
    var t = String(text || "").replace(/,/g, ".").replace(/\s+/g, "")
    if (!/^[0-9.+\-*\/()%^]+$/.test(t) || !/\d/.test(t) || !/[+\-*\/%^]/.test(t)) return null
    t = t.replace(/\^/g, "**")
    try {
      var v = Function('"use strict"; return (' + t + ')')()
      if (typeof v !== "number" || !isFinite(v)) return null
      return String(+v.toFixed(10))
    } catch (e) {
      return null
    }
  }

  // ------------------------------------------------------------ Inhalte
  function appItem(entry) {
    return {
      kind: "app",
      id: String(entry.id || ""),
      name: String(entry.name || entry.id || ""),
      detail: String(entry.genericName || entry.comment || ""),
      icon: String(entry.icon || ""),
      glyph: ""
    }
  }

  function actionItem(a) {
    return { kind: "action", id: a.action, name: a.name, detail: "", icon: "", glyph: a.glyph, action: a.action, confirm: a.confirm === true }
  }

  // pins: Liste aus App-IDs (Text) und Ordnern ({ folder: "Name", apps: [IDs] })
  function isPinned(id) { return root.pins.indexOf(id) >= 0 }
  function isFolder(p) { return p && typeof p === "object" && Array.isArray(p.apps) }
  function folderAt(i) { var f = root.pins[i]; return root.isFolder(f) ? f : null }
  function inFolder(id) { var f = root.folderAt(root.currentFolder); return !!f && f.apps.indexOf(id) >= 0 }
  // Abzeichen ✓ im Bearbeiten-Modus
  function isMarked(item) {
    if (!item || item.kind !== "app") return false
    if (root.view === "folderEdit") return root.inFolder(item.id)
    return root.isPinned(item.id)
  }
  function clonePins() { return JSON.parse(JSON.stringify(root.pins)) }

  function folderItem(f, index, byId) {
    var list = []
    for (var i = 0; i < f.apps.length; i++) if (byId[f.apps[i]]) list.push(byId[f.apps[i]])
    return { kind: "folder", id: "folder:" + index, fi: index, name: String(f.folder || "Ordner"),
             detail: list.length + " Apps", icon: "", glyph: "󰉋", apps: list }
  }

  // Favoriten-Zeile: Apps und Ordner in gespeicherter Reihenfolge
  function pinnedItems(byId) {
    var out = []
    for (var p = 0; p < root.pins.length; p++) {
      var pin = root.pins[p]
      if (root.isFolder(pin)) out.push(root.folderItem(pin, p, byId))
      else if (byId[pin]) out.push(byId[pin])
    }
    return out
  }

  function rebuild() {
    var out = []
    var secs = []
    function addSection(title, style, cols, list, buttons, keepEmpty) {
      if (list.length === 0 && !keepEmpty) return
      secs.push({ title: title, style: style, cols: cols, start: out.length, count: list.length, buttons: buttons || [] })
      for (var i = 0; i < list.length; i++) out.push(list[i])
    }

    var entries = root.sortedEntries(root.filterText)
    var apps = []
    var byId = ({})
    for (var i = 0; i < entries.length; i++) {
      var item = root.appItem(entries[i])
      apps.push(item)
      byId[item.id] = item
    }
    if (!root.filterText) root.appCount = apps.length

    var folder = root.folderAt(root.currentFolder)
    if ((root.view === "folder" || root.view === "folderEdit") && !folder) root.view = "start"

    if (root.view === "folder" && !root.filterText) {
      var fApps = root.folderItem(folder, root.currentFolder, byId).apps
      addSection("󰉋  " + String(folder.folder || "Ordner"), "tile", root.columns, fApps,
                 [{ label: "✎  Bearbeiten", act: "folderEdit" }, { label: "‹  Zurück", act: "start" }], true)
      secs[secs.length - 1].reorder = "folder"
      if (fApps.length === 0) secs[secs.length - 1].empty = "Leer – oben rechts auf Bearbeiten und Apps antippen"
    } else if (root.view === "folderEdit") {
      var inside = root.folderItem(folder, root.currentFolder, byId).apps
      addSection("󰉋  " + String(folder.folder || "Ordner") + " · " + inside.length, "tile", root.columns, inside,
                 [{ label: "Aa  Umbenennen", act: "rename" }, { label: "󰆴  Löschen", act: "deleteFolder" }, { label: "✓  Fertig", act: "folder" }], true)
      secs[secs.length - 1].rename = true
      secs[secs.length - 1].reorder = "folder"
      if (inside.length === 0) secs[secs.length - 1].empty = "Noch leer – unten Apps antippen"
      addSection(root.filterText ? "Gefunden" : "Antippen zum Hinzufügen", "tile", root.columns,
                 apps.filter(function(x) { return !root.inFolder(x.id) }))
    } else if (root.view === "edit") {
      // Favoriten bearbeiten: oben die eigenen (Klick = entfernen), unten alle anderen (Klick = hinzufügen)
      var pinnedAll = root.pinnedItems(byId)
      var mine = pinnedAll.filter(function(x) { return x.kind === "app" })
      var myFolders = pinnedAll.filter(function(x) { return x.kind === "folder" })
      addSection("Deine Favoriten · " + mine.length, "tile", root.columns, mine,
                 [{ label: "✓  Fertig", act: "start" }], true)
      secs[secs.length - 1].reorder = "pins"
      if (mine.length === 0) secs[secs.length - 1].empty = "Noch keine – unten Apps antippen"
      addSection("Deine Ordner · " + myFolders.length, "tile", root.columns, myFolders,
                 [{ label: "+  Ordner", act: "newFolder" }], true)
      secs[secs.length - 1].reorder = "pins"
      if (myFolders.length === 0) secs[secs.length - 1].empty = "Noch keine – oben rechts «+ Ordner»"
      addSection(root.filterText ? "Gefunden" : "Antippen zum Hinzufügen", "tile", root.columns,
                 apps.filter(function(x) { return !root.isPinned(x.id) }))
    } else if (root.filterText) {
      var result = root.calc(root.filterText)
      if (result !== null)
        addSection("Rechner", "row", 1, [{ kind: "calc", id: "calc", name: "= " + result, detail: "Enter kopiert das Ergebnis", icon: "", glyph: "󰃬", value: result }])
      addSection("Apps", "tile", root.columns, apps.slice(0, 24))
      var q = root.filterText.toLowerCase()
      var acts = []
      for (var a = 0; a < root.actions.length; a++) {
        var act = root.actions[a]
        if (act.name.toLowerCase().indexOf(q) >= 0 || act.keywords.indexOf(q) >= 0) acts.push(root.actionItem(act))
      }
      addSection("Aktionen", "tile", root.columns, acts)
    } else if (root.view === "all") {
      addSection("Alle Apps · " + root.appCount, "tile", root.columns, apps, [{ label: "‹  Zurück", act: "start" }])
    } else {
      // Favoriten: nur die eigenen (Reihenfolge wie gespeichert).
      // Noch keine? Dann die meistgestarteten, aufgefüllt alphabetisch.
      var pinned = root.pinnedItems(byId)
      var fav = pinned.filter(function(x) { return x.kind === "app" })
      var folders = pinned.filter(function(x) { return x.kind === "folder" })
      var hasAppPins = root.pins.some(function(x) { return typeof x === "string" })
      var used = ({})
      if (!hasAppPins) {
        var counts = root.stats.count || {}
        var ranked = apps.filter(function(x) { return (counts[x.id] || 0) > 0 })
        ranked.sort(function(x, y) { return (counts[y.id] || 0) - (counts[x.id] || 0) })
        for (var r = 0; r < ranked.length && fav.length < root.columns * 2; r++) { fav.push(ranked[r]); used[ranked[r].id] = true }
        for (var f = 0; f < apps.length && fav.length < root.columns * 2; f++)
          if (!used[apps[f].id]) { fav.push(apps[f]); used[apps[f].id] = true }
      }
      addSection("Favoriten", "tile", root.columns, fav,
                 [{ label: "✎  Bearbeiten", act: "edit" }, { label: "Alle Apps  ›", act: "all" }])
      if (hasAppPins && secs.length > 0) secs[secs.length - 1].reorder = "pins"
      // Ordner ganz unten (dort war früher "Zuletzt")
      addSection("Ordner", "tile", root.columns, folders, [{ label: "+  Ordner", act: "newFolder" }])
      if (folders.length > 0) secs[secs.length - 1].reorder = "pins"
    }

    root.items = out
    root.sections = secs
    if (root.selectedIndex >= out.length) root.selectedIndex = Math.max(0, out.length - 1)
    if (root.selectedIndex > 0) Qt.callLater(root.ensureVisible)
  }

  function setView(v) {
    root.renaming = false
    root.view = v
    root.filterText = ""
    root.selectedIndex = 0
    root.rebuild()
    flick.contentY = 0
    root.openSerial++
  }

  function pillAction(act) {
    if (act === "newFolder") {
      var next = root.clonePins()
      next.push({ folder: "Neuer Ordner", apps: [] })
      root.currentFolder = next.length - 1
      root.savePins(next)
      root.setView("folderEdit")
      root.renaming = true
      root.renameText = ""
      root.showToast("Namen tippen, Enter = fertig")
    } else if (act === "rename") {
      var f = root.folderAt(root.currentFolder)
      root.renaming = true
      root.renameText = f ? String(f.folder || "") : ""
      root.showToast("Namen tippen, Enter = fertig")
    } else if (act === "deleteFolder") {
      if (root.confirmAction !== "deleteFolder") {
        root.confirmAction = "deleteFolder"
        confirmTimer.restart()
        root.showToast("Nochmal auf Löschen klicken (Apps bleiben installiert)")
        return
      }
      root.confirmAction = ""
      var del = root.clonePins()
      var gone = del.splice(root.currentFolder, 1)[0]
      root.currentFolder = -1
      root.savePins(del)
      root.setView("edit")
      root.showToast("Ordner „" + ((gone && gone.folder) || "") + "“ gelöscht")
    } else {
      root.setView(act)
    }
  }

  function finishRename(save) {
    if (save) {
      var next = root.clonePins()
      var f = next[root.currentFolder]
      var name = root.renameText.trim()
      if (root.isFolder(f) && name) { f.folder = name; root.savePins(next) }
    }
    root.renaming = false
    root.rebuild()
  }

  // ------------------------------------------------------- Ziehen & Ablegen
  // Kachel festhalten und ziehen = verschieben. Mitten auf einen Ordner
  // fallen lassen = App kommt in den Ordner.
  property int dragIndex: -1
  property int dropIndex: -1
  property bool dropInto: false
  property point dragPos: Qt.point(0, 0)   // in cardHolder-Koordinaten
  property var tileMap: ({})               // flatIndex -> Kachel

  function canDrag(index) {
    if (root.filterText) return false
    var s = root.sections[root.sectionOf(index)]
    var it = root.items[index]
    return !!s && !!s.reorder && !!it && (it.kind === "app" || it.kind === "folder")
  }

  function startDrag(index) {
    root.dragIndex = index
    root.dropIndex = -1
    root.dropInto = false
    root.selectedIndex = index
  }

  function updateDrag(cx, cy) {
    var s = root.sections[root.sectionOf(root.dragIndex)]
    if (!s) return
    var hit = -1, into = false
    var draggingApp = root.items[root.dragIndex].kind === "app"
    for (var si = 0; si < root.sections.length && hit < 0; si++) {
      var sec = root.sections[si]
      var same = sec === s
      // andere Bereiche nur als Ziel für "App in Ordner"
      if (!same && !(draggingApp && s.reorder === "pins" && sec.reorder === "pins")) continue
      for (var i = sec.start; i < sec.start + sec.count; i++) {
        var t = root.tileMap[i]
        if (!t) continue
        var p = t.mapToItem(content, 0, 0)
        if (cx >= p.x && cx < p.x + t.width && cy >= p.y && cy < p.y + t.height) {
          var isFolder = root.items[i].kind === "folder"
          var lx = (cx - p.x) / t.width
          if (!same && !isFolder) break
          hit = i
          into = isFolder && draggingApp && s.reorder === "pins" && (!same || (lx > 0.22 && lx < 0.78))
          break
        }
      }
    }
    root.dropIndex = hit === root.dragIndex ? -1 : hit
    root.dropInto = into && hit !== root.dragIndex
  }

  function cancelDrag() {
    root.dragIndex = -1
    root.dropIndex = -1
    root.dropInto = false
  }

  function finishDrag() {
    var from = root.items[root.dragIndex]
    var to = root.items[root.dropIndex]
    var s = root.sections[root.sectionOf(root.dragIndex)]
    var into = root.dropInto
    var target = root.dropIndex
    root.cancelDrag()
    if (!from || !to || !s) return
    var next = root.clonePins()
    if (s.reorder === "pins") {
      var a = from.kind === "folder" ? from.fi : next.indexOf(from.id)
      var b = to.kind === "folder" ? to.fi : next.indexOf(to.id)
      if (a < 0 || b < 0) return
      if (into && root.isFolder(next[b])) {
        var f = next[b]
        if (f.apps.indexOf(from.id) < 0) f.apps.push(from.id)
        next.splice(a, 1)
        root.showToast(from.name + " → Ordner „" + f.folder + "“")
      } else {
        var moved = next.splice(a, 1)[0]
        next.splice(b, 0, moved)
      }
      root.currentFolder = -1
    } else if (s.reorder === "folder") {
      var fold = next[root.currentFolder]
      if (!root.isFolder(fold)) return
      var fa = fold.apps.indexOf(from.id), fb = fold.apps.indexOf(to.id)
      if (fa < 0 || fb < 0) return
      var m = fold.apps.splice(fa, 1)[0]
      fold.apps.splice(fb, 0, m)
    } else return
    root.savePins(next)
    root.setSelected(into ? Math.min(target, root.items.length - 1) : target)
  }

  // ------------------------------------------------------------ Navigation
  function sectionOf(index) {
    for (var i = 0; i < root.sections.length; i++) {
      var s = root.sections[i]
      if (index >= s.start && index < s.start + s.count) return i
    }
    return -1
  }

  function setSelected(index) {
    if (root.items.length === 0) return
    root.selectedIndex = Math.max(0, Math.min(root.items.length - 1, index))
    Qt.callLater(root.ensureVisible)
  }

  // Hover wählt nur nach echter Mausbewegung aus (Scrollen unter ruhender
  // Maus soll die Tastatur-Auswahl nicht klauen).
  property var lastMouse: null
  function mouseMoved(item, mouse) {
    var g = item.mapToGlobal(mouse.x, mouse.y)
    var moved = root.lastMouse !== null && (Math.abs(g.x - root.lastMouse.x) > 2 || Math.abs(g.y - root.lastMouse.y) > 2)
    root.lastMouse = { x: g.x, y: g.y }
    return moved
  }

  function findDelegate(item, index) {
    var kids = item.children
    for (var i = 0; i < kids.length; i++) {
      var c = kids[i]
      if (c.flatIndex === index && c.item !== undefined) return c
      var found = root.findDelegate(c, index)
      if (found) return found
    }
    return null
  }

  function ensureVisible() {
    var d = root.findDelegate(content, root.selectedIndex)
    if (!d) return
    var p = d.mapToItem(flick.contentItem, 0, 0)
    var margin = root.px(34)
    if (p.y - margin < flick.contentY) flick.contentY = Math.max(0, p.y - margin)
    else if (p.y + d.height > flick.contentY + flick.height)
      flick.contentY = Math.min(flick.contentHeight - flick.height, p.y + d.height - flick.height + root.px(10))
  }

  function moveVertical(dir) {
    var si = root.sectionOf(root.selectedIndex)
    if (si < 0) return root.setSelected(0)
    var s = root.sections[si]
    var local = root.selectedIndex - s.start
    var col = local % s.cols
    var target = local + dir * s.cols
    if (target >= 0 && target < s.count) return root.setSelected(s.start + target)
    if (dir > 0 && Math.floor(local / s.cols) < Math.floor((s.count - 1) / s.cols))
      return root.setSelected(s.start + s.count - 1)

    var ni = si + dir
    if (ni < 0 || ni >= root.sections.length) return
    var n = root.sections[ni]
    // Spalte ungefähr mitnehmen (6er-Raster <-> 2er-Liste)
    var frac = (col + 0.5) / s.cols
    var ncol = Math.min(n.cols - 1, Math.floor(frac * n.cols))
    if (dir > 0) {
      root.setSelected(n.start + Math.min(ncol, n.count - 1))
    } else {
      var lastRow = Math.floor((n.count - 1) / n.cols) * n.cols
      root.setSelected(n.start + Math.min(lastRow + ncol, n.count - 1))
    }
  }

  function setFilter(text) {
    root.filterText = text
    root.selectedIndex = 0
    root.rebuild()
    flick.contentY = 0
  }

  // --------------------------------------------------------------- Starten
  function remember(id) {
    var s = root.stats || {}
    var recent = (s.recent || []).filter(function(x) { return x !== id })
    recent.unshift(id)
    var count = s.count || {}
    count[id] = (count[id] || 0) + 1
    root.stats = { recent: recent.slice(0, 20), count: count }
    writeJson(root.statsPath, root.stats)
  }

  function writeJson(path, value) {
    Quickshell.execDetached(["bash", "-c", "mkdir -p \"$(dirname \"$1\")\" && printf '%s' \"$2\" > \"$1\"", "_", path, JSON.stringify(value)])
  }

  property string confirmAction: ""
  Timer { id: confirmTimer; interval: 3000; onTriggered: root.confirmAction = "" }

  function runAction(action, needsConfirm) {
    if (needsConfirm && root.confirmAction !== action) {
      root.confirmAction = action
      confirmTimer.restart()
      root.showToast("Nochmal klicken zum Bestätigen")
      return
    }
    root.confirmAction = ""
    root.dismiss()
    Util.execDetached(action)
  }

  function activate(index) {
    var item = root.items[index]
    if (!item) return
    if (item.kind === "folder") {
      root.currentFolder = item.fi
      root.setView(root.view === "edit" ? "folderEdit" : "folder")
    } else if (item.kind === "app" && (root.view === "edit" || root.view === "folderEdit")) {
      root.togglePin(item)
    } else if (item.kind === "app") {
      root.dismiss()
      root.remember(item.id)
      Quickshell.execDetached(["uwsm-app", "--", "gtk-launch", item.id + ".desktop"])
    } else if (item.kind === "action") {
      root.runAction(item.action, item.confirm)
    } else if (item.kind === "calc") {
      root.dismiss()
      Quickshell.execDetached(["wl-copy", item.value])
    }
  }

  function togglePin(item) {
    if (!item || item.kind !== "app") return
    var next = root.clonePins()
    if (root.view === "folderEdit") {
      var f = next[root.currentFolder]
      if (!root.isFolder(f)) return
      var fat = f.apps.indexOf(item.id)
      if (fat >= 0) { f.apps.splice(fat, 1); root.showToast(item.name + " aus „" + f.folder + "“ entfernt") }
      else { f.apps.push(item.id); root.showToast(item.name + " in „" + f.folder + "“") }
      root.savePins(next)
      return
    }
    var at = next.indexOf(item.id)
    if (at >= 0) { next.splice(at, 1); root.showToast(item.name + " aus Favoriten entfernt") }
    else { next.push(item.id); root.showToast(item.name + " zu Favoriten hinzugefügt") }
    root.savePins(next)
  }

  function savePins(next) {
    root.pins = next
    writeJson(root.pinsPath, { pins: next })
    root.rebuild()
  }

  // Im Bearbeiten-Modus: Shift + ←/→ verschiebt den gewählten Favoriten
  function movePin(dir) {
    var item = root.items[root.selectedIndex]
    if (!item || root.filterText) return
    var next = root.clonePins()
    var list, at
    if (root.view === "edit") {
      list = next
      at = item.kind === "folder" ? item.fi : next.indexOf(item.id)
    } else if (root.view === "folderEdit" && root.isFolder(next[root.currentFolder])) {
      list = next[root.currentFolder].apps
      at = list.indexOf(item.id)
    } else return
    // in der Favoriten-Zeile zählt die sichtbare Reihenfolge: nächsten sichtbaren Nachbarn suchen
    var neighbor = root.items[root.selectedIndex + dir]
    var sec = root.sections[root.sectionOf(root.selectedIndex)]
    if (!neighbor || !sec || root.sectionOf(root.selectedIndex + dir) !== root.sectionOf(root.selectedIndex)) return
    var to = root.view === "edit" ? (neighbor.kind === "folder" ? neighbor.fi : list.indexOf(neighbor.id)) : list.indexOf(neighbor.id)
    if (at < 0 || to < 0) return
    var moving = list.splice(at, 1)[0]
    list.splice(to, 0, moving)
    if (root.view === "edit" && root.currentFolder >= 0) root.currentFolder = -1
    root.savePins(next)
    root.setSelected(root.selectedIndex + dir)
  }

  function showToast(text) {
    root.toast = text
    toastTimer.restart()
  }
  Timer { id: toastTimer; interval: 2200; onTriggered: root.toast = "" }

  FileView {
    id: statsFile
    path: root.statsPath
    printErrors: false
    onLoaded: {
      try { root.stats = JSON.parse(text()) } catch (e) { root.stats = { recent: [], count: {} } }
      if (root.opened) root.rebuild()
    }
  }

  FileView {
    id: pinsFile
    path: root.pinsPath
    printErrors: false
    onLoaded: {
      try {
        var parsed = JSON.parse(text())
        root.pins = Array.isArray(parsed.pins) ? parsed.pins : []
      } catch (e) { root.pins = [] }
      root.pinsLoaded = true
      if (root.opened) root.rebuild()
    }
    onLoadFailed: {
      // Erster Start: Favoriten aus dem alten Launcher übernehmen
      if (!root.pinsLoaded) oldSettings.reload()
    }
  }

  FileView {
    id: oldSettings
    path: Quickshell.env("HOME") + "/.config/cillian-launcher/settings.json"
    printErrors: false
    onLoaded: {
      if (root.pinsLoaded || root.pins.length > 0) return
      try {
        var favs = JSON.parse(text()).favorites || []
        if (favs.length > 0) { root.pins = favs; if (root.opened) root.rebuild() }
      } catch (e) {}
    }
  }

  // --------------------------------------------------------- Live-Werte
  property real cpu: 0
  property real ram: 0
  property int battery: -1
  property bool charging: false
  property var cpuPrev: null

  Process {
    id: sysProc
    command: ["bash", "-c", "head -1 /proc/stat; grep -E '^(MemTotal|MemAvailable):' /proc/meminfo; cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -1; cat /sys/class/power_supply/BAT*/status 2>/dev/null | head -1"]
    stdout: StdioCollector {
      onStreamFinished: {
        var lines = text.split("\n")
        var c = (lines[0] || "").trim().split(/\s+/).slice(1).map(Number)
        if (c.length >= 4) {
          var idle = c[3] + (c[4] || 0)
          var total = c.reduce(function(a, b) { return a + b }, 0)
          if (root.cpuPrev) {
            var dt = total - root.cpuPrev.total
            if (dt > 0) root.cpu = Math.max(0, Math.min(1, 1 - (idle - root.cpuPrev.idle) / dt))
          }
          root.cpuPrev = { idle: idle, total: total }
        }
        var memTotal = 0, memAvail = 0
        for (var i = 1; i < lines.length; i++) {
          var m = lines[i].match(/^(MemTotal|MemAvailable):\s+(\d+)/)
          if (m) { if (m[1] === "MemTotal") memTotal = +m[2]; else memAvail = +m[2] }
        }
        if (memTotal > 0) root.ram = 1 - memAvail / memTotal
        var cap = lines.length > 3 ? parseInt(lines[3]) : NaN
        root.battery = isNaN(cap) ? -1 : cap
        root.charging = lines.length > 4 && /Charging|Full/.test(lines[4])
      }
    }
  }

  Timer {
    interval: 1500
    repeat: true
    running: root.opened
    onTriggered: { sysProc.running = false; sysProc.running = true }
  }

  SystemClock { id: clock; precision: SystemClock.Seconds }

  readonly property string greeting: {
    var h = clock.date.getHours()
    var name = String(Quickshell.env("USER") || "")
    name = name.charAt(0).toUpperCase() + name.slice(1)
    var g = h < 5 ? "Gute Nacht" : h < 11 ? "Guten Morgen" : h < 17 ? "Guten Tag" : h < 22 ? "Guten Abend" : "Gute Nacht"
    return g + ", " + name
  }

  // ======================================================== Bausteine

  component Tile: Item {
    id: tile
    required property var item
    required property int flatIndex
    required property int order
    readonly property bool active: flatIndex === root.selectedIndex
    readonly property bool pinned: root.isMarked(item)
    property real rise: 1

    readonly property bool dragging: root.dragIndex === flatIndex
    readonly property bool dropTarget: root.dropIndex === flatIndex

    width: root.cellWidth
    height: root.cellHeight
    opacity: rise * (dragging ? 0.25 : 1)
    transform: Translate { y: (1 - tile.rise) * root.px(16) }

    Component.onCompleted: root.tileMap[flatIndex] = tile
    Component.onDestruction: if (root.tileMap[flatIndex] === tile) delete root.tileMap[flatIndex]

    // Einfüge-Strich links/rechts der Ziel-Kachel
    Rectangle {
      visible: tile.dropTarget && !root.dropInto
      width: root.px(4)
      height: root.px(70)
      radius: width / 2
      y: root.px(10)
      x: root.dragIndex > tile.flatIndex ? -width / 2 : tile.width - width / 2
      color: root.glow
      z: 5
    }

    SequentialAnimation {
      id: riseAnim
      PropertyAction { target: tile; property: "rise"; value: 0 }
      PauseAnimation { duration: Math.min(tile.order, 24) * 14 + 60 }
      NumberAnimation { target: tile; property: "rise"; to: 1; duration: 320; easing.type: Easing.OutCubic }
    }
    Connections {
      target: root
      function onOpenSerialChanged() { riseAnim.restart() }
    }

    Rectangle {
      anchors.fill: parent
      anchors.margins: root.px(4)
      radius: root.px(16)
      color: tile.active ? Util.alpha(root.fg, 0.09) : "transparent"
      border.width: 1
      border.color: tile.active ? Util.alpha(root.fg, 0.16) : "transparent"
      Behavior on color { ColorAnimation { duration: 140 } }
    }

    Item {
      id: iconWrap
      width: root.px(62)
      height: root.px(62)
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: parent.top
      anchors.topMargin: root.px(12)
      scale: tile.dropTarget && root.dropInto ? 1.28 : (tile.active && root.dragIndex < 0 ? 1.1 : 1.0)
      Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 2.2 } }

      RectangularShadow {
        anchors.fill: iconBox
        radius: iconBox.radius
        blur: root.px(22)
        spread: 0
        color: Util.alpha(root.glow, tile.active ? 0.28 : 0.0)
        Behavior on color { ColorAnimation { duration: 200 } }
      }

      Rectangle {
        id: iconBox
        anchors.fill: parent
        radius: root.px(18)
        gradient: Gradient {
          GradientStop { position: 0.0; color: Util.alpha(root.fg, tile.active ? 0.16 : 0.09) }
          GradientStop { position: 1.0; color: Util.alpha(root.fg, tile.active ? 0.07 : 0.03) }
        }
        border.width: 1
        border.color: Util.alpha(root.fg, tile.active ? 0.28 : 0.08)

        Image {
          anchors.centerIn: parent
          visible: tile.item.kind === "app"
          width: root.px(38)
          height: root.px(38)
          sourceSize.width: width * 2
          sourceSize.height: height * 2
          fillMode: Image.PreserveAspectFit
          asynchronous: true
          smooth: true
          source: tile.item.kind === "app" ? root.iconSource(tile.item.icon) : ""
        }

        Grid {
          anchors.centerIn: parent
          visible: tile.item.kind === "folder"
          columns: 2
          spacing: root.px(4)
          Repeater {
            model: tile.item.kind === "folder" ? Math.min(4, tile.item.apps.length) : 0
            Image {
              required property int index
              width: root.px(19)
              height: root.px(19)
              sourceSize.width: width * 2
              sourceSize.height: height * 2
              fillMode: Image.PreserveAspectFit
              asynchronous: true
              smooth: true
              source: root.iconSource(tile.item.apps[index].icon)
            }
          }
        }

        Text {
          anchors.centerIn: parent
          visible: tile.item.kind !== "app" && (tile.item.kind !== "folder" || tile.item.apps.length === 0)
          text: tile.item.glyph
          color: root.confirmAction !== "" && root.confirmAction === tile.item.action ? Commons.Color.urgent : root.fg
          font.family: root.fontFamily
          font.pixelSize: root.fpx(26)
        }
      }

      // Bearbeiten: ✓ = Favorit (Klick entfernt), + = hinzufügen
      Rectangle {
        visible: (root.view === "edit" || root.view === "folderEdit") && tile.item.kind === "app"
        width: root.px(22); height: width; radius: width / 2
        anchors.right: parent.right; anchors.top: parent.top
        anchors.margins: -root.px(6)
        color: tile.pinned ? root.glow : Util.alpha(root.bg, 0.9)
        border.width: 1
        border.color: Util.alpha(root.fg, tile.pinned ? 0 : 0.5)
        Text {
          anchors.centerIn: parent
          text: tile.pinned ? (tile.active ? "✕" : "✓") : "+"
          color: tile.pinned ? root.bg : root.fg
          font.family: root.fontFamily
          font.pixelSize: root.fpx(13)
          font.weight: Font.Bold
        }
      }
      // kleiner Punkt = Favorit (in Suche und Alle Apps)
      Rectangle {
        visible: tile.pinned && root.view !== "edit" && (root.view === "all" || root.filterText !== "")
        width: root.px(8); height: width; radius: width / 2
        anchors.right: parent.right; anchors.top: parent.top
        anchors.margins: -root.px(2)
        color: root.glow
      }
    }

    Text {
      anchors.top: iconWrap.bottom
      anchors.topMargin: root.px(12)
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: root.px(8)
      anchors.rightMargin: root.px(8)
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: tile.item.name
      color: root.fg
      opacity: tile.active ? 1 : 0.78
      font.family: root.fontFamily
      font.pixelSize: root.fpx(13)
      font.weight: tile.active ? Font.DemiBold : Font.Normal
      elide: Text.ElideRight
    }

    MouseArea {
      id: tileMouse
      property real pressX: 0
      property real pressY: 0
      property bool dragged: false
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      preventStealing: root.canDrag(tile.flatIndex)
      cursorShape: dragged ? Qt.ClosedHandCursor : Qt.PointingHandCursor
      onPressed: function(mouse) { pressX = mouse.x; pressY = mouse.y; dragged = false }
      onPositionChanged: function(mouse) {
        if (pressed && (mouse.buttons & Qt.LeftButton) && root.canDrag(tile.flatIndex)) {
          if (!dragged && Math.hypot(mouse.x - pressX, mouse.y - pressY) > root.px(10)) {
            dragged = true
            root.startDrag(tile.flatIndex)
          }
          if (dragged) {
            var c = mapToItem(content, mouse.x, mouse.y)
            root.updateDrag(c.x, c.y)
            var h = mapToItem(cardHolder, mouse.x, mouse.y)
            root.dragPos = Qt.point(h.x, h.y)
            return
          }
        }
        if (root.mouseMoved(this, mouse)) root.selectedIndex = tile.flatIndex
      }
      onReleased: if (dragged) Qt.callLater(root.finishDrag)
      onCanceled: if (dragged) { dragged = false; root.cancelDrag() }
      onClicked: function(mouse) {
        if (dragged) { dragged = false; return }
        if (mouse.button === Qt.RightButton) root.togglePin(tile.item)
        else root.activate(tile.flatIndex)
      }
    }
  }

  component RowItem: Item {
    id: row
    required property var item
    required property int flatIndex
    required property int order
    required property int cols
    readonly property bool active: flatIndex === root.selectedIndex
    property real rise: 1

    width: Math.floor(root.innerWidth / cols)
    height: root.rowHeight
    opacity: rise
    transform: Translate { y: (1 - row.rise) * root.px(12) }

    SequentialAnimation {
      id: rowAnim
      PropertyAction { target: row; property: "rise"; value: 0 }
      PauseAnimation { duration: 200 + row.order * 30 }
      NumberAnimation { target: row; property: "rise"; to: 1; duration: 300; easing.type: Easing.OutCubic }
    }
    Connections {
      target: root
      function onOpenSerialChanged() { rowAnim.restart() }
    }

    Rectangle {
      anchors.fill: parent
      anchors.margins: root.px(3)
      radius: root.px(14)
      color: row.active ? Util.alpha(root.fg, 0.09) : "transparent"
      border.width: 1
      border.color: row.active ? Util.alpha(root.fg, 0.16) : "transparent"
      Behavior on color { ColorAnimation { duration: 140 } }
    }

    Rectangle {
      id: rowIcon
      width: root.px(40)
      height: root.px(40)
      radius: root.px(12)
      anchors.left: parent.left
      anchors.leftMargin: root.px(12)
      anchors.verticalCenter: parent.verticalCenter
      color: Util.alpha(root.fg, 0.07)

      Image {
        anchors.centerIn: parent
        visible: row.item.kind === "app"
        width: root.px(26)
        height: root.px(26)
        sourceSize.width: width * 2
        sourceSize.height: height * 2
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        source: row.item.kind === "app" ? root.iconSource(row.item.icon) : ""
      }

      Text {
        anchors.centerIn: parent
        visible: row.item.kind !== "app"
        text: row.item.glyph
        color: root.fg
        font.family: root.fontFamily
        font.pixelSize: root.fpx(20)
      }
    }

    Column {
      anchors.left: rowIcon.right
      anchors.leftMargin: root.px(14)
      anchors.right: parent.right
      anchors.rightMargin: root.px(12)
      anchors.verticalCenter: parent.verticalCenter
      spacing: root.px(2)

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: row.item.name
        color: root.fg
        font.family: root.fontFamily
        font.pixelSize: root.fpx(row.item.kind === "calc" ? 20 : 14)
        font.weight: Font.Medium
        elide: Text.ElideRight
      }
      Text {
        width: parent.width
        visible: text !== ""
        textFormat: Text.PlainText
        text: row.item.detail
        color: root.fg
        opacity: 0.5
        font.family: root.fontFamily
        font.pixelSize: root.fpx(12)
        elide: Text.ElideRight
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      cursorShape: Qt.PointingHandCursor
      onPositionChanged: function(mouse) { if (root.mouseMoved(this, mouse)) root.selectedIndex = row.flatIndex }
      onClicked: function(mouse) {
        if (mouse.button === Qt.RightButton) root.togglePin(row.item)
        else root.activate(row.flatIndex)
      }
    }
  }

  // Live-Wert mit kleinem Balken
  component Stat: Item {
    id: stat
    property string glyph
    property string label
    property real value: 0
    property string valueText: Math.round(value * 100) + "%"
    width: root.px(150)
    height: root.px(26)

    Text {
      id: statGlyph
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: stat.glyph
      color: root.fg
      opacity: 0.8
      font.family: root.fontFamily
      font.pixelSize: root.fpx(15)
    }
    Text {
      anchors.left: statGlyph.right
      anchors.leftMargin: root.px(8)
      anchors.verticalCenter: parent.verticalCenter
      text: stat.label
      color: root.fg
      opacity: 0.55
      font.family: root.fontFamily
      font.pixelSize: root.fpx(12)
    }
    Text {
      id: statValue
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: stat.valueText
      color: root.fg
      font.family: root.fontFamily
      font.pixelSize: root.fpx(12)
      font.weight: Font.DemiBold
    }
    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: root.px(3)
      radius: height / 2
      color: Util.alpha(root.fg, 0.1)
      Rectangle {
        height: parent.height
        radius: parent.radius
        width: parent.width * Math.max(0.02, Math.min(1, stat.value))
        color: root.fg
        opacity: 0.85
        Behavior on width { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
      }
    }
  }

  component PowerButton: Item {
    id: pb
    property string glyph
    property string tip
    property string action
    property bool confirm: false
    readonly property bool armed: root.confirmAction === action
    width: root.px(42)
    height: root.px(42)

    Rectangle {
      anchors.fill: parent
      radius: width / 2
      color: pb.armed ? Util.alpha(Commons.Color.urgent, 0.35) : (pbMouse.containsMouse ? Util.alpha(root.fg, 0.14) : Util.alpha(root.fg, 0.05))
      border.width: 1
      border.color: pbMouse.containsMouse || pb.armed ? Util.alpha(root.fg, 0.35) : Util.alpha(root.fg, 0.08)
      scale: pbMouse.pressed ? 0.9 : (pbMouse.containsMouse ? 1.08 : 1)
      Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
      Behavior on color { ColorAnimation { duration: 140 } }

      Text {
        anchors.centerIn: parent
        text: pb.glyph
        color: root.fg
        font.family: root.fontFamily
        font.pixelSize: root.fpx(18)
      }
    }

    // Tooltip über dem Knopf
    Rectangle {
      visible: pbMouse.containsMouse
      anchors.bottom: parent.top
      anchors.bottomMargin: root.px(8)
      anchors.horizontalCenter: parent.horizontalCenter
      width: tipText.implicitWidth + root.px(16)
      height: tipText.implicitHeight + root.px(8)
      radius: root.px(8)
      color: Util.alpha(root.bg, 0.95)
      border.width: 1
      border.color: Util.alpha(root.fg, 0.2)
      Text {
        id: tipText
        anchors.centerIn: parent
        text: pb.armed ? "Nochmal = " + pb.tip : pb.tip
        color: root.fg
        font.family: root.fontFamily
        font.pixelSize: root.fpx(12)
      }
    }

    MouseArea {
      id: pbMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.runAction(pb.action, pb.confirm)
    }
  }

  // ========================================================== Fenster
  PanelWindow {
    id: panel
    visible: root.opened || root.reveal > 0.01
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "cillian-start"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    // Abdunkeln (Hyprland macht dahinter Unschärfe, siehe layer_rule cillian-start)
    Rectangle {
      anchors.fill: parent
      color: Util.alpha(root.scrimColor, 0.22)
      opacity: root.reveal
    }

    MouseArea {
      anchors.fill: parent
      enabled: root.opened
      onClicked: root.dismiss()
    }

    Item {
      id: cardHolder
      width: root.cardWidth
      height: root.cardHeight
      Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
      anchors.centerIn: parent
      opacity: root.reveal
      scale: 0.93 + 0.07 * root.reveal
      transform: Translate { y: (1 - root.reveal) * root.px(36) }

      // weicher Lichtschein + Schatten NUR aussen um die Karte: unter dem Glas
      // ausgeschnitten, sonst sieht man durchs Glas nur den schwarzen Schatten
      Item {
        id: shadowBox
        anchors.fill: card
        anchors.margins: -root.px(150)
        layer.enabled: true
        layer.effect: MultiEffect {
          maskEnabled: true
          maskInverted: true
          maskSource: shadowCut
        }
        RectangularShadow {
          anchors.fill: parent
          anchors.margins: root.px(150)
          radius: card.radius
          blur: root.px(70)
          spread: root.px(2)
          color: Util.alpha(root.glow, 0.10)
        }
        RectangularShadow {
          anchors.fill: parent
          anchors.margins: root.px(150)
          anchors.topMargin: root.px(150) + root.px(18)
          radius: card.radius
          blur: root.px(50)
          color: Qt.rgba(0, 0, 0, 0.7)
        }
      }
      Item {
        id: shadowCut
        anchors.fill: shadowBox
        visible: false
        layer.enabled: true
        Rectangle {
          anchors.fill: parent
          anchors.margins: root.px(150)
          radius: card.radius
          color: "black"
        }
      }

      Rectangle {
        id: card
        anchors.fill: parent
        radius: root.px(28)
        // Glas-Stil Option A (wie shell.toml): Graphit 0.70, Rand 0.14, Glanz 0.06
        color: Util.alpha(root.bg, 0.70)
        border.width: 1
        border.color: Util.alpha(root.fg, 0.14)
        clip: true

        // leichter Glanz oben
        Rectangle {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          height: root.px(220)
          radius: card.radius
          gradient: Gradient {
            GradientStop { position: 0.0; color: Util.alpha(root.fg, 0.06) }
            GradientStop { position: 1.0; color: "transparent" }
          }
        }

        MouseArea { anchors.fill: parent; onClicked: {} }

        Item {
          id: keyCatcher
          anchors.fill: parent
          focus: true

          Keys.priority: Keys.BeforeItem
          Keys.onPressed: function(event) {
            var k = event.key
            if (root.renaming) {
              if (k === Qt.Key_Return || k === Qt.Key_Enter) root.finishRename(true)
              else if (k === Qt.Key_Escape) root.finishRename(false)
              else if (k === Qt.Key_Backspace) root.renameText = root.renameText.slice(0, -1)
              else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && root.renameText.length < 30)
                root.renameText += event.text
              event.accepted = true
              return
            }
            if (k === Qt.Key_Escape) {
              if (root.filterText) root.setFilter("")
              else if (root.view === "folderEdit") root.setView("folder")
              else if (root.view !== "start") root.setView("start")
              else root.dismiss()
            } else if (k === Qt.Key_Tab || k === Qt.Key_Backtab) {
              root.setView(root.view !== "start" || root.filterText ? "start" : "all")
            } else if ((k === Qt.Key_Left || k === Qt.Key_Right) && (event.modifiers & Qt.ShiftModifier) && (root.view === "edit" || root.view === "folderEdit")) {
              root.movePin(k === Qt.Key_Left ? -1 : 1)
            } else if (k === Qt.Key_P && (event.modifiers & Qt.ControlModifier)) {
              root.togglePin(root.items[root.selectedIndex])
            } else if (Util.editsFilter(event, root.filterText)) {
              root.setFilter(Util.editedFilter(event, root.filterText))
            } else if (k === Qt.Key_Left) {
              root.setSelected(root.selectedIndex - 1)
            } else if (k === Qt.Key_Right) {
              root.setSelected(root.selectedIndex + 1)
            } else if (k === Qt.Key_Up) {
              root.moveVertical(-1)
            } else if (k === Qt.Key_Down) {
              root.moveVertical(1)
            } else if (k === Qt.Key_Return || k === Qt.Key_Enter) {
              root.activate(root.selectedIndex)
            } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127
                       && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
              root.setFilter(root.filterText + event.text)
            } else {
              return
            }
            event.accepted = true
          }
        }

        // ------------------------------------------------ Kopf: Uhr + Werte
        Item {
          id: header
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.topMargin: root.px(26)
          anchors.leftMargin: root.pad + root.px(6)
          anchors.rightMargin: root.pad + root.px(6)
          height: root.px(104)

          Text {
            id: clockText
            anchors.left: parent.left
            anchors.top: parent.top
            text: Qt.formatDateTime(clock.date, "HH:mm")
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: root.fpx(60)
            font.weight: Font.Light
            font.letterSpacing: root.px(1)
          }
          Text {
            anchors.left: clockText.right
            anchors.leftMargin: root.px(6)
            anchors.baseline: clockText.baseline
            text: Qt.formatDateTime(clock.date, "ss")
            color: root.fg
            opacity: 0.4
            font.family: root.fontFamily
            font.pixelSize: root.fpx(20)
          }
          Text {
            id: dateText
            anchors.left: parent.left
            anchors.top: clockText.bottom
            anchors.topMargin: root.px(2)
            text: clock.date.toLocaleDateString(Qt.locale("de_CH"), "dddd, d. MMMM yyyy")
            color: root.fg
            opacity: 0.6
            font.family: root.fontFamily
            font.pixelSize: root.fpx(14)
          }
          Text {
            anchors.left: dateText.right
            anchors.leftMargin: root.px(12)
            anchors.baseline: dateText.baseline
            text: "·  " + root.greeting
            color: root.fg
            opacity: 0.85
            font.family: root.fontFamily
            font.pixelSize: root.fpx(14)
            font.weight: Font.Medium
          }

          Column {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: root.px(8)
            Stat { glyph: "󰍛"; label: "CPU"; value: root.cpu }
            Stat { glyph: "󰘚"; label: "RAM"; value: root.ram }
            Stat {
              visible: root.battery >= 0
              glyph: root.charging ? "󰂄" : (root.battery > 60 ? "󰁹" : root.battery > 25 ? "󰁾" : "󰁻")
              label: root.charging ? "Akku lädt" : "Akku"
              value: root.battery / 100
              valueText: root.battery + "%"
            }
          }
        }

        // --------------------------------------------------------- Suche
        Rectangle {
          id: search
          anchors.top: header.bottom
          anchors.topMargin: root.px(18)
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.leftMargin: root.pad
          anchors.rightMargin: root.pad
          height: root.px(54)
          radius: height / 2
          color: Util.alpha(root.fg, root.filterText ? 0.09 : 0.06)
          border.width: 1
          border.color: Util.alpha(root.fg, root.filterText ? 0.38 : 0.12)
          Behavior on border.color { ColorAnimation { duration: 200 } }
          Behavior on color { ColorAnimation { duration: 200 } }

          RectangularShadow {
            anchors.fill: parent
            z: -1
            radius: parent.radius
            blur: root.px(26)
            color: Util.alpha(root.glow, root.filterText ? 0.16 : 0)
            Behavior on color { ColorAnimation { duration: 250 } }
          }

          Text {
            id: searchGlyph
            anchors.left: parent.left
            anchors.leftMargin: root.px(22)
            anchors.verticalCenter: parent.verticalCenter
            text: "󰍉"
            color: root.fg
            opacity: 0.75
            font.family: root.fontFamily
            font.pixelSize: root.fpx(20)
          }
          Text {
            id: queryText
            anchors.left: searchGlyph.right
            anchors.leftMargin: root.px(14)
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.filterText
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: root.fpx(18)
          }
          Rectangle {
            id: caret
            anchors.left: queryText.right
            anchors.leftMargin: root.px(2)
            anchors.verticalCenter: parent.verticalCenter
            width: root.px(2)
            height: root.px(22)
            radius: 1
            color: root.fg
            SequentialAnimation on opacity {
              running: root.opened
              loops: Animation.Infinite
              NumberAnimation { to: 0; duration: 520; easing.type: Easing.InOutQuad }
              NumberAnimation { to: 1; duration: 520; easing.type: Easing.InOutQuad }
            }
          }
          Text {
            anchors.left: caret.right
            anchors.leftMargin: root.px(6)
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.filterText
            text: "Tippen zum Suchen – Apps, Aktionen, Rechnen (z.B. 12*7)"
            color: root.fg
            opacity: 0.4
            font.family: root.fontFamily
            font.pixelSize: root.fpx(16)
          }
        }

        // ------------------------------------------------------- Inhalt
        Flickable {
          id: flick
          anchors.top: search.bottom
          anchors.topMargin: root.px(10)
          anchors.bottom: footer.top
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.leftMargin: root.pad
          anchors.rightMargin: root.pad
          contentHeight: content.height + root.px(14)
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          interactive: root.dragIndex < 0
          Behavior on contentY { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

          Column {
            id: content
            width: flick.width
            topPadding: root.px(8)

            Repeater {
              model: root.sections

              Column {
                id: sectionCol
                required property var modelData
                width: content.width

                Item {
                  width: parent.width
                  height: root.px(38)

                  Text {
                    anchors.left: parent.left
                    anchors.leftMargin: root.px(10)
                    anchors.verticalCenter: parent.verticalCenter
                    text: sectionCol.modelData.rename && root.renaming ? "󰉋  Name: " + root.renameText + "▏" : sectionCol.modelData.title
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: root.fpx(15)
                    font.weight: Font.DemiBold
                  }

                  // Knöpfe rechts: Bearbeiten / Alle Apps / Zurück / Fertig
                  Row {
                    anchors.right: parent.right
                    anchors.rightMargin: root.px(8)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: root.px(8)
                    Repeater {
                      model: sectionCol.modelData.buttons || []
                      Rectangle {
                        id: pill
                        required property var modelData
                        width: pillText.implicitWidth + root.px(24)
                        height: root.px(28)
                        radius: height / 2
                        color: pillMouse.containsMouse ? Util.alpha(root.fg, 0.16) : Util.alpha(root.fg, 0.06)
                        border.width: 1
                        border.color: Util.alpha(root.fg, pillMouse.containsMouse ? 0.3 : 0.1)
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Text {
                          id: pillText
                          anchors.centerIn: parent
                          text: pill.modelData.label
                          color: root.fg
                          opacity: 0.9
                          font.family: root.fontFamily
                          font.pixelSize: root.fpx(12)
                        }
                        MouseArea {
                          id: pillMouse
                          anchors.fill: parent
                          hoverEnabled: true
                          cursorShape: Qt.PointingHandCursor
                          onClicked: root.pillAction(pill.modelData.act)
                        }
                      }
                    }
                  }
                }

                Text {
                  visible: sectionCol.modelData.count === 0
                  leftPadding: root.px(10)
                  bottomPadding: root.px(10)
                  text: sectionCol.modelData.empty || "Noch keine – unten Apps antippen"
                  color: root.fg
                  opacity: 0.45
                  font.family: root.fontFamily
                  font.pixelSize: root.fpx(13)
                }

                Grid {
                  columns: sectionCol.modelData.cols
                  Repeater {
                    model: sectionCol.modelData.style === "tile" ? sectionCol.modelData.count : 0
                    Tile {
                      required property int index
                      order: index
                      flatIndex: sectionCol.modelData.start + index
                      item: root.items[flatIndex] || root.emptyItem
                    }
                  }
                  Repeater {
                    model: sectionCol.modelData.style === "row" ? sectionCol.modelData.count : 0
                    RowItem {
                      required property int index
                      order: index
                      cols: sectionCol.modelData.cols
                      flatIndex: sectionCol.modelData.start + index
                      item: root.items[flatIndex] || root.emptyItem
                    }
                  }
                }

                Item { width: 1; height: root.px(8) }
              }
            }

            Text {
              visible: root.items.length === 0 && root.filterText !== ""
              width: content.width
              topPadding: root.px(70)
              horizontalAlignment: Text.AlignHCenter
              textFormat: Text.PlainText
              text: "Nichts gefunden für „" + root.filterText + "“"
              color: root.fg
              opacity: 0.6
              font.family: root.fontFamily
              font.pixelSize: root.fpx(16)
            }
          }
        }

        // -------------------------------------------- Fuss: Profil + Ein/Aus
        Rectangle {
          id: footer
          anchors.bottom: parent.bottom
          anchors.left: parent.left
          anchors.right: parent.right
          height: root.px(76)
          color: Util.alpha(root.fg, 0.035)

          Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: Util.alpha(root.fg, 0.08)
          }

          Rectangle {
            id: avatar
            anchors.left: parent.left
            anchors.leftMargin: root.pad + root.px(4)
            anchors.verticalCenter: parent.verticalCenter
            width: root.px(40)
            height: width
            radius: width / 2
            gradient: Gradient {
              GradientStop { position: 0.0; color: Util.alpha(root.fg, 0.9) }
              GradientStop { position: 1.0; color: Util.alpha(root.fg, 0.45) }
            }
            Text {
              anchors.centerIn: parent
              text: String(Quickshell.env("USER") || "?").charAt(0).toUpperCase()
              color: root.bg
              font.family: root.fontFamily
              font.pixelSize: root.fpx(18)
              font.weight: Font.Bold
            }
          }

          Column {
            anchors.left: avatar.right
            anchors.leftMargin: root.px(12)
            anchors.verticalCenter: parent.verticalCenter
            spacing: root.px(1)
            Text {
              text: String(Quickshell.env("USER") || "")
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: root.fpx(14)
              font.weight: Font.DemiBold
            }
            Text {
              text: root.toast !== "" ? root.toast
                  : root.dragIndex >= 0 ? (root.dropInto ? "Loslassen = in den Ordner" : "Loslassen = hier hinstellen")
                  : root.view === "edit" ? "Klick = Favorit an/aus   Ziehen = verschieben   Esc fertig"
                  : root.view === "folder" || root.view === "folderEdit" ? "Ziehen = verschieben   Esc zurück"
                  : "Ziehen = verschieben (auf Ordner = hinein)   Rechtsklick = Favorit   Esc zu"
              color: root.fg
              opacity: root.toast !== "" ? 0.9 : 0.45
              font.family: root.fontFamily
              font.pixelSize: root.fpx(11)
            }
          }

          Row {
            anchors.right: parent.right
            anchors.rightMargin: root.pad
            anchors.verticalCenter: parent.verticalCenter
            spacing: root.px(10)
            PowerButton { glyph: "󰣇"; tip: "Omarchy-Menü"; action: "omarchy-menu toggle root" }
            PowerButton { glyph: "󰌾"; tip: "Sperren"; action: "omarchy-system-lock" }
            PowerButton { glyph: "󰜉"; tip: "Neustart"; action: "omarchy-system-reboot"; confirm: true }
            PowerButton { glyph: "󰐥"; tip: "Ausschalten"; action: "omarchy-system-shutdown"; confirm: true }
          }
        }
      }

      // Umlaufendes Licht auf dem Rand (zwei Lichtpunkte drehen langsam)
      Item {
        id: ring
        anchors.fill: card
        layer.enabled: root.opened || root.reveal > 0
        layer.effect: MultiEffect {
          maskEnabled: true
          maskSource: ringMask
        }

        Rectangle {
          width: Math.hypot(card.width, card.height) * 1.05
          height: width
          anchors.centerIn: parent
          RotationAnimation on rotation {
            running: root.opened
            from: 0; to: 360
            duration: 9000
            loops: Animation.Infinite
          }
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.44; color: "transparent" }
            GradientStop { position: 0.5; color: Util.alpha(root.glow, 0.95) }
            GradientStop { position: 0.56; color: "transparent" }
            GradientStop { position: 1.0; color: "transparent" }
          }
        }
      }

      // gezogene Kachel klebt an der Maus
      Item {
        id: ghost
        readonly property var it: root.dragIndex >= 0 ? (root.items[root.dragIndex] || root.emptyItem) : root.emptyItem
        visible: root.dragIndex >= 0
        z: 100
        width: root.px(66)
        height: width
        x: root.dragPos.x - width / 2
        y: root.dragPos.y - height / 2
        rotation: -4
        RectangularShadow {
          anchors.fill: ghostBox
          radius: ghostBox.radius
          blur: root.px(26)
          color: Util.alpha(root.glow, 0.3)
        }
        Rectangle {
          id: ghostBox
          anchors.fill: parent
          radius: root.px(18)
          color: Util.alpha(root.bg, 0.92)
          border.width: 1
          border.color: Util.alpha(root.fg, 0.4)
          Image {
            anchors.centerIn: parent
            visible: ghost.it.kind === "app"
            width: root.px(40); height: width
            sourceSize.width: width * 2; sourceSize.height: height * 2
            fillMode: Image.PreserveAspectFit
            source: ghost.it.kind === "app" ? root.iconSource(ghost.it.icon) : ""
          }
          Text {
            anchors.centerIn: parent
            visible: ghost.it.kind === "folder"
            text: "󰉋"
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: root.fpx(28)
          }
        }
      }

      Item {
        id: ringMask
        anchors.fill: card
        visible: false
        layer.enabled: true
        Rectangle {
          anchors.fill: parent
          radius: card.radius
          color: "transparent"
          border.width: Math.max(1.5, root.px(1.6))
          border.color: "black"
        }
      }
    }
  }
}
