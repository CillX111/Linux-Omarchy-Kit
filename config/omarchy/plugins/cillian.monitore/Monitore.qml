import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import qs.Commons
import qs.Ui

// Monitore anordnen (wie Windows: Anzeige -> Bildschirme neu anordnen).
// Kaestchen ziehen, beim Loslassen dockt der Monitor an den naechsten an.
// "Uebernehmen" setzt die Positionen live und speichert sie in monitors.lua.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false
  property var activeScreen: null

  // [{id,name,description,width,height,scale,transform,x,y,lw,lh,num}]
  property var mons: []
  property var original: []
  property int selected: 0
  property bool dirty: false
  property string status: ""
  property bool identifying: false

  // Zeichenflaeche
  readonly property real canvasW: Style.space(620)
  readonly property real canvasH: Style.space(300)
  property real factor: 0.05
  property real originX: 0
  property real originY: 0

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property var borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
  property string fontFamily: Style.font.menuFamily

  function resolveActiveScreen() {
    var focused = Hyprland.focusedMonitor ? String(Hyprland.focusedMonitor.name || "") : ""
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++)
      if (String(screens[i].name) === focused) return screens[i]
    return screens.length > 0 ? screens[0] : null
  }

  function open(payloadJson) {
    root.activeScreen = root.resolveActiveScreen()
    root.status = ""
    root.opened = true
    root.detect()
  }
  function close() { root.opened = false; root.identifying = false }
  function dismiss() {
    root.close()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "cillian.monitore")
  }

  function detect() { listProc.running = false; listProc.running = true }

  function parseList(text) {
    var arr = []
    try { arr = JSON.parse(text) } catch (e) { arr = [] }
    arr.sort(function(a, b) { return a.id - b.id })
    var out = []
    for (var i = 0; i < arr.length; i++) {
      var m = arr[i]
      var rot = (m.transform % 2) === 1
      var lw = Math.round((rot ? m.height : m.width) / m.scale)
      var lh = Math.round((rot ? m.width : m.height) / m.scale)
      out.push({ id: m.id, name: m.name, description: m.description, width: m.width, height: m.height,
                 scale: m.scale, x: m.x, y: m.y, lw: lw, lh: lh, num: i + 1, focused: m.focused })
    }
    root.original = JSON.parse(JSON.stringify(out))
    root.mons = out
    root.dirty = false
    if (root.selected >= out.length) root.selected = 0
    root.refit()
  }

  // Massstab so waehlen, dass alles in die Flaeche passt
  function refit() {
    var ms = root.mons
    if (ms.length === 0) return
    var minX = 1e9, minY = 1e9, maxX = -1e9, maxY = -1e9
    for (var i = 0; i < ms.length; i++) {
      minX = Math.min(minX, ms[i].x); minY = Math.min(minY, ms[i].y)
      maxX = Math.max(maxX, ms[i].x + ms[i].lw); maxY = Math.max(maxY, ms[i].y + ms[i].lh)
    }
    var bw = maxX - minX, bh = maxY - minY
    var f = Math.min((root.canvasW * 0.8) / bw, (root.canvasH * 0.8) / bh)
    root.factor = f
    root.originX = minX - (root.canvasW / f - bw) / 2
    root.originY = minY - (root.canvasH / f - bh) / 2
  }

  function overlaps(a, b) {
    return a.x < b.x + b.lw && a.x + a.lw > b.x && a.y < b.y + b.lh && a.y + a.lh > b.y
  }

  // Monitor idx wurde bei (px,py) (logische Pixel) losgelassen -> andocken
  function snap(idx, px, py) {
    var ms = JSON.parse(JSON.stringify(root.mons))
    var m = ms[idx]
    var others = ms.filter(function(o, i) { return i !== idx })
    if (others.length === 0) { m.x = 0; m.y = 0; root.mons = ms; return }
    var thr = Style.space(18) / root.factor
    function clampAlign(p, lo, hi, a1, a2) {
      p = Math.max(lo, Math.min(hi, p))
      if (Math.abs(p - a1) < thr) p = a1
      else if (Math.abs(p - a2) < thr) p = a2
      return p
    }
    var cands = []
    for (var i = 0; i < others.length; i++) {
      var o = others[i]
      var cy = clampAlign(py, o.y - m.lh + 1, o.y + o.lh - 1, o.y, o.y + o.lh - m.lh)
      var cx = clampAlign(px, o.x - m.lw + 1, o.x + o.lw - 1, o.x, o.x + o.lw - m.lw)
      cands.push({ x: o.x - m.lw, y: cy })
      cands.push({ x: o.x + o.lw, y: cy })
      cands.push({ x: cx, y: o.y - m.lh })
      cands.push({ x: cx, y: o.y + o.lh })
    }
    var best = null, bestD = 1e18
    for (var c = 0; c < cands.length; c++) {
      var t = { x: Math.round(cands[c].x), y: Math.round(cands[c].y), lw: m.lw, lh: m.lh }
      var bad = false
      for (var k = 0; k < others.length; k++) if (root.overlaps(t, others[k])) { bad = true; break }
      if (bad) continue
      var d = (t.x - px) * (t.x - px) + (t.y - py) * (t.y - py)
      if (d < bestD) { bestD = d; best = t }
    }
    if (best) { m.x = best.x; m.y = best.y }
    // nach oben links verschieben, damit nichts negativ ist
    var minX = 1e9, minY = 1e9
    for (var j = 0; j < ms.length; j++) { minX = Math.min(minX, ms[j].x); minY = Math.min(minY, ms[j].y) }
    for (j = 0; j < ms.length; j++) { ms[j].x -= minX; ms[j].y -= minY }
    root.mons = ms
    var changed = false
    for (j = 0; j < ms.length; j++)
      if (ms[j].x !== root.original[j].x || ms[j].y !== root.original[j].y) changed = true
    root.dirty = changed
    root.status = ""
    root.refit()
  }

  function apply() {
    var list = root.mons.map(function(m) { return { name: m.name, x: m.x, y: m.y } })
    applyProc.command = [Quickshell.env("HOME") + "/.local/bin/monitore-anordnen", "apply", JSON.stringify(list)]
    applyProc.running = true
  }

  function reset() {
    root.mons = JSON.parse(JSON.stringify(root.original))
    root.dirty = false
    root.status = ""
    root.refit()
  }

  function identify() { root.identifying = true; identifyTimer.restart() }

  function numFor(name) {
    for (var i = 0; i < root.mons.length; i++) if (root.mons[i].name === name) return root.mons[i].num
    return ""
  }

  Timer { id: identifyTimer; interval: 2500; onTriggered: root.identifying = false }

  Process {
    id: listProc
    command: [Quickshell.env("HOME") + "/.local/bin/monitore-anordnen", "list"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.parseList(String(text || "[]")) }
  }

  Process {
    id: applyProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.status = String(text || "").indexOf("ok") !== -1 ? "Gespeichert" : "Fehler beim Übernehmen"
        root.activeScreen = root.resolveActiveScreen()
        root.detect()
      }
    }
  }

  // Grosse Nummer auf jedem Bildschirm (Identifizieren)
  Variants {
    model: Quickshell.screens
    PanelWindow {
      required property var modelData
      screen: modelData
      visible: root.identifying
      anchors { bottom: true; left: true }
      margins { bottom: Style.space(40); left: Style.space(40) }
      implicitWidth: Style.space(180)
      implicitHeight: Style.space(180)
      color: "transparent"
      WlrLayershell.namespace: "cillian-monitore-id"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore
      Rectangle {
        anchors.fill: parent
        radius: Style.cornerRadius
        color: Qt.rgba(0.082, 0.078, 0.075, 0.70)
        border.color: Color.accent
        border.width: Style.space(3)
        Text {
          anchors.centerIn: parent
          text: root.numFor(String(modelData.name))
          color: "white"
          font.family: root.fontFamily
          font.pixelSize: Style.space(120)
          font.bold: true
        }
      }
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    screen: root.activeScreen
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "cillian-monitore"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(0, 0, 0, 0.22)
      MouseArea { anchors.fill: parent; onClicked: root.dismiss() }
    }

    BorderSurface {
      id: card
      anchors.centerIn: parent
      width: root.canvasW + card.contentLeftInset + card.contentRightInset
      height: content.implicitHeight + card.contentTopInset + card.contentBottomInset
      radius: Style.cornerRadius
      color: root.background
      borderSpec: root.borderSpec
      padding: Style.spacing.panelPadding

      MouseArea { anchors.fill: parent }  // Klicks nicht zum Hintergrund durchlassen

      Item {
        anchors.fill: parent
        focus: root.opened
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) { root.dismiss(); event.accepted = true }
          else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { if (root.dirty) root.apply(); event.accepted = true }
        }
      }

      Column {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: card.contentTopInset
        anchors.leftMargin: card.contentLeftInset
        anchors.rightMargin: card.contentRightInset
        spacing: Style.spacing.md

        Text {
          text: "Bildschirme neu anordnen"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
        }
        Text {
          width: parent.width
          wrapMode: Text.Wrap
          text: "Wähle unten einen Bildschirm aus. Halte ihn gedrückt und ziehe ihn, um die Bildschirme neu anzuordnen."
          color: Qt.darker(root.foreground, 1.3)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        // Zeichenflaeche mit den Monitoren
        Rectangle {
          id: canvas
          width: root.canvasW
          height: root.canvasH
          radius: Style.space(6)
          color: Qt.darker(root.background, 1.25)
          clip: true

          Repeater {
            model: root.mons
            delegate: Rectangle {
              id: tile
              required property var modelData
              required property int index
              property bool dragging: mouse.drag.active
              x: dragging ? x : (modelData.x - root.originX) * root.factor
              y: dragging ? y : (modelData.y - root.originY) * root.factor
              width: modelData.lw * root.factor
              height: modelData.lh * root.factor
              z: dragging ? 10 : (root.selected === index ? 5 : 1)
              color: root.selected === index ? Color.accent : Qt.lighter(root.background, 1.9)
              opacity: dragging ? 0.85 : 1
              border.color: root.selected === index ? Qt.lighter(Color.accent, 1.4) : Qt.darker(root.foreground, 2.2)
              border.width: Style.space(2)

              Text {
                anchors.centerIn: parent
                text: tile.modelData.num
                color: root.selected === tile.index ? root.background : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Math.min(tile.height * 0.45, Style.space(56))
              }
              Text {
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                anchors.margins: Style.space(5)
                text: tile.modelData.name
                color: root.selected === tile.index ? root.background : Qt.darker(root.foreground, 1.4)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              MouseArea {
                id: mouse
                anchors.fill: parent
                cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                drag.target: tile
                drag.threshold: 2
                onPressed: root.selected = tile.index
                onReleased: {
                  if (!drag.active && Math.abs(tile.x - (tile.modelData.x - root.originX) * root.factor) < 1) return
                  var px = tile.x / root.factor + root.originX
                  var py = tile.y / root.factor + root.originY
                  root.snap(tile.index, px, py)
                }
              }
            }
          }
        }

        // Info zum gewaehlten Monitor
        Text {
          width: parent.width
          elide: Text.ElideRight
          property var m: root.mons.length > root.selected ? root.mons[root.selected] : null
          text: m ? (m.num + "  " + m.name + "  " + m.description + "   " + m.width + "x" + m.height
                     + "   Skalierung " + Math.round(m.scale * 100) + "%   Position " + m.x + ", " + m.y) : ""
          color: Qt.darker(root.foreground, 1.3)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Item {
          width: parent.width
          height: buttons.implicitHeight

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: root.status
            color: Color.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Row {
            id: buttons
            anchors.right: parent.right
            spacing: Style.spacing.md

            Button { text: "Identifizieren"; bordered: true; foreground: root.foreground; fontFamily: root.fontFamily; onClicked: root.identify() }
            Button { text: "Erkennen"; bordered: true; foreground: root.foreground; fontFamily: root.fontFamily; onClicked: { root.status = ""; root.detect() } }
            Button { text: "Zurücksetzen"; bordered: true; foreground: root.foreground; fontFamily: root.fontFamily
                     enabled: root.dirty; opacity: enabled ? 1 : 0.4; onClicked: root.reset() }
            Button { text: "Übernehmen"; bordered: true; selected: root.dirty; foreground: root.foreground; fontFamily: root.fontFamily
                     enabled: root.dirty; opacity: enabled ? 1 : 0.4; onClicked: root.apply() }
            Button { text: "Schließen"; bordered: true; foreground: root.foreground; fontFamily: root.fontFamily; onClicked: root.dismiss() }
          }
        }
      }
    }
  }
}
