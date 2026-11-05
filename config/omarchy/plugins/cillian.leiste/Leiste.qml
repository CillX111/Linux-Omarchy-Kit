import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import qs.Commons

// Glas-Leiste: legt hinter die obere Omarchy-Leiste eine schwebende Glas-Kapsel
// im Stil des Startmenüs (cillian.start): dunkles Glas mit Hyprland-Blur
// (layer_rule "cillian-leiste" in looknfeel.lua), feiner Rand, Glanz oben,
// weicher Schatten/Lichtschein darunter. Alles steht still (ein Lichtlauf über
// den Rand war drin, hat den User abgelenkt -> entfernt 2026-11-05).
//
// Die Leiste selbst (Knöpfe, Symbole) bleibt Omarchys; sie liegt eine Ebene
// darüber (Layer "top"), diese Kapsel auf Layer "bottom" und nimmt keine
// Klicks an.
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property var bar: shell ? shell.bar : null
  readonly property bool showGlass: !bar || ((bar.position === undefined || bar.position === "top") && bar.barHidden !== true)
  readonly property int barSize: bar && bar.barSize > 0 ? bar.barSize : Style.bar.sizeHorizontal

  readonly property color bg: Color.menu.background
  readonly property color fg: Color.bar.text
  readonly property color glow: Color.foreground

  // Abstand der Kapsel zum Rand und Platz für den Schatten darunter
  readonly property int sideGap: Style.space(4)
  readonly property int vGap: Math.max(2, Math.round(barSize * 0.1))
  readonly property int shadowRoom: Style.space(22)

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: win
      required property var modelData

      screen: modelData
      visible: root.showGlass
      anchors { top: true; left: true; right: true }
      implicitHeight: root.barSize + root.shadowRoom
      exclusionMode: ExclusionMode.Ignore
      color: "transparent"
      surfaceFormat.opaque: false
      mask: Region {}
      WlrLayershell.namespace: "cillian-leiste"
      WlrLayershell.layer: WlrLayer.Bottom
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

      Item {
        id: holder
        x: root.sideGap
        y: root.vGap
        width: parent.width - root.sideGap * 2
        height: root.barSize - root.vGap * 2

        // weicher Schatten nach unten + leichter Lichtschein (wie beim Startmenü),
        // NUR aussen: unter dem Glas ausgeschnitten, sonst wirkt es schwarz
        Item {
          id: shadowBox
          anchors.fill: pill
          anchors.margins: -Style.space(40)
          layer.enabled: true
          layer.effect: MultiEffect {
            maskEnabled: true
            maskInverted: true
            maskSource: shadowCut
          }
          RectangularShadow {
            anchors.fill: parent
            anchors.margins: Style.space(40)
            anchors.topMargin: Style.space(40) + Style.space(5)
            radius: pill.radius
            blur: Style.space(18)
            color: Qt.rgba(0, 0, 0, 0.38)
          }
          RectangularShadow {
            anchors.fill: parent
            anchors.margins: Style.space(40)
            radius: pill.radius
            blur: Style.space(24)
            spread: 1
            color: Util.alpha(root.glow, 0.08)
          }
        }
        Item {
          id: shadowCut
          anchors.fill: shadowBox
          visible: false
          layer.enabled: true
          Rectangle {
            anchors.fill: parent
            anchors.margins: Style.space(40)
            radius: pill.radius
            color: "black"
          }
        }

        Rectangle {
          id: pill
          anchors.fill: parent
          radius: height / 2
          // Glas-Stil Option A (wie shell.toml): Graphit 0.70, Rand 0.14, Glanz 0.06
          color: Util.alpha(root.bg, 0.70)
          border.width: 1
          border.color: Util.alpha(root.fg, 0.14)

          // Glas: oben heller, unten dunkler
          Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: pill.radius - 1
            gradient: Gradient {
              GradientStop { position: 0.0; color: Util.alpha(root.fg, 0.06) }
              GradientStop { position: 1.0; color: "transparent" }
            }
          }
        }

        // Licht auf dem Rand wie beim Startmenü, aber STILL: helle Enden links
        // und rechts (der User mag keine bewegten Effekte in der Leiste)
        Item {
          anchors.fill: pill
          layer.enabled: true
          layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: rimMask
          }
          Rectangle {
            anchors.fill: parent
            gradient: Gradient {
              orientation: Gradient.Horizontal
              GradientStop { position: 0.0; color: Util.alpha(root.glow, 0.75) }
              GradientStop { position: 0.035; color: "transparent" }
              GradientStop { position: 0.965; color: "transparent" }
              GradientStop { position: 1.0; color: Util.alpha(root.glow, 0.75) }
            }
          }
        }
        Item {
          id: rimMask
          anchors.fill: pill
          visible: false
          layer.enabled: true
          Rectangle {
            anchors.fill: parent
            radius: pill.radius
            color: "transparent"
            border.width: 1.5
            border.color: "black"
          }
        }

        // Lichtkante oben in der Mitte (wie Licht auf Glas), steht still
        Rectangle {
          x: pill.radius
          y: 0
          width: pill.width - pill.radius * 2
          height: 1
          opacity: 0.55
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.5; color: Util.alpha(root.fg, 0.7) }
            GradientStop { position: 1.0; color: "transparent" }
          }
        }
      }
    }
  }
}
