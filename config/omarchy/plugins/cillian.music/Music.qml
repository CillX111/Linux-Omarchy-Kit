import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Mpris
import Quickshell.Hyprland
import QtQuick
import qs.Commons
import qs.Ui

// Musik-Panel (Page_Up): zeigt das laufende Lied (Cover, Titel, Interpret,
// Album, Fortschritt) mit den Knoepfen Zurueck, Play/Pause, Weiter, Stopp.
//
// Das Panel bleibt offen, bis Page_Up es wieder schliesst. Es nimmt weder
// Tastatur noch Maus ausserhalb seiner Flaeche in Anspruch.
Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  // Bildschirm, auf dem das Panel liegt (der von Hyprland fokussierte)
  property var activeScreen: null

  // Alle MPRIS-Player (Spotify, Browser, mpv, ...)
  readonly property var players: Mpris.players ? Mpris.players.values : []
  readonly property var player: pickPlayer()

  readonly property bool hasMedia: player !== null && (player.trackTitle || player.trackArtist)
  readonly property string title: player ? (player.trackTitle || "") : ""
  readonly property string artist: player ? (player.trackArtist || "") : ""
  readonly property string album: player && player.trackAlbum ? player.trackAlbum : ""
  readonly property string artUrl: player && player.trackArtUrl ? player.trackArtUrl : ""
  readonly property string appName: player ? (player.identity || player.desktopEntry || "") : ""
  readonly property bool playing: player ? !!player.isPlaying : false

  // Fortschritt: position/length sind Sekunden, position wird nur bei
  // geoeffnetem Panel per Timer aktualisiert.
  property real position: 0
  readonly property real length: player && player.length > 0 ? player.length : 0

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int cardWidth: Style.space(440)

  // Spielender Player zuerst, sonst der erste mit Titel, sonst der erste
  // steuerbare.
  function pickPlayer() {
    var list = root.players
    var withTrack = null
    var controllable = null
    for (var i = 0; i < list.length; i++) {
      var p = list[i]
      if (!p) continue
      var proxy = String(p.dbusName || "").indexOf("playerctld") !== -1
      if (proxy) continue
      if (p.isPlaying) return p
      if (!withTrack && (p.trackTitle || p.trackArtist)) withTrack = p
      if (!controllable && (p.canPlay || p.canPause || p.canTogglePlaying)) controllable = p
    }
    return withTrack || controllable || (list.length > 0 ? list[0] : null)
  }

  function refreshPosition() {
    if (!root.player) { root.position = 0; return }
    if (root.player.positionSupported) root.position = root.player.position
    else root.position = 0
  }

  function fmtTime(seconds) {
    var s = Math.max(0, Math.floor(seconds))
    var m = Math.floor(s / 60)
    var r = s % 60
    return m + ":" + (r < 10 ? "0" : "") + r
  }

  // Der von Hyprland fokussierte Bildschirm, sonst der erste.
  function resolveActiveScreen() {
    var focused = Hyprland.focusedMonitor ? String(Hyprland.focusedMonitor.name || "") : ""
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++)
      if (String(screens[i].name) === focused) return screens[i]
    return screens.length > 0 ? screens[0] : null
  }

  function open(payloadJson) {
    root.activeScreen = root.resolveActiveScreen()
    root.opened = true
    root.refreshPosition()
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "cillian.music")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function previous() {
    if (root.player && root.player.canGoPrevious) root.player.previous()
  }

  function next() {
    if (root.player && root.player.canGoNext) root.player.next()
  }

  function playPause() {
    var p = root.player
    if (!p) return
    if (p.canTogglePlaying) p.togglePlaying()
    else if (p.isPlaying && p.canPause) p.pause()
    else if (!p.isPlaying && p.canPlay) p.play()
  }

  function stop() {
    var p = root.player
    if (!p) return
    if (p.canControl) p.stop()
    else if (p.canPause) p.pause()
  }

  Timer {
    interval: 500
    running: root.opened
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshPosition()
  }

  PanelWindow {
    id: panel
    visible: root.opened
    screen: root.activeScreen
    // Nur so gross wie die Karte, unten links mit Fensterabstand. Alles
    // daneben bleibt frei bedienbar.
    anchors { bottom: true; left: true }
    margins { bottom: Style.gapsOut * 2; left: Style.gapsOut * 2 }
    implicitWidth: card.width
    implicitHeight: card.height
    color: "transparent"
    WlrLayershell.namespace: "cillian-music"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    BorderSurface {
      id: card
      width: root.cardWidth
      height: content.implicitHeight + card.contentTopInset + card.contentBottomInset
      radius: root.cornerRadius
      anchors.left: parent.left
      anchors.top: parent.top
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      // Glanz oben (Glas-Stil wie Startmenü)
      Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: Math.max(0, card.radius - 1)
        gradient: Gradient {
          GradientStop { position: 0.0; color: Util.alpha(root.foreground, 0.06) }
          GradientStop { position: 0.6; color: "transparent" }
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

        // Kopf: Cover + Text
        Row {
          width: parent.width
          spacing: Style.spacing.md

          BorderSurface {
            id: cover
            width: Style.space(96)
            height: Style.space(96)
            radius: Style.spacing.labelGap
            color: Style.normalFillFor(root.foreground, Color.accent)
            borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)

            Image {
              anchors.fill: parent
              anchors.margins: Style.space(2)
              fillMode: Image.PreserveAspectCrop
              asynchronous: true
              source: root.artUrl
              visible: root.artUrl !== ""
            }

            Text {
              anchors.centerIn: parent
              visible: root.artUrl === ""
              text: "󰝚"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge
            }
          }

          Column {
            width: parent.width - cover.width - parent.spacing
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(4)

            Text {
              textFormat: Text.PlainText
              text: root.hasMedia ? root.title : (root.player ? "Nichts am Laufen" : "Kein Player offen")
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
              maximumLineCount: 2
              wrapMode: Text.Wrap
            }

            Text {
              textFormat: Text.PlainText
              text: root.artist
              color: Qt.darker(root.foreground, 1.3)
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              elide: Text.ElideRight
              width: parent.width
              visible: text !== ""
            }

            Text {
              textFormat: Text.PlainText
              text: root.album
              color: Qt.darker(root.foreground, 1.6)
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
              width: parent.width
              visible: text !== ""
            }

            Text {
              textFormat: Text.PlainText
              text: root.appName
              color: Qt.darker(root.foreground, 1.8)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
              width: parent.width
              visible: text !== ""
            }
          }
        }

        // Fortschrittsbalken
        Column {
          width: parent.width
          spacing: Style.space(4)
          visible: root.length > 0

          Rectangle {
            width: parent.width
            height: Style.space(4)
            radius: height / 2
            color: Qt.darker(root.foreground, 3.0)

            Rectangle {
              width: root.length > 0 ? parent.width * Math.min(1, root.position / root.length) : 0
              height: parent.height
              radius: height / 2
              color: Color.accent
              Behavior on width { NumberAnimation { duration: 300 } }
            }
          }

          Item {
            width: parent.width
            height: timeLeft.implicitHeight

            Text {
              id: timeLeft
              textFormat: Text.PlainText
              anchors.left: parent.left
              text: root.fmtTime(root.position)
              color: Qt.darker(root.foreground, 1.6)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Text {
              textFormat: Text.PlainText
              anchors.right: parent.right
              text: root.fmtTime(root.length)
              color: Qt.darker(root.foreground, 1.6)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        // Knoepfe
        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(10)

          Button {
            iconText: "󰒮"
            tooltipText: "Zurueck"
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconSize: Style.font.iconLarge
            horizontalPadding: Style.spacing.panelGap
            verticalPadding: Style.spacing.controlPaddingY
            enabled: root.player && root.player.canGoPrevious
            opacity: enabled ? 1.0 : 0.4
            onClicked: root.previous()
          }

          Button {
            iconText: root.playing ? "󰏤" : "󰐊"
            tooltipText: root.playing ? "Pause" : "Play"
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconSize: Style.font.displayLarge
            horizontalPadding: Style.spacing.panelGap
            verticalPadding: Style.spacing.controlPaddingY
            bordered: true
            enabled: root.player && (root.player.canTogglePlaying || root.player.canPlay || root.player.canPause)
            opacity: enabled ? 1.0 : 0.4
            onClicked: root.playPause()
          }

          Button {
            iconText: "󰒭"
            tooltipText: "Weiter"
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconSize: Style.font.iconLarge
            horizontalPadding: Style.spacing.panelGap
            verticalPadding: Style.spacing.controlPaddingY
            enabled: root.player && root.player.canGoNext
            opacity: enabled ? 1.0 : 0.4
            onClicked: root.next()
          }

          Button {
            iconText: "󰓛"
            tooltipText: "Stopp"
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconSize: Style.font.iconLarge
            horizontalPadding: Style.spacing.panelGap
            verticalPadding: Style.spacing.controlPaddingY
            enabled: root.player && (root.player.canControl || root.player.canPause)
            opacity: enabled ? 1.0 : 0.4
            onClicked: root.stop()
          }
        }

        Text {
          textFormat: Text.PlainText
          anchors.horizontalCenter: parent.horizontalCenter
          text: "Page_Up schliessen"
          color: Qt.darker(root.foreground, 2.0)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
