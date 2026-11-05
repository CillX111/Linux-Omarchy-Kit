import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Kalender-Zeichen in der Leiste (Hilfsprogramm: ~/.local/bin/kalender-foto).
// Am Morgen macht man einen Screenshot vom Kalender, Claude liest alle
// sichtbaren Tage daraus (~/Pictures/Kalender/termine.json). Ein Klick aufs
// Zeichen zeigt einen echten Kalender: Wochenleiste + Tagesansicht mit
// Stundenraster, Termin-Bloecken und Jetzt-Linie. Gelb = Teams-Call.
// Termin anklicken = bearbeiten, leere Stelle anklicken / "+ Termin" = neu.
// ⚙ = Einstellungen (wie lange vorher erinnern, Morgen-Erinnerung, Modell).
// Fehlt das Foto fuer heute, zeigt das Zeichen ein "!".
// Links-Klick = Panel, Rechts-Klick = gleich aufnehmen.
// Im Panel: ←/→ = Tag, Bild↑/Bild↓ = Woche, Enter = Foto, Esc = zurueck/zu.
// IPC: omarchy-shell cillian-kalender toggle|settings|add|editNext
// Look wie das Startmenue (cillian.start): Glas, Blur (layer_rule
// "cillian-kalender" in looknfeel.lua), zwei Lichtpunkte auf dem Rand.
Panel {
  id: root
  moduleName: "cillian.kalender"

  // ---------------------------------------------------------------- Daten
  property var status: ({ today: "", has: false, dir: "", photos: [], store: "", next: null, lead: 10, settings: null })
  property var store: ({ status: "", days: {} })
  property bool loaded: false
  property string selected: ""
  property int nowMin: 0
  property real anchorX: -1
  property string view: "day"          // day | edit | settings

  // Entwurf im Bearbeiten-Formular
  property string dId: ""
  property string dTitle: ""
  property string dStart: ""
  property string dEnd: ""
  property string dInfo: ""
  property bool dTeams: false
  property string dColor: ""
  property var dRemind: null           // null = Standard, 0 = aus, n = Minuten
  property bool dAllday: false
  property bool delArm: false
  property string editError: ""
  property string editErrText: ""

  readonly property var cfg: status.settings || ({ lead: 10, teamsLead: -1, atStart: false, teamsOnly: false, morning: true,
    morningFrom: 5, morningTo: 17, repeat: 90, days: [1, 2, 3, 4, 5], model: "sonnet" })
  readonly property bool hasToday: status.has === true
  readonly property var storeDays: store && store.days ? store.days : ({})
  readonly property bool isToday: selected !== "" && selected === status.today
  readonly property var dayData: storeDays[selected] || null
  readonly property var allEvents: dayData && dayData.events ? dayData.events : []
  readonly property var timedEvents: allEvents.filter(function(e) { return !e.allday && e.start })
  readonly property var alldayEvents: allEvents.filter(function(e) { return e.allday })
  readonly property bool reading: store.status === "reading"
  readonly property var layout: layoutDay(timedEvents)
  readonly property int startHour: {
    var h = 8
    for (var i = 0; i < timedEvents.length; i++) h = Math.min(h, Math.floor(toMin(timedEvents[i].start) / 60))
    if (isToday && nowMin > 0) h = Math.min(h, Math.floor(nowMin / 60))
    return Math.max(0, h)
  }
  readonly property int endHour: {
    var h = 17
    for (var i = 0; i < timedEvents.length; i++) h = Math.max(h, Math.ceil(endMin(timedEvents[i]) / 60))
    return Math.min(24, Math.max(h, startHour + 6))
  }
  readonly property var nextEv: {
    if (!isToday) return null
    for (var i = 0; i < timedEvents.length; i++) if (toMin(timedEvents[i].start) > nowMin) return timedEvents[i]
    return null
  }
  readonly property var weekDays: {
    if (!selected) return []
    var d = parseDay(selected)
    var mon = new Date(d); mon.setDate(d.getDate() - ((d.getDay() + 6) % 7))
    var out = []
    for (var i = 0; i < 7; i++) {
      var x = new Date(mon); x.setDate(mon.getDate() + i)
      var iso = isoDay(x)
      var data = storeDays[iso]
      var n = data && data.events ? data.events.length : 0
      if (i >= 5 && n === 0 && iso !== selected) continue
      out.push({ iso: iso, wd: ["MO", "DI", "MI", "DO", "FR", "SA", "SO"][i], num: x.getDate(), known: !!data, count: n })
    }
    return out
  }
  readonly property var swatches: ["", "#f5a31a", "#22a722", "#1a73c9", "#e03aa0", "#8e44ad", "#7f8c8d"]

  // ---------------------------------------------------------------- Look
  readonly property color bg: Commons.Color.menu.background
  readonly property color fg: Commons.Color.menu.text
  readonly property color glow: Commons.Color.foreground
  readonly property color warn: Commons.Color.urgent
  readonly property string fontFamily: Style.font.menuFamily

  property real reveal: opened ? 1 : 0
  Behavior on reveal { NumberAnimation { duration: root.opened ? 280 : 160; easing.type: root.opened ? Easing.OutQuint : Easing.InCubic } }

  function sp(n) { return Style.space(n) }
  function glyph(cp) { return String.fromCodePoint(cp) }

  function toMin(hhmm) {
    var m = /^\s*(\d{1,2})[:.](\d{2})\s*$/.exec(String(hhmm || ""))
    if (!m) return -1
    var h = Number(m[1]), mi = Number(m[2])
    return h < 24 && mi < 60 ? h * 60 + mi : -1
  }
  function endMin(e) {
    var s = toMin(e.start), en = toMin(e.end)
    return en > s ? en : s + 30
  }
  function pad2(n) { return (n < 10 ? "0" : "") + n }
  function fmt(min) { min = Math.max(0, Math.min(1439, Math.round(min))); return pad2(Math.floor(min / 60)) + ":" + pad2(min % 60) }
  function isoDay(d) { return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate()) }
  function parseDay(s) {
    var p = String(s).split("-")
    return new Date(Number(p[0]), Number(p[1]) - 1, Number(p[2]))
  }
  function shiftDay(s, n) { var d = parseDay(s); d.setDate(d.getDate() + n); return isoDay(d) }

  // ueberlappende Termine nebeneinander: Gruppen bilden, Spalten verteilen
  function layoutDay(evs) {
    var list = evs.slice().sort(function(a, b) { return toMin(a.start) - toMin(b.start) || endMin(b) - endMin(a) })
    var out = [], group = [], colsEnd = [], groupEnd = -1
    function flush() {
      for (var j = 0; j < group.length; j++) group[j].cols = colsEnd.length
      out = out.concat(group); group = []; colsEnd = []
    }
    for (var i = 0; i < list.length; i++) {
      var e = list[i], s = toMin(e.start), en = endMin(e)
      if (group.length && s >= groupEnd) { flush(); groupEnd = -1 }
      var col = -1
      for (var c = 0; c < colsEnd.length; c++) if (colsEnd[c] <= s) { col = c; break }
      if (col < 0) { col = colsEnd.length; colsEnd.push(en) } else colsEnd[col] = en
      group.push({ e: e, col: col, cols: 1 })
      groupEnd = Math.max(groupEnd, en)
    }
    if (group.length) flush()
    return out
  }

  function evState(e) {
    if (!isToday) return "normal"
    if (nowMin >= endMin(e)) return "past"
    if (nowMin >= toMin(e.start)) return "now"
    return "future"
  }

  function untilText(e) {
    var d = toMin(e.start) - nowMin
    if (d <= 0) return "jetzt"
    if (d < 60) return "in " + d + " Min"
    var h = Math.floor(d / 60), m = d % 60
    return "in " + h + " h" + (m > 0 ? " " + m + " Min" : "")
  }

  function evColor(e) {
    var c = e && e.color ? String(e.color) : ""
    return /^#[0-9a-fA-F]{6}$/.test(c) ? Qt.color(c) : root.fg
  }
  function tint(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

  function dayTitle(s) {
    if (!s) return ""
    if (s === status.today) return "Heute"
    if (s === shiftDay(status.today, -1)) return "Gestern"
    if (s === shiftDay(status.today, 1)) return "Morgen"
    return parseDay(s).toLocaleDateString(Qt.locale("de_CH"), "dddd")
  }
  function daySubtitle(s) {
    if (!s) return ""
    return parseDay(s).toLocaleDateString(Qt.locale("de_CH"), "dddd, d. MMMM yyyy").toUpperCase()
  }
  function defaultLead(teams) {
    return teams && typeof cfg.teamsLead === "number" && cfg.teamsLead >= 0 ? cfg.teamsLead : cfg.lead
  }
  function remindText(n) {
    if (n === 0) return "aus"
    return n + " Min vorher"
  }

  function refresh() { if (!statusProc.running) statusProc.running = true }

  function shoot() {
    close()
    if (!shootProc.running) shootProc.running = true
  }
  function paste() {
    close()
    if (!pasteProc.running) pasteProc.running = true
  }
  // Foto, aus dem der gezeigte Tag stammt (sonst das neueste)
  function photoDay() {
    if (dayData && dayData.src) return dayData.src
    if (hasToday) return status.today
    return store.photo || ""
  }
  function reread() {
    var d = photoDay()
    if (d && !reading) Quickshell.execDetached(["kalender-foto", "read", d])
  }
  function openPhoto() {
    var d = photoDay()
    if (!d) return
    close()
    Quickshell.execDetached(["kalender-foto", "open", d])
  }
  function stepDay(dir) {
    var d = shiftDay(selected, dir)
    // Wochenenden ohne Termine ueberspringen
    for (var i = 0; i < 2; i++) {
      var wd = parseDay(d).getDay()
      var data = storeDays[d]
      if ((wd === 0 || wd === 6) && !(data && data.events && data.events.length)) d = shiftDay(d, dir)
    }
    selected = d
  }
  function stepWeek(dir) { selected = shiftDay(selected, 7 * dir) }

  function updateNow() {
    var n = new Date()
    nowMin = n.getHours() * 60 + n.getMinutes()
  }

  // ---------- Bearbeiten
  function openEdit(e) {
    dId = e.id || ""
    dTitle = e.title || ""
    dStart = e.start || ""
    dEnd = e.end || ""
    dInfo = e.info || ""
    dTeams = !!e.teams
    dColor = e.color || ""
    dRemind = (typeof e.remind === "number") ? e.remind : null
    dAllday = !!e.allday
    delArm = false
    editError = ""
    view = "edit"
  }
  function newAt(min) {
    openEdit({ start: fmt(min), end: fmt(min + 30) })
    Qt.callLater(function() { titleField.input.forceActiveFocus() })
  }
  function newDefault() {
    var m = isToday ? Math.ceil((nowMin + 1) / 15) * 15 : 9 * 60
    newAt(Math.min(m, 23 * 60))
  }
  function shiftTime(which, delta) {
    var s = toMin(dStart), e = toMin(dEnd)
    if (s < 0) s = 9 * 60
    if (which === "start") {
      var dur = e > s ? e - s : 30
      s = Math.max(0, Math.min(1435, s + delta))
      dStart = fmt(s)
      dEnd = fmt(Math.min(1439, s + dur))
    } else {
      if (e < 0) e = s + 30
      dEnd = fmt(Math.max(s + 5, Math.min(1439, e + delta)))
    }
  }
  function durationText() {
    var s = toMin(dStart), e = toMin(dEnd)
    if (s < 0 || e <= s) return "–"
    var d = e - s, h = Math.floor(d / 60), m = d % 60
    return (h > 0 ? h + " h " : "") + (m > 0 || h === 0 ? m + " Min" : "")
  }
  function saveEdit() {
    var t = dTitle.trim()
    if (!t) { editError = "Bitte einen Titel eingeben."; return }
    var s = toMin(dStart), e = dEnd.trim() ? toMin(dEnd) : -2
    if (!dAllday && s < 0) { editError = "Start bitte als HH:MM eingeben, z.B. 08:30."; return }
    if (e === -1) { editError = "Ende bitte als HH:MM eingeben."; return }
    if (!dAllday && e >= 0 && e <= s) { editError = "Das Ende muss nach dem Start sein."; return }
    var ev = { id: dId, title: t, start: dAllday ? "" : fmt(s), end: dAllday || e < 0 ? "" : fmt(e),
               info: dInfo.trim(), teams: dTeams, color: dColor, allday: dAllday }
    if (dRemind !== null) ev.remind = dRemind
    runEdit({ op: "save", event: ev })
  }
  function deleteEdit() {
    if (!dId) return
    if (!delArm) { delArm = true; return }
    runEdit({ op: "delete", id: dId })
  }
  function runEdit(op) {
    if (editProc.running) return
    editError = ""
    editErrText = ""
    editProc.command = ["kalender-foto", "edit", selected, JSON.stringify(op)]
    editProc.running = true
  }

  // ---------- Einstellungen (sofort gespeichert)
  function setSetting(key, value) {
    var patch = {}
    patch[key] = value
    var s = Object.assign({}, cfg, patch)
    status = Object.assign({}, status, { settings: s, lead: s.lead })
    Quickshell.execDetached(["kalender-foto", "set", JSON.stringify(patch)])
    settleTimer.restart()
  }
  function toggleDay(n) {
    var days = (cfg.days || []).slice()
    var i = days.indexOf(n)
    if (i >= 0) days.splice(i, 1); else days.push(n)
    days.sort()
    setSetting("days", days)
  }

  function back() {
    if (view !== "day") { view = "day"; delArm = false; Qt.callLater(function() { keyCatcher.forceActiveFocus() }) }
    else close()
  }

  onOpenedChanged: {
    if (opened) {
      var p = button.mapToItem(null, button.width / 2, 0)
      anchorX = p.x
      view = "day"
      if (status.today) selected = status.today
      updateNow()
      refresh()
      if (bar && typeof bar.requestPopout === "function") bar.requestPopout(root)
      Qt.callLater(function() { keyCatcher.forceActiveFocus(); timeline.scrollToNow() })
    } else if (bar && typeof bar.releasePopout === "function") {
      bar.releasePopout(root)
    }
  }
  onSelectedChanged: Qt.callLater(function() { timeline.scrollToNow() })

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // ---------------------------------------------------------------- Prozesse
  Process {
    id: statusProc
    command: ["kalender-foto", "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var s = JSON.parse(String(text || "").trim())
          var dayChanged = s.today !== root.status.today
          root.status = s
          root.loaded = true
          if (dayChanged || root.selected === "" || !root.opened) root.selected = s.today
        } catch (e) {}
      }
    }
  }
  Process { id: shootProc; command: ["kalender-foto", "shoot"]; onExited: root.refresh() }
  Process { id: pasteProc; command: ["kalender-foto", "paste"]; onExited: root.refresh() }
  Process {
    id: editProc
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.editErrText = String(text || "").trim()
        if (root.editError !== "" && root.editErrText !== "") root.editError = root.editErrText
      }
    }
    onExited: function(code) {
      if (code === 0) {
        root.view = "day"
        root.delArm = false
        Qt.callLater(function() { keyCatcher.forceActiveFocus() })
        root.refresh()
      } else {
        root.editError = root.editErrText || "Speichern hat nicht geklappt."
      }
    }
  }
  Timer { id: settleTimer; interval: 500; onTriggered: root.refresh() }

  // alle gelesenen Tage (wird live nachgeladen, wenn Claude fertig ist)
  FileView {
    path: root.status.store || ""
    watchChanges: true
    printErrors: false
    onFileChanged: { reload(); root.refresh() }
    onLoaded: {
      try { root.store = JSON.parse(text()) } catch (e) {}
    }
    onLoadFailed: root.store = ({ status: "", days: {} })
  }

  // Jede Minute: Status (Tageswechsel, naechster Termin) + Erinnerungen.
  // remind prueft selbst, ob schon erinnert wurde (eine Leiste pro Monitor).
  Timer {
    interval: 60000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      root.refresh()
      Quickshell.execDetached(["kalender-foto", "remind"])
    }
  }
  Timer { interval: 20000; running: root.opened; repeat: true; onTriggered: root.updateNow() }

  IpcHandler {
    target: "cillian-kalender"
    function toggle(): void { root.toggle() }
    function settings(): void { root.open(); root.view = "settings" }
    function add(): void { root.open(); root.newDefault() }
    function editNext(): void {
      root.open()
      var e = root.nextEv || root.timedEvents[0]
      if (e) root.openEdit(e)
    }
  }

  // ---------------------------------------------------------------- Leisten-Zeichen
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.glyph(root.loaded && !root.hasToday ? 0xF0A31 : 0xF00ED)
    active: root.loaded && !root.hasToday
    tooltipText: {
      if (root.opened) return ""
      if (root.loaded && !root.hasToday) return "Kalender-Foto für heute fehlt – klicken"
      var n = root.status.next
      if (n && n.start) return "Als Nächstes: " + n.start + "  " + (n.teams ? "Teams-Call · " : "") + n.title
      return "Kalender"
    }
    onPressed: function(b) {
      if (b === Qt.RightButton) root.shoot()
      else root.toggle()
    }
  }

  // ---------------------------------------------------------------- Fenster
  PanelWindow {
    id: win
    screen: root.QsWindow.window ? root.QsWindow.window.screen : null
    visible: root.opened || root.reveal > 0.01
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "cillian-kalender"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    readonly property int pad: root.sp(18)
    readonly property int gap: root.sp(12)
    readonly property int headH: root.sp(46)
    readonly property int weekH: root.sp(54)
    readonly property int nextH: root.nextEv ? root.sp(40) : 0
    readonly property int alldayH: root.alldayEvents.length > 0 ? root.sp(30) : 0
    readonly property int footH: root.sp(36)
    readonly property int margin: root.sp(14)
    readonly property int cardW: Math.min(root.sp(580), width - margin * 2)
    readonly property int topY: (root.bar && root.bar.barSize > 0 ? root.bar.barSize : 32) + root.sp(12)
    readonly property real maxCardH: height - topY - margin
    readonly property int hours: root.endHour - root.startHour
    // Tagesansicht: Kopf, Woche, [Als Naechstes], [Ganztags], Tag, Knoepfe
    readonly property int parts: 4 + (nextH > 0 ? 1 : 0) + (alldayH > 0 ? 1 : 0)
    readonly property real fixedH: pad * 2 + headH + weekH + nextH + alldayH + footH + gap * (parts - 1)
    readonly property real availTL: Math.max(root.sp(260), maxCardH - fixedH)
    readonly property real hourH: Math.max(root.sp(34), Math.min(root.sp(56), (availTL - root.sp(16)) / Math.max(1, hours)))
    readonly property bool showGrid: root.dayData !== null && root.allEvents.length > 0
    readonly property real tlH: showGrid ? Math.min(availTL, hours * hourH + root.sp(16)) : root.sp(300)
    // Formulare (Bearbeiten / Einstellungen)
    readonly property real formMaxH: maxCardH - pad * 2 - headH - gap
    readonly property real formH: Math.min(formMaxH, root.view === "edit" ? editForm.implicitHeight : settingsForm.implicitHeight)
    readonly property real cardH: root.view === "day" ? fixedH + tlH : pad * 2 + headH + gap + formH
    readonly property real cardX: {
      var cx = root.anchorX >= 0 ? root.anchorX : width / 2
      return Math.max(margin, Math.min(width - cardW - margin, cx - cardW / 2))
    }

    MouseArea { anchors.fill: parent; enabled: root.opened; onClicked: root.close() }

    Item {
      id: cardHolder
      x: win.cardX
      y: win.topY
      width: win.cardW
      height: win.cardH
      Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
      opacity: root.reveal
      scale: 0.96 + 0.04 * root.reveal
      transformOrigin: Item.Top
      transform: Translate { y: (1 - root.reveal) * -root.sp(14) }

      // Lichtschein + Schatten NUR aussen um die Karte (unter dem Glas
      // ausgeschnitten, sonst sieht man durchs Glas nur den Schatten) - work-22
      Item {
        id: shadowBox
        anchors.fill: card
        anchors.margins: -root.sp(130)
        layer.enabled: true
        layer.effect: MultiEffect {
          maskEnabled: true
          maskInverted: true
          maskSource: shadowCut
        }
        RectangularShadow {
          anchors.fill: parent
          anchors.margins: root.sp(130)
          radius: card.radius
          blur: root.sp(60)
          spread: root.sp(2)
          color: Util.alpha(root.glow, 0.09)
        }
        RectangularShadow {
          anchors.fill: parent
          anchors.margins: root.sp(130)
          anchors.topMargin: root.sp(130) + root.sp(16)
          radius: card.radius
          blur: root.sp(46)
          color: Qt.rgba(0, 0, 0, 0.65)
        }
      }
      Item {
        id: shadowCut
        anchors.fill: shadowBox
        visible: false
        layer.enabled: true
        Rectangle {
          anchors.fill: parent
          anchors.margins: root.sp(130)
          radius: card.radius
          color: "black"
        }
      }

      Rectangle {
        id: card
        anchors.fill: parent
        radius: root.sp(24)
        color: Util.alpha(root.bg, 0.70)
        border.width: 1
        border.color: Util.alpha(root.fg, 0.14)
        clip: true

        Rectangle {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          height: root.sp(200)
          radius: card.radius
          gradient: Gradient {
            GradientStop { position: 0.0; color: Util.alpha(root.fg, 0.06) }
            GradientStop { position: 1.0; color: "transparent" }
          }
        }

        MouseArea { anchors.fill: parent; onClicked: keyCatcher.forceActiveFocus() }

        Item {
          id: keyCatcher
          anchors.fill: parent
          focus: true
          Keys.onPressed: function(event) {
            var k = event.key
            if (k === Qt.Key_Escape) root.back()
            else if (root.view !== "day") return
            else if (k === Qt.Key_Left) root.stepDay(-1)
            else if (k === Qt.Key_Right) root.stepDay(1)
            else if (k === Qt.Key_PageUp) root.stepWeek(-1)
            else if (k === Qt.Key_PageDown) root.stepWeek(1)
            else if (k === Qt.Key_Home) root.selected = root.status.today
            else if (k === Qt.Key_Up) timeline.flick(0, root.sp(900))
            else if (k === Qt.Key_Down) timeline.flick(0, -root.sp(900))
            else if (k === Qt.Key_Plus || k === Qt.Key_N) root.newDefault()
            else if (k === Qt.Key_Return || k === Qt.Key_Enter) root.openPhoto()
            else return
            event.accepted = true
          }

          Column {
            x: win.pad
            y: win.pad
            width: card.width - win.pad * 2
            spacing: win.gap

            // ---------- Kopf
            Item {
              width: parent.width
              height: win.headH

              Rectangle {
                id: headIcon
                width: root.sp(42); height: width; radius: width / 2
                anchors.verticalCenter: parent.verticalCenter
                gradient: Gradient {
                  GradientStop { position: 0.0; color: Util.alpha(root.fg, 0.16) }
                  GradientStop { position: 1.0; color: Util.alpha(root.fg, 0.05) }
                }
                border.width: 1
                border.color: Util.alpha(root.fg, 0.16)
                Text {
                  anchors.centerIn: parent
                  text: root.glyph(root.view === "settings" ? 0xF0493 : (root.view === "edit" ? 0xF03EB : 0xF00ED))
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.iconLarge
                }
              }

              Column {
                anchors.left: headIcon.right
                anchors.leftMargin: root.sp(14)
                anchors.right: navRow.left
                anchors.rightMargin: root.sp(10)
                anchors.verticalCenter: parent.verticalCenter
                spacing: root.sp(3)
                Text {
                  width: parent.width
                  text: root.view === "settings" ? "Einstellungen"
                    : root.view === "edit" ? (root.dId ? "Termin bearbeiten" : "Neuer Termin")
                    : "Kalender · " + root.dayTitle(root.selected)
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.heading
                  font.bold: true
                  elide: Text.ElideRight
                }
                Text {
                  width: parent.width
                  text: root.view === "settings" ? "KALENDER · ERINNERUNGEN" : root.daySubtitle(root.selected)
                  color: Util.alpha(root.fg, 0.55)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  font.letterSpacing: 1.4
                  elide: Text.ElideRight
                }
              }

              Row {
                id: navRow
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: root.sp(6)
                RoundButton { visible: root.view === "day"; glyphText: root.glyph(0xF0450); usable: root.photoDay() !== "" && !root.reading; onActivated: root.reread() }
                RoundButton { visible: root.view === "day"; glyphText: root.glyph(0xF0493); onActivated: root.view = "settings" }
                Item { visible: root.view === "day"; width: root.sp(4); height: 1 }
                RoundButton { visible: root.view === "day"; glyphText: root.glyph(0xF0141); onActivated: root.stepWeek(-1) }
                RoundButton { visible: root.view === "day"; glyphText: root.glyph(0xF0142); onActivated: root.stepWeek(1) }
                RoundButton { visible: root.view !== "day"; glyphText: root.glyph(0xF0156); onActivated: root.back() }
              }
            }

            // ---------- Woche
            Row {
              id: weekRow
              visible: root.view === "day"
              width: parent.width
              height: win.weekH
              spacing: root.sp(6)
              readonly property real cellW: (width - spacing * (root.weekDays.length - 1)) / Math.max(1, root.weekDays.length)

              Repeater {
                model: root.weekDays
                Rectangle {
                  id: dayChip
                  required property var modelData
                  readonly property bool sel: modelData.iso === root.selected
                  readonly property bool tod: modelData.iso === root.status.today
                  width: weekRow.cellW
                  height: weekRow.height
                  radius: root.sp(14)
                  color: sel ? Util.alpha(root.fg, 0.16) : Util.alpha(root.fg, chipMouse.containsMouse ? 0.08 : 0.03)
                  border.width: 1
                  border.color: sel ? Util.alpha(root.fg, 0.38) : (tod ? Util.alpha(root.fg, 0.24) : Util.alpha(root.fg, 0.07))
                  Behavior on color { ColorAnimation { duration: 140 } }

                  Column {
                    anchors.centerIn: parent
                    spacing: root.sp(2)
                    Text {
                      anchors.horizontalCenter: parent.horizontalCenter
                      text: dayChip.modelData.wd
                      color: Util.alpha(root.fg, dayChip.sel || dayChip.tod ? 0.85 : 0.5)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                      font.letterSpacing: 1.2
                    }
                    Text {
                      anchors.horizontalCenter: parent.horizontalCenter
                      text: dayChip.modelData.num
                      color: root.fg
                      opacity: dayChip.modelData.known || dayChip.tod ? 1 : 0.45
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.title
                      font.bold: dayChip.sel || dayChip.tod
                    }
                    Row {
                      anchors.horizontalCenter: parent.horizontalCenter
                      spacing: root.sp(3)
                      height: root.sp(5)
                      Repeater {
                        model: Math.min(4, dayChip.modelData.count)
                        Rectangle { width: root.sp(4); height: width; radius: width / 2; color: Util.alpha(root.fg, 0.6) }
                      }
                    }
                  }
                  MouseArea {
                    id: chipMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.selected = dayChip.modelData.iso
                  }
                }
              }
            }

            // ---------- Als Naechstes
            Rectangle {
              id: nextBox
              visible: root.view === "day" && root.nextEv !== null
              width: parent.width
              height: win.nextH
              radius: height / 2
              color: Util.alpha(root.fg, nextMouse.containsMouse ? 0.10 : 0.06)
              border.width: 1
              border.color: Util.alpha(root.fg, 0.12)
              readonly property var ev: root.nextEv || ({})
              Row {
                anchors.left: parent.left
                anchors.leftMargin: root.sp(16)
                anchors.right: parent.right
                anchors.rightMargin: root.sp(16)
                anchors.verticalCenter: parent.verticalCenter
                spacing: root.sp(10)
                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: root.sp(8); height: width; radius: width / 2; color: root.evColor(nextBox.ev) }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: "ALS NÄCHSTES"
                  color: Util.alpha(root.fg, 0.55)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  font.letterSpacing: 1.2
                }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  visible: !!nextBox.ev.teams
                  text: root.glyph(0xF02BB)
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  width: parent.width - x - nxWhen.width - parent.spacing
                  text: (nextBox.ev.start || "") + "  " + (nextBox.ev.title || "")
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                  elide: Text.ElideRight
                }
                Text {
                  id: nxWhen
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.nextEv ? root.untilText(root.nextEv) : ""
                  color: root.glow
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }
              }
              MouseArea {
                id: nextMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: if (root.nextEv) root.openEdit(root.nextEv)
              }
            }

            // ---------- Ganztags
            Row {
              visible: root.view === "day" && root.alldayEvents.length > 0
              width: parent.width
              height: win.alldayH
              spacing: root.sp(6)
              Repeater {
                model: root.alldayEvents
                Rectangle {
                  required property var modelData
                  height: parent.height
                  width: Math.min(parent.width, adText.implicitWidth + root.sp(24))
                  radius: root.sp(8)
                  color: root.tint(root.evColor(modelData), 0.22)
                  border.width: 1
                  border.color: root.tint(root.evColor(modelData), 0.5)
                  Text {
                    id: adText
                    anchors.centerIn: parent
                    width: parent.width - root.sp(16)
                    text: (modelData.teams ? root.glyph(0xF02BB) + " " : "") + modelData.title
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignHCenter
                  }
                  MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.openEdit(modelData) }
                }
              }
            }

            // ---------- Tag (Stundenraster)
            Item {
              visible: root.view === "day"
              width: parent.width
              height: win.tlH

              Rectangle {
                anchors.fill: parent
                radius: root.sp(16)
                color: Util.alpha(root.fg, 0.03)
                border.width: 1
                border.color: Util.alpha(root.fg, 0.08)
              }

              Flickable {
                id: timeline
                anchors.fill: parent
                anchors.margins: 1
                visible: win.showGrid
                clip: true
                contentHeight: win.hours * win.hourH + root.sp(16)
                boundsBehavior: Flickable.StopAtBounds

                function scrollToNow() {
                  if (!visible) return
                  var target = root.isToday ? ((root.nowMin / 60 - root.startHour) - 1) * win.hourH : 0
                  contentY = Math.max(0, Math.min(contentHeight - height, target))
                }

                Item {
                  id: grid
                  width: timeline.width
                  height: timeline.contentHeight
                  readonly property real top0: root.sp(8)
                  readonly property real x0: root.sp(52)
                  readonly property real areaW: width - x0 - root.sp(8)
                  function yOf(min) { return top0 + (min / 60 - root.startHour) * win.hourH }

                  // leere Stelle anklicken = neuer Termin (auf 15 Min gerundet)
                  MouseArea {
                    id: gridMouse
                    x: grid.x0
                    width: grid.areaW
                    height: parent.height
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: function(mouse) {
                      var min = root.startHour * 60 + (mouse.y - grid.top0) / win.hourH * 60
                      root.newAt(Math.max(0, Math.floor(min / 15) * 15))
                    }
                  }
                  Rectangle {
                    visible: gridMouse.containsMouse
                    x: grid.x0
                    width: grid.areaW
                    height: win.hourH / 4
                    y: grid.yOf(Math.floor((root.startHour * 60 + (gridMouse.mouseY - grid.top0) / win.hourH * 60) / 15) * 15)
                    radius: root.sp(6)
                    color: Util.alpha(root.fg, 0.05)
                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      x: root.sp(8)
                      text: "+ neuer Termin"
                      color: Util.alpha(root.fg, 0.4)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }

                  // Stundenlinien
                  Repeater {
                    model: win.hours + 1
                    Item {
                      required property int index
                      width: grid.width
                      y: grid.yOf((root.startHour + index) * 60)
                      Text {
                        x: root.sp(14)
                        anchors.verticalCenter: line.verticalCenter
                        text: root.pad2(root.startHour + index) + ":00"
                        visible: !(root.isToday && Math.abs(root.nowMin - (root.startHour + index) * 60) < 12)
                        color: Util.alpha(root.fg, 0.4)
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }
                      Rectangle { id: line; x: grid.x0; width: grid.width - grid.x0 - root.sp(8); height: 1; color: Util.alpha(root.fg, 0.08) }
                      Rectangle {
                        visible: index < win.hours
                        x: grid.x0; y: win.hourH / 2
                        width: grid.width - grid.x0 - root.sp(8); height: 1
                        color: Util.alpha(root.fg, 0.035)
                      }
                    }
                  }

                  // Termine
                  Repeater {
                    model: root.layout
                    EventBlock {
                      required property var modelData
                      ev: modelData.e
                      x: grid.x0 + modelData.col * (grid.areaW / modelData.cols) + root.sp(2)
                      y: grid.yOf(root.toMin(modelData.e.start)) + 1
                      width: grid.areaW / modelData.cols - root.sp(4)
                      height: Math.max(root.sp(22), (root.endMin(modelData.e) - root.toMin(modelData.e.start)) / 60 * win.hourH - 2)
                    }
                  }

                  // Jetzt-Linie
                  Item {
                    visible: root.isToday && root.nowMin >= root.startHour * 60 && root.nowMin <= root.endHour * 60
                    width: grid.width
                    y: grid.yOf(root.nowMin)
                    z: 10
                    Rectangle {
                      x: grid.x0 - root.sp(4); y: -root.sp(4)
                      width: root.sp(8); height: width; radius: width / 2
                      color: root.glow
                    }
                    Rectangle {
                      x: grid.x0; y: -1
                      width: grid.width - grid.x0 - root.sp(8); height: 2
                      color: root.glow
                      opacity: 0.85
                    }
                    Text {
                      x: root.sp(10)
                      anchors.verticalCenter: parent.top
                      text: root.pad2(Math.floor(root.nowMin / 60)) + ":" + root.pad2(root.nowMin % 60)
                      color: root.glow
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }
                  }
                }
              }

              // Zustaende: kein Foto / liest / Fehler / leer
              Column {
                anchors.centerIn: parent
                width: parent.width - root.sp(60)
                spacing: root.sp(10)
                visible: !win.showGrid

                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  visible: !root.reading
                  text: root.glyph(root.dayData === null && root.isToday && !root.hasToday ? 0xF0A31 : 0xF00ED)
                  color: root.dayData === null && root.isToday && !root.hasToday ? root.warn : Util.alpha(root.fg, 0.4)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.displayLarge * 1.5
                }
                Row {
                  anchors.horizontalCenter: parent.horizontalCenter
                  visible: root.reading
                  spacing: root.sp(8)
                  height: root.sp(24)
                  Repeater {
                    model: 3
                    Rectangle {
                      required property int index
                      anchors.verticalCenter: parent.verticalCenter
                      width: root.sp(9); height: width; radius: width / 2
                      color: root.fg
                      SequentialAnimation on opacity {
                        running: root.opened && root.reading
                        loops: Animation.Infinite
                        PauseAnimation { duration: index * 180 }
                        NumberAnimation { from: 0.15; to: 1; duration: 420; easing.type: Easing.InOutSine }
                        NumberAnimation { from: 1; to: 0.15; duration: 420; easing.type: Easing.InOutSine }
                        PauseAnimation { duration: (2 - index) * 180 }
                      }
                    }
                  }
                }
                Text {
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                  wrapMode: Text.WordWrap
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  font.bold: true
                  text: {
                    if (root.reading) return "Claude liest deinen Kalender …"
                    if (root.store.status === "error" && root.dayData === null) return "Kalender konnte nicht gelesen werden"
                    if (root.dayData !== null) return "Keine Termine"
                    if (root.isToday && !root.hasToday) return "Noch kein Kalender-Foto für heute"
                    return "Für diesen Tag gibt es kein Foto"
                  }
                }
                Text {
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                  wrapMode: Text.WordWrap
                  maximumLineCount: 4
                  elide: Text.ElideRight
                  color: Util.alpha(root.fg, 0.55)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  text: {
                    if (root.reading) return "dauert etwa 15 Sekunden"
                    if (root.store.status === "error" && root.dayData === null) return String(root.store.msg || "")
                    if (root.dayData !== null) return root.isToday ? "Heute ist frei." : ""
                    if (root.isToday && !root.hasToday) return "Öffne deinen Kalender (Wochenansicht geht auch), klick auf «Aufnehmen» und zieh einen Rahmen darum. Claude macht daraus deinen Kalender und erinnert dich vor jedem Termin."
                    return "Mach ein Foto von der Woche – oder trag selbst einen Termin ein."
                  }
                }
                Row {
                  anchors.horizontalCenter: parent.horizontalCenter
                  spacing: root.sp(8)
                  Pill {
                    visible: !root.reading && root.isToday && !root.hasToday
                    primary: true
                    glyphText: root.glyph(0xF0100)
                    label: "Aufnehmen"
                    onActivated: root.shoot()
                  }
                  Pill {
                    visible: !root.reading && root.store.status === "error" && root.dayData === null && root.photoDay() !== ""
                    glyphText: root.glyph(0xF0450)
                    label: "Nochmal lesen"
                    onActivated: root.reread()
                  }
                  Pill {
                    visible: !root.reading
                    glyphText: root.glyph(0xF0415)
                    label: "Termin eintragen"
                    onActivated: root.newDefault()
                  }
                }
              }

              // kleiner Hinweis, wenn neu gelesen wird, waehrend schon Termine da sind
              Rectangle {
                visible: root.reading && win.showGrid
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: root.sp(10)
                height: root.sp(26)
                width: rdText.implicitWidth + root.sp(22)
                radius: height / 2
                color: Util.alpha(root.bg, 0.85)
                border.width: 1
                border.color: Util.alpha(root.fg, 0.25)
                Text {
                  id: rdText
                  anchors.centerIn: parent
                  text: "Claude liest neu …"
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
              }
            }

            // ---------- Knoepfe (Tagesansicht)
            Item {
              visible: root.view === "day"
              width: parent.width
              height: win.footH

              Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: root.sp(8)
                Pill {
                  primary: !root.hasToday
                  glyphText: root.glyph(root.hasToday ? 0xF0E1A : 0xF0100)
                  label: "Aufnehmen"
                  onActivated: root.shoot()
                }
                Pill {
                  glyphText: root.glyph(0xF014C)
                  label: "Zwischenablage"
                  onActivated: root.paste()
                }
                Pill {
                  visible: root.photoDay() !== ""
                  glyphText: root.glyph(0xF02E9)
                  label: "Foto"
                  onActivated: root.openPhoto()
                }
              }
              Pill {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                glyphText: root.glyph(0xF0415)
                label: "Termin"
                onActivated: root.newDefault()
              }
            }

            // ---------- Bearbeiten
            Flickable {
              visible: root.view === "edit"
              width: parent.width
              height: win.formH
              contentHeight: editForm.implicitHeight
              clip: true
              boundsBehavior: Flickable.StopAtBounds

              Column {
                id: editForm
                width: parent.width
                spacing: root.sp(14)

                Column {
                  width: parent.width
                  spacing: root.sp(6)
                  SectionLabel { text: "TITEL" }
                  Field {
                    id: titleField
                    width: parent.width
                    placeholder: "z.B. Teams-Call mit …"
                    text: root.dTitle
                    onEdited: function(t) { root.dTitle = t }
                    onSubmitted: root.saveEdit()
                  }
                }

                Row {
                  visible: !root.dAllday
                  spacing: root.sp(18)
                  Column {
                    spacing: root.sp(6)
                    SectionLabel { text: "START" }
                    TimeRow { value: root.dStart; onEdited: function(t) { root.dStart = t }; onStep: function(d) { root.shiftTime("start", d) } }
                  }
                  Column {
                    spacing: root.sp(6)
                    SectionLabel { text: "ENDE" }
                    TimeRow { value: root.dEnd; onEdited: function(t) { root.dEnd = t }; onStep: function(d) { root.shiftTime("end", d) } }
                  }
                  Column {
                    spacing: root.sp(6)
                    SectionLabel { text: "DAUER" }
                    Item {
                      width: root.sp(80); height: root.sp(36)
                      Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.durationText()
                        color: root.fg
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                      }
                    }
                  }
                }

                Column {
                  width: parent.width
                  spacing: root.sp(6)
                  SectionLabel { text: "ORT / INFO" }
                  Field {
                    width: parent.width
                    placeholder: "optional"
                    text: root.dInfo
                    onEdited: function(t) { root.dInfo = t }
                    onSubmitted: root.saveEdit()
                  }
                }

                Column {
                  width: parent.width
                  spacing: root.sp(6)
                  SectionLabel { text: "ERINNERUNG" }
                  Flow {
                    width: parent.width
                    spacing: root.sp(6)
                    Chip { label: "Standard (" + root.remindText(root.defaultLead(root.dTeams)) + ")"; on: root.dRemind === null; onActivated: root.dRemind = null }
                    Chip { label: "Aus"; on: root.dRemind === 0; onActivated: root.dRemind = 0 }
                    Repeater {
                      model: [2, 5, 10, 15, 30, 60]
                      Chip {
                        required property int modelData
                        label: modelData + " Min"
                        on: root.dRemind === modelData
                        onActivated: root.dRemind = modelData
                      }
                    }
                  }
                }

                Column {
                  width: parent.width
                  spacing: root.sp(6)
                  SectionLabel { text: "ART & FARBE" }
                  Row {
                    spacing: root.sp(10)
                    Chip {
                      anchors.verticalCenter: parent.verticalCenter
                      label: root.glyph(0xF02BB) + "  Teams-Call"
                      on: root.dTeams
                      onActivated: root.dTeams = !root.dTeams
                    }
                    Item { width: root.sp(6); height: 1 }
                    Repeater {
                      model: root.swatches
                      Rectangle {
                        required property string modelData
                        readonly property bool sel: root.dColor.toLowerCase() === modelData.toLowerCase()
                        anchors.verticalCenter: parent.verticalCenter
                        width: root.sp(24); height: width; radius: width / 2
                        color: modelData ? modelData : Util.alpha(root.fg, 0.25)
                        border.width: sel ? 2 : 1
                        border.color: sel ? root.fg : Util.alpha(root.fg, 0.2)
                        scale: swMouse.containsMouse ? 1.12 : 1
                        Behavior on scale { NumberAnimation { duration: 120 } }
                        MouseArea {
                          id: swMouse
                          anchors.fill: parent
                          hoverEnabled: true
                          cursorShape: Qt.PointingHandCursor
                          onClicked: {
                            root.dColor = modelData
                            if (modelData.toLowerCase() === "#f5a31a") root.dTeams = true   // gelb = Teams-Call
                          }
                        }
                      }
                    }
                  }
                }

                Text {
                  visible: root.editError !== ""
                  width: parent.width
                  text: root.editError
                  color: root.warn
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                  wrapMode: Text.WordWrap
                }

                Item {
                  width: parent.width
                  height: root.sp(40)
                  Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: root.sp(8)
                    Pill { primary: true; glyphText: root.glyph(0xF012C); label: "Speichern"; onActivated: root.saveEdit() }
                    Pill { glyphText: root.glyph(0xF0156); label: "Abbrechen"; onActivated: root.back() }
                  }
                  Pill {
                    visible: root.dId !== ""
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    primary: root.delArm
                    glyphText: root.glyph(0xF0A7A)
                    label: root.delArm ? "Wirklich löschen?" : "Löschen"
                    onActivated: root.deleteEdit()
                  }
                }
              }
            }

            // ---------- Einstellungen
            Flickable {
              visible: root.view === "settings"
              width: parent.width
              height: win.formH
              contentHeight: settingsForm.implicitHeight
              clip: true
              boundsBehavior: Flickable.StopAtBounds

              Column {
                id: settingsForm
                width: parent.width
                spacing: root.sp(12)

                SectionLabel { text: "ERINNERUNG VOR TERMINEN" }
                Flow {
                  width: parent.width
                  spacing: root.sp(6)
                  Repeater {
                    model: [0, 5, 10, 15, 30, 60]
                    Chip {
                      required property int modelData
                      label: modelData === 0 ? "Aus" : modelData + " Min vorher"
                      on: root.cfg.lead === modelData
                      onActivated: root.setSetting("lead", modelData)
                    }
                  }
                }
                Row {
                  spacing: root.sp(6)
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.glyph(0xF02BB) + "  Teams-Calls"
                    color: Util.alpha(root.fg, 0.75)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    rightPadding: root.sp(4)
                  }
                  Repeater {
                    model: [-1, 0, 1, 2, 5, 10]
                    Chip {
                      required property int modelData
                      label: modelData === -1 ? "wie oben" : (modelData === 0 ? "Aus" : modelData + " Min")
                      on: (typeof root.cfg.teamsLead === "number" ? root.cfg.teamsLead : -1) === modelData
                      onActivated: root.setSetting("teamsLead", modelData)
                    }
                  }
                }
                Toggle {
                  width: parent.width
                  label: "Auch beim Beginn erinnern"
                  hint: "zweite Meldung, wenn der Termin anfängt"
                  on: root.cfg.atStart === true
                  onToggled: root.setSetting("atStart", !root.cfg.atStart)
                }
                Toggle {
                  width: parent.width
                  label: "Nur bei Teams-Calls erinnern"
                  hint: "gelbe Termine"
                  on: root.cfg.teamsOnly === true
                  onToggled: root.setSetting("teamsOnly", !root.cfg.teamsOnly)
                }
                Text {
                  width: parent.width
                  text: "Pro Termin geht es auch anders: Termin anklicken → Erinnerung."
                  color: Util.alpha(root.fg, 0.45)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }

                Rectangle { width: parent.width; height: 1; color: Util.alpha(root.fg, 0.08) }

                SectionLabel { text: "FOTO AM MORGEN" }
                Toggle {
                  width: parent.width
                  label: "Erinnern, wenn das Foto fehlt"
                  hint: "mit Knopf «Jetzt aufnehmen»"
                  on: root.cfg.morning === true
                  onToggled: root.setSetting("morning", !root.cfg.morning)
                }
                Column {
                  width: parent.width
                  spacing: root.sp(8)
                  opacity: root.cfg.morning ? 1 : 0.4
                  enabled: root.cfg.morning === true
                  ChipLine {
                    title: "Ab"
                    values: [5, 6, 7, 8, 9]
                    suffix: " Uhr"
                    current: root.cfg.morningFrom
                    onPicked: function(v) { root.setSetting("morningFrom", v) }
                  }
                  ChipLine {
                    title: "Bis"
                    values: [11, 12, 15, 17, 20]
                    suffix: " Uhr"
                    current: root.cfg.morningTo
                    onPicked: function(v) { root.setSetting("morningTo", v) }
                  }
                  ChipLine {
                    title: "Alle"
                    values: [30, 60, 90, 120]
                    suffix: " Min"
                    current: root.cfg.repeat
                    onPicked: function(v) { root.setSetting("repeat", v) }
                  }
                  Row {
                    spacing: root.sp(6)
                    Text {
                      width: root.sp(44)
                      anchors.verticalCenter: parent.verticalCenter
                      text: "Tage"
                      color: Util.alpha(root.fg, 0.6)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                    }
                    Repeater {
                      model: ["MO", "DI", "MI", "DO", "FR", "SA", "SO"]
                      Chip {
                        required property string modelData
                        required property int index
                        label: modelData
                        on: (root.cfg.days || []).indexOf(index + 1) >= 0
                        onActivated: root.toggleDay(index + 1)
                      }
                    }
                  }
                }

                Rectangle { width: parent.width; height: 1; color: Util.alpha(root.fg, 0.08) }

                SectionLabel { text: "TERMINE LESEN MIT" }
                Row {
                  spacing: root.sp(6)
                  Chip { label: "Haiku · schnell"; on: root.cfg.model === "haiku"; onActivated: root.setSetting("model", "haiku") }
                  Chip { label: "Sonnet"; on: root.cfg.model === "sonnet"; onActivated: root.setSetting("model", "sonnet") }
                  Chip { label: "Opus · genau"; on: root.cfg.model === "opus"; onActivated: root.setSetting("model", "opus") }
                }
                Text {
                  width: parent.width
                  text: "Gilt fürs nächste Foto. Nochmal lesen: " + root.glyph(0xF0450) + " oben im Kalender. Deine eigenen Änderungen bleiben dabei erhalten."
                  color: Util.alpha(root.fg, 0.45)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }

                Item {
                  width: parent.width
                  height: root.sp(40)
                  Pill {
                    anchors.verticalCenter: parent.verticalCenter
                    primary: true
                    glyphText: root.glyph(0xF012C)
                    label: "Fertig"
                    onActivated: root.back()
                  }
                }
              }
            }
          }
        }
      }

      // Umlaufendes Licht auf dem Rand (wie im Startmenue)
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

      Item {
        id: ringMask
        anchors.fill: card
        visible: false
        layer.enabled: true
        Rectangle {
          anchors.fill: parent
          radius: card.radius
          color: "transparent"
          border.width: Math.max(1.5, root.sp(1.6))
          border.color: "black"
        }
      }
    }
  }

  // ---------------------------------------------------------------- Bausteine
  component Pill: Rectangle {
    id: pill
    property string glyphText: ""
    property string label: ""
    property bool primary: false
    signal activated()
    height: root.sp(34)
    width: pillRow.implicitWidth + root.sp(30)
    radius: height / 2
    color: Util.alpha(root.fg, primary ? (pillMouse.containsMouse ? 0.24 : 0.16) : (pillMouse.containsMouse ? 0.12 : 0.05))
    border.width: 1
    border.color: Util.alpha(root.fg, pillMouse.containsMouse ? 0.35 : (primary ? 0.28 : 0.10))
    Behavior on color { ColorAnimation { duration: 150 } }
    Row {
      id: pillRow
      anchors.centerIn: parent
      spacing: root.sp(8)
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: pill.glyphText
        color: root.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: pill.label
        color: root.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: pill.primary
      }
    }
    MouseArea {
      id: pillMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: pill.activated()
    }
  }

  component RoundButton: Rectangle {
    id: rb
    property string glyphText: ""
    property bool usable: true
    signal activated()
    width: root.sp(32); height: width; radius: width / 2
    opacity: usable ? 1 : 0.3
    color: Util.alpha(root.fg, rbMouse.containsMouse && usable ? 0.14 : 0.05)
    border.width: 1
    border.color: Util.alpha(root.fg, rbMouse.containsMouse && usable ? 0.35 : 0.10)
    Behavior on color { ColorAnimation { duration: 150 } }
    Text {
      anchors.centerIn: parent
      text: rb.glyphText
      color: root.fg
      font.family: root.fontFamily
      font.pixelSize: Style.font.title
    }
    MouseArea {
      id: rbMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: rb.usable ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: if (rb.usable) rb.activated()
    }
  }

  component Chip: Rectangle {
    id: chip
    property string label: ""
    property bool on: false
    signal activated()
    height: root.sp(30)
    width: chipText.implicitWidth + root.sp(24)
    radius: height / 2
    color: on ? Util.alpha(root.fg, 0.18) : Util.alpha(root.fg, chipMouse.containsMouse ? 0.10 : 0.04)
    border.width: 1
    border.color: on ? Util.alpha(root.fg, 0.45) : Util.alpha(root.fg, 0.10)
    Behavior on color { ColorAnimation { duration: 120 } }
    Text {
      id: chipText
      anchors.centerIn: parent
      text: chip.label
      color: root.fg
      opacity: chip.on ? 1 : 0.75
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: chip.on
    }
    MouseArea {
      id: chipMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: chip.activated()
    }
  }

  component ChipLine: Row {
    id: cl
    property string title: ""
    property var values: []
    property string suffix: ""
    property int current: -1
    signal picked(int v)
    spacing: root.sp(6)
    Text {
      width: root.sp(44)
      anchors.verticalCenter: parent.verticalCenter
      text: cl.title
      color: Util.alpha(root.fg, 0.6)
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
    Repeater {
      model: cl.values
      Chip {
        required property int modelData
        label: modelData + cl.suffix
        on: cl.current === modelData
        onActivated: cl.picked(modelData)
      }
    }
  }

  component Toggle: Item {
    id: tg
    property string label: ""
    property string hint: ""
    property bool on: false
    signal toggled()
    height: Math.max(root.sp(36), tgCol.implicitHeight + root.sp(6))
    Column {
      id: tgCol
      anchors.left: parent.left
      anchors.right: sw.left
      anchors.rightMargin: root.sp(12)
      anchors.verticalCenter: parent.verticalCenter
      spacing: root.sp(2)
      Text {
        width: parent.width
        text: tg.label
        color: root.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }
      Text {
        visible: tg.hint !== ""
        width: parent.width
        text: tg.hint
        color: Util.alpha(root.fg, 0.45)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }
    Rectangle {
      id: sw
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: root.sp(44); height: root.sp(24); radius: height / 2
      color: tg.on ? Util.alpha(root.fg, 0.8) : Util.alpha(root.fg, 0.10)
      border.width: 1
      border.color: Util.alpha(root.fg, tg.on ? 0.8 : 0.2)
      Behavior on color { ColorAnimation { duration: 150 } }
      Rectangle {
        width: root.sp(18); height: width; radius: width / 2
        y: (parent.height - height) / 2
        x: tg.on ? parent.width - width - root.sp(3) : root.sp(3)
        color: tg.on ? root.bg : Util.alpha(root.fg, 0.75)
        Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
      }
    }
    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: tg.toggled()
    }
  }

  component SectionLabel: Text {
    color: Util.alpha(root.fg, 0.55)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: 1.4
  }

  component Field: Rectangle {
    id: fld
    property alias text: input.text
    property alias input: input
    property string placeholder: ""
    signal edited(string t)
    signal submitted()
    height: root.sp(38)
    radius: root.sp(10)
    color: Util.alpha(root.fg, input.activeFocus ? 0.09 : 0.05)
    border.width: 1
    border.color: Util.alpha(root.fg, input.activeFocus ? 0.4 : 0.12)
    Behavior on border.color { ColorAnimation { duration: 140 } }
    TextInput {
      id: input
      anchors.fill: parent
      anchors.leftMargin: root.sp(12)
      anchors.rightMargin: root.sp(12)
      verticalAlignment: TextInput.AlignVCenter
      color: root.fg
      selectionColor: Util.alpha(root.fg, 0.3)
      selectedTextColor: root.fg
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      clip: true
      selectByMouse: true
      onTextEdited: fld.edited(text)
      onAccepted: fld.submitted()
    }
    Text {
      anchors.left: parent.left
      anchors.leftMargin: root.sp(12)
      anchors.verticalCenter: parent.verticalCenter
      visible: input.text === "" && !input.activeFocus
      text: fld.placeholder
      color: Util.alpha(root.fg, 0.35)
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }
  }

  component TimeRow: Row {
    id: tr
    property string value: ""
    signal edited(string t)
    signal step(int d)
    spacing: root.sp(4)
    RoundButton { anchors.verticalCenter: parent.verticalCenter; glyphText: "−"; onActivated: tr.step(-5) }
    Field {
      width: root.sp(74)
      text: tr.value
      onEdited: function(t) { tr.edited(t) }
      onSubmitted: root.saveEdit()
    }
    RoundButton { anchors.verticalCenter: parent.verticalCenter; glyphText: "+"; onActivated: tr.step(5) }
  }

  // ein Termin im Stundenraster (anklicken = bearbeiten)
  component EventBlock: Rectangle {
    id: eb
    property var ev: ({})
    readonly property string st: root.evState(ev)
    readonly property color c: root.evColor(ev)
    readonly property bool roomy: height >= root.sp(44)
    radius: root.sp(8)
    color: root.tint(c, st === "now" ? 0.34 : (ebMouse.containsMouse ? 0.3 : 0.2))
    border.width: 1
    border.color: st === "now" || ebMouse.containsMouse ? root.glow : root.tint(c, 0.5)
    opacity: st === "past" && !ebMouse.containsMouse ? 0.42 : 1
    clip: true

    Rectangle {
      x: 0; y: 0
      width: root.sp(4); height: parent.height
      color: eb.c
    }

    Column {
      x: root.sp(10)
      y: eb.roomy ? root.sp(5) : (eb.height - height) / 2
      width: eb.width - root.sp(14)
      spacing: root.sp(1)
      Row {
        width: parent.width
        spacing: root.sp(5)
        Text {
          id: teamsGlyph
          visible: !!eb.ev.teams
          text: root.glyph(0xF02BB)
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
        Text {
          width: parent.width - (teamsGlyph.visible ? teamsGlyph.width + parent.spacing : 0)
          text: eb.roomy ? String(eb.ev.title || "") : (eb.ev.start + "  " + String(eb.ev.title || ""))
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          elide: Text.ElideRight
          wrapMode: eb.height >= root.sp(70) ? Text.WordWrap : Text.NoWrap
          maximumLineCount: eb.height >= root.sp(70) ? 2 : 1
        }
      }
      Text {
        visible: eb.roomy
        width: parent.width
        text: eb.ev.start + (eb.ev.end ? "–" + eb.ev.end : "") + (eb.ev.teams ? "  ·  Teams-Call" : "")
          + (eb.st === "now" ? "  ·  JETZT" : (eb.st === "future" && root.nextEv === eb.ev ? "  ·  " + root.untilText(eb.ev) : ""))
          + (typeof eb.ev.remind === "number" ? "  ·  " + root.glyph(0xF009A) + " " + root.remindText(eb.ev.remind) : "")
        color: Util.alpha(root.fg, 0.7)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
      Text {
        visible: eb.height >= root.sp(66) && !!eb.ev.info
        width: parent.width
        text: String(eb.ev.info || "")
        color: Util.alpha(root.fg, 0.5)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    MouseArea {
      id: ebMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.openEdit(eb.ev)
    }
  }
}
