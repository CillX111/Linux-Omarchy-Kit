import QtQuick
import QtQuick.Controls
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Panel {
  id: root
  moduleName: "omarchy.agents"
  ipcTarget: "omarchy.agents"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color dim2: Qt.darker(foreground, 2.3)
  // Variante B (cillian): Claude-Orange als einziger Farbtupfer, eigenes Rot
  // fuer Alarm (das Theme-"urgent" ist bei Vantablack grau).
  readonly property color claudeOrange: "#D97757"
  readonly property color claudeOrangeLight: "#f0b39b"
  readonly property color alarmColor: "#e5484d"
  readonly property color surface: Commons.Color.popups.background
  readonly property color track: Style.selectedFillFor(foreground, Commons.Color.accent)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property var providers: usage.enabledProviders
  // The selection follows the provider, not the slot it happens to sit in: a
  // provider whose first scan lands while the panel is open would otherwise
  // shift the list underneath you and swap out what you were reading.
  property string selectedProviderId: ""
  readonly property int providerIndex: {
    for (var i = 0; i < providers.length; i++)
      if (providers[i].providerId === selectedProviderId) return i
    return 0
  }
  readonly property var provider: providers.length > 0 ? providers[providerIndex] : null

  property bool cursorActive: false

  // Countdowns and "updated" read this instead of Date.now() so the
  // panel keeps telling the truth while it sits open.
  property double nowMs: Date.now()

  readonly property var limits: limitWindows(provider)
  readonly property var allModels: modelRows(provider, 0)
  readonly property var models: allModels.slice(0, 4)
  readonly property var headline: bindingWindow(provider)
  readonly property var balance: provider ? (provider.balance || null) : null
  // A prepaid account runs low the way a subscription window fills up: the
  // last 10% of the funded credits lights the same alarm.
  readonly property bool balanceAlarming: !!balance && balance.funded > 0
    && balance.remaining / balance.funded <= 0.1
  readonly property bool alarming: (!!headline && headline.percent >= 0.9) || balanceAlarming

  // Leisten-Ring (cillian): fuellt sich mit dem Session-Fenster; ohne Session
  // nimmt er das vollste Fenster. Ab 90 % in der Warnfarbe.
  readonly property var sessionWindow: sessionWin || headline
  readonly property real ringValue: sessionWindow ? clamp(sessionWindow.percent, 0, 1) : 0

  // Panel-Ringe (Variante B): aussen Session, innen Woche.
  readonly property var sessionWin: findWindow("Session")
  readonly property var weekWin: findWindow("Weekly")
  readonly property real sessionValue: sessionWin ? clamp(sessionWin.percent, 0, 1) : 0
  readonly property real weekValue: weekWin ? clamp(weekWin.percent, 0, 1) : 0
  readonly property real sessionElapsed: elapsedFraction(sessionWin)
  readonly property real weekElapsed: elapsedFraction(weekWin)
  readonly property bool sessionAlarming: !!sessionWindow && sessionWindow.percent >= 0.9
  readonly property bool weekAlarming: !!weekWin && weekWin.percent >= 0.9
  readonly property var legendRows: buildLegend(limits)

  function findWindow(title) {
    for (var i = 0; i < limits.length; i++)
      if (limits[i].title === title) return limits[i]
    return null
  }

  function elapsedFraction(w) {
    if (!w || !(w.span > 0)) return -1
    var remaining = resetMsFor(w)
    if (!(remaining > 0)) return -1
    return clamp(1 - remaining / w.span, 0, 1)
  }

  function css(c) {
    return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + ","
      + Math.round(c.b * 255) + "," + c.a + ")"
  }

  function hex(c) {
    function two(v) { var h = Math.round(v * 255).toString(16); return h.length < 2 ? "0" + h : h }
    return "#" + two(c.r) + two(c.g) + two(c.b)
  }

  function pad2(n) { return (n < 10 ? "0" : "") + n }

  function clockOf(ms) {
    var d = new Date(Math.round(ms / 60000) * 60000)
    return pad2(d.getHours()) + ":" + pad2(d.getMinutes())
  }

  function clockText(iso) {
    var ms = new Date(String(iso || "")).getTime()
    return isFinite(ms) ? clockOf(ms) : ""
  }

  readonly property var dayNamesDe: ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"]

  function dayNameDe(date) {
    var parsed = new Date(String(date || "") + "T00:00:00")
    return isNaN(parsed.getTime()) ? String(date || "") : dayNamesDe[parsed.getDay()]
  }

  function inText(ms) {
    var minutes = Math.max(1, Math.round(ms / 60000))
    var hours = Math.floor(minutes / 60)
    var days = Math.floor(hours / 24)
    if (days > 0) return days + " T " + (hours % 24) + " h"
    if (hours > 0) return hours + " h " + pad2(minutes % 60)
    return minutes + " min"
  }

  function resetCaption(w, withCountdown) {
    if (!w || w.resetAt === "") return ""
    var ms = new Date(w.resetAt).getTime()
    if (!isFinite(ms)) return ""
    var at = new Date(Math.round(ms / 60000) * 60000)
    var now = new Date(root.nowMs)
    var sameDay = at.toDateString() === now.toDateString()
    var text = "neu " + (sameDay ? "um " : dayNamesDe[at.getDay()] + " ") + clockOf(ms)
    if (withCountdown && resetMsFor(w) > 0) text += " · in " + inText(resetMsFor(w))
    return text
  }

  function titleDe(title) {
    var t = String(title || "")
    if (t === "Weekly") return "Woche"
    if (t === "Monthly") return "Monat"
    if (/ Weekly$/.test(t)) return t.replace(/ Weekly$/, "-Woche")
    if (/ Monthly$/.test(t)) return t.replace(/ Monthly$/, "-Monat")
    return t
  }

  function buildLegend(windows) {
    var rows = []
    var dim2Hex = hex(root.dim2)
    function add(w, dot, dotColor, countdown, caption) {
      rows.push({
        title: titleDe(w.title),
        percentText: Math.round(Number(w.percent) * 100) + " %",
        dot: dot,
        dotColor: dotColor,
        caption: caption ? resetCaption(w, countdown) : ""
      })
    }
    if (sessionWin) add(sessionWin, "●", sessionAlarming ? hex(alarmColor) : hex(claudeOrange), true, true)
    if (weekWin) add(weekWin, "●", weekAlarming ? hex(alarmColor) : hex(claudeOrangeLight), false, true)
    for (var i = 0; i < windows.length; i++)
      if (windows[i] !== sessionWin && windows[i] !== weekWin) add(windows[i], "○", dim2Hex, false, false)
    return rows
  }

  function modelColor(index) {
    if (index === 0) return claudeOrange
    if (index === 1) return claudeOrangeLight
    if (index === 2) return alpha(foreground, 0.45)
    if (index === 3) return alpha(foreground, 0.25)
    return alpha(foreground, 0.14)
  }

  // "84 M" in den Kacheln, "849M" ueber den Saeulen.
  function tileTokens(n) {
    if (n >= 1e9) return (n / 1e9).toFixed(1).replace(".", ",") + " Mrd"
    if (n >= 1e6) return Math.round(n / 1e6) + " M"
    if (n >= 1e3) return Math.round(n / 1e3) + " K"
    return String(n)
  }

  function columnTokens(n) {
    if (n >= 1e9) return (n / 1e9).toFixed(1).replace(".", ",") + "Mrd"
    if (n >= 1e6) return Math.round(n / 1e6) + "M"
    if (n >= 1e3) return Math.round(n / 1e3) + "K"
    return String(n)
  }

  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }
  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

  function selectProvider(index) {
    if (providers.length === 0) return
    var wrapped = ((index % providers.length) + providers.length) % providers.length
    selectedProviderId = providers[wrapped].providerId
  }

  function refreshNow() {
    usage.refreshAll(true)
  }

  function launchAgent() {
    if (root.bar) root.bar.run("omarchy-agent --pick")
    root.close()
  }

  // ---------------------------------------------------------------- limits
  //
  // Both providers report the same two shapes: a short rolling session window
  // and a long weekly one. Everything below normalizes them into one record so
  // the meters and the hero speak a single language.

  // Claude spells its windows out ("Session (5-hour)"), Codex abbreviates
  // them ("5h window", "30m window"). Both have to land on the same record.
  function windowIsLong(text) {
    return text.indexOf("week") >= 0 || text.indexOf("7-day") >= 0 || text.indexOf("seven") >= 0
      || text.indexOf("month") >= 0 || text.indexOf("30-day") >= 0
  }

  function windowSpanMs(label) {
    var text = String(label || "").toLowerCase()
    if (text.indexOf("month") >= 0 || text.indexOf("30-day") >= 0) return 30 * 24 * 3600 * 1000
    if (windowIsLong(text)) return 7 * 24 * 3600 * 1000
    var hours = text.match(/(\d+)\s*-?\s*h(?:our)?\b/)
    if (hours) return Number(hours[1]) * 3600 * 1000
    var minutes = text.match(/(\d+)\s*-?\s*m(?:in(?:ute)?s?)?\b/)
    if (minutes) return Number(minutes[1]) * 60 * 1000
    return 0
  }

  function windowTitle(label) {
    var text = String(label || "").toLowerCase()
    if (text.indexOf("month") >= 0) return "Monthly"
    if (windowIsLong(text)) return "Weekly"
    if (text.indexOf("session") >= 0 || windowSpanMs(label) > 0) return "Session"
    var plain = String(label || "").replace(/\s*\(.*\)\s*/, "").trim()
    return plain === "" ? "Limit" : plain
  }

  // A collector that already knows which window a limit belongs to says so,
  // and that beats reading it back out of the label: a model-scoped limit is
  // titled after its model, and a name like "Opus 5 (1M context)" would parse
  // as a one-minute window.
  function limitWindow(label, percent, resetAt, title) {
    var reset = new Date(String(resetAt || "")).getTime()
    var expired = isFinite(reset) && reset <= root.nowMs
    return {
      title: String(title || "") !== "" ? String(title) : windowTitle(label),
      span: windowSpanMs(label),
      percent: expired ? 0 : Number(percent),
      resetAt: expired ? "" : String(resetAt || "")
    }
  }

  function limitWindows(p) {
    if (!p) return []
    var out = []
    var list = p.limits || []
    for (var i = 0; i < list.length; i++) {
      var entry = list[i] || {}
      var percent = Number(entry.percent)
      if (percent >= 0) out.push(limitWindow(entry.label, percent, entry.resetsAt, entry.title))
    }
    return out
  }

  // The window that decides how much room is left — the fullest one, since
  // that is what stops the next prompt.
  function bindingWindow(p) {
    var windows = limitWindows(p)
    var best = null
    for (var i = 0; i < windows.length; i++) {
      if (!best || windows[i].percent > best.percent) best = windows[i]
    }
    return best
  }

  function resetMsFor(w) {
    if (!w || w.resetAt === "") return -1
    var ms = new Date(w.resetAt).getTime()
    return isFinite(ms) ? ms - root.nowMs : -1
  }

  function formatDuration(ms) {
    if (!(ms > 0)) return "now"
    var minutes = Math.floor(ms / 60000)
    var hours = Math.floor(minutes / 60)
    var days = Math.floor(hours / 24)
    if (days > 0) return days + "d " + (hours % 24) + "h"
    if (hours > 0) return hours + "h " + (minutes % 60) + "m"
    return Math.max(1, minutes) + "m"
  }

  // ---------------------------------------------------------------- balance
  //
  // Prepaid agents report a credit ledger instead of rate-limit windows: the
  // record's balance object carries remaining, funded, and spent amounts.

  function currencyPrefix(currency) {
    var code = String(currency || "USD").toUpperCase()
    if (code === "USD") return "$"
    if (code === "EUR") return "€"
    if (code === "GBP") return "£"
    return code + " "
  }

  function formatMoney(value, currency) {
    var amount = Number(value)
    if (!isFinite(amount)) amount = 0
    return currencyPrefix(currency) + amount.toFixed(2)
  }

  function balanceDetailText(b) {
    if (!b || !(b.funded > 0)) return ""
    var text = formatMoney(b.spent, b.currency) + " spent of " + formatMoney(b.funded, b.currency) + " funded"
    if (b.estimated) text += " · estimated"
    return text
  }

  // ---------------------------------------------------------------- content

  // The plan you pay for, under the name of the tool it pays for. Limits live
  // in their own section; the hero just says what this is.
  function heroMeta(p) {
    if (!p) return ""
    if (String(p.usageStatusText || "") !== "") return p.usageStatusText
    var tier = String(p.tierLabel || "")
    if (tier === "") return "Subscription"
    return tier.charAt(0).toUpperCase() + tier.slice(1)
  }

  // Local calendar date, recomputed from nowMs so a panel left open across
  // midnight moves the "Today" row with the clock.
  function todayDate() {
    var now = new Date(root.nowMs)
    return now.getFullYear()
      + "-" + String(now.getMonth() + 1).padStart(2, "0")
      + "-" + String(now.getDate()).padStart(2, "0")
  }

  function dayName(date) {
    var parsed = new Date(String(date || "") + "T00:00:00")
    if (isNaN(parsed.getTime())) return String(date || "")
    return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][parsed.getDay()]
  }

  function dayLabel(date, today) {
    if (today) return "Today"
    return dayName(date)
  }

  function dayTooltip(day, today) {
    if (!day) return ""
    var parsed = new Date(String(day.date) + "T00:00:00")
    var label = isNaN(parsed.getTime())
      ? String(day.date)
      : dayNameDe(day.date) + " " + parsed.getDate() + "." + (parsed.getMonth() + 1) + "."
    var text = label + " · " + usage.formatTokenCount(Number(day.messageCount || 0)) + " Tokens"
    // Prompt and session counts only exist for today, so they ride along here
    // instead of taking a section of their own. Billing-API agents never
    // count prompts, and "0 prompts" would read as a quiet day, not a gap.
    if (today && provider && provider.hasPromptStats !== false)
      text += " · " + Number(provider.todayPrompts || 0) + " Prompts · "
        + Number(provider.todaySessions || 0) + " Sessions"
    return text
  }

  function weekPeak(p) {
    var days = p ? (p.recentDays || []) : []
    var peak = 0
    for (var i = 0; i < days.length; i++) peak = Math.max(peak, Number(days[i].messageCount || 0))
    return peak
  }

  function modelRows(p, limit) {
    var usageByModel = p ? (p.modelUsage || {}) : {}
    var rows = []
    for (var id in usageByModel) {
      var bucket = usageByModel[id] || {}
      var input = Number(bucket.inputTokens || 0)
      var output = Number(bucket.outputTokens || 0)
      var cacheRead = Number(bucket.cacheReadInputTokens || 0)
      var cacheWrite = Number(bucket.cacheCreationInputTokens || 0)
      rows.push({
        name: usage.friendlyModelName(id),
        total: input + output + cacheRead + cacheWrite,
        input: input,
        output: output,
        cacheRead: cacheRead,
        cacheWrite: cacheWrite
      })
    }
    rows.sort(function(a, b) { return b.total - a.total })
    var sum = 0
    for (var j = 0; j < rows.length; j++) sum += rows[j].total
    for (var k = 0; k < rows.length; k++) rows[k].share = sum > 0 ? rows[k].total / sum : 0
    return limit > 0 ? rows.slice(0, limit) : rows
  }

  function modelTooltip(row) {
    if (!row) return ""
    return "In " + usage.formatTokenCount(row.input)
      + " · out " + usage.formatTokenCount(row.output)
      + " · cache read " + usage.formatTokenCount(row.cacheRead)
      + " · cache write " + usage.formatTokenCount(row.cacheWrite)
  }

  // Only speaks up when the numbers cover more than this machine.
  function footerText() {
    if (usage.syncStatusText !== "") return usage.syncStatusText
    if (provider && provider.syncEnabled && provider.syncDeviceCount > 0)
      return "Merged from " + provider.syncDeviceCount + " device" + (provider.syncDeviceCount === 1 ? "" : "s")
    return ""
  }

  // Agents that ship a white mark carry an `assets/<id>-light.svg` twin for
  // light surfaces; marks that work on both (Claude's brand-orange) ship one
  // file. The luminance check decides which candidate to try first.
  function colorChannelLuminance(value) {
    var channel = Number(value)
    if (!isFinite(channel)) return 0
    return channel <= 0.03928 ? channel / 12.92 : Math.pow((channel + 0.055) / 1.055, 2.4)
  }

  function colorLuminance(color) {
    return 0.2126 * colorChannelLuminance(color.r)
      + 0.7152 * colorChannelLuminance(color.g)
      + 0.0722 * colorChannelLuminance(color.b)
  }

  // Marks resolve by convention, so a new agent's data file needs nothing
  // from this panel: assets/<id>.svg if it ships one, the module's bar glyph
  // if it doesn't.
  function iconCandidatesForProvider(p, surfaceColor) {
    if (!p) return []
    var candidates = []
    if (colorLuminance(surfaceColor || Commons.Color.background) >= 0.5)
      candidates.push(Qt.resolvedUrl("assets/" + p.providerId + "-light.svg"))
    candidates.push(Qt.resolvedUrl("assets/" + p.providerId + ".svg"))
    return candidates
  }

  // Nothing to report, nothing in the bar: Bar.qml collapses a slot whose item
  // is invisible, so the icon appears the moment the first scan finds usage and
  // stays away entirely on a machine that has never run either CLI.
  visible: providers.length > 0
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onProviderIndexChanged: if (panelFlick) panelFlick.contentY = 0
  onOpenedChanged: if (opened) {
    cursorActive = false
    nowMs = Date.now()
    if (panelFlick) panelFlick.contentY = 0
    usage.refreshLimits()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Main {
    id: usage
    settings: root.settings
  }

  // Cheap enough to keep running: it only re-evaluates text bindings, and a
  // stale "resets in 2h" on a panel that is open is worse than a timer.
  Timer {
    interval: 30000
    running: root.opened
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  // Der Ring sitzt dauernd in der Leiste: Uhr jede Minute nachziehen (damit ein
  // abgelaufenes Fenster auf 0 faellt) und die Limits alle 5 Minuten holen.
  // "limits" fragt nur den Server, ohne alle Transkripte neu zu lesen.
  Timer {
    interval: 60000
    running: !root.opened
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  Timer {
    interval: 300000
    running: root.providers.length > 0
    repeat: true
    onTriggered: if (root.provider) usage.runUpdate("limits", [root.provider.providerId])
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refreshNow(); return "ok" }
    function next(): string { root.selectProvider(root.providerIndex + 1); return "ok" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󱚣"
    active: root.alarming
    iconComponent: Component { RingMark {} }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.launchAgent()
      else if (buttonCode === Qt.MiddleButton) root.selectProvider(root.providerIndex + 1)
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    // Taller than the control panels on purpose: this one is a dashboard, and
    // the whole point is reading limits and history without scrolling.
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onMoveRequested: function(dx, dy) {
        if (dx !== 0) {
          root.cursorActive = true
          root.selectProvider(root.providerIndex + dx)
        }
        if (dy !== 0)
          panelFlick.contentY = root.clamp(panelFlick.contentY + dy * Style.space(56), 0,
                                           Math.max(0, panelFlick.contentHeight - panelFlick.height))
      }
      onActivateRequested: root.refreshNow()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) { if (t === "r" || t === "R") root.refreshNow() }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          // ---------- Kopf: Stern · Name · Plan · Stand (cillian, Variante B) ----------
          Item {
            id: head
            visible: !!root.provider
            width: parent.width
            implicitHeight: Math.max(headMark.height, headName.implicitHeight)

            Image {
              id: headMark
              width: Style.space(22)
              height: width
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              source: root.provider ? Qt.resolvedUrl("assets/" + root.provider.providerId + ".svg") : ""
              sourceSize.width: width * 2
              sourceSize.height: height * 2
              fillMode: Image.PreserveAspectFit
            }

            Text {
              anchors.centerIn: headMark
              visible: headMark.status !== Image.Ready
              text: button.text
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
            }

            Text {
              id: headName
              textFormat: Text.PlainText
              anchors.left: headMark.right
              anchors.leftMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              text: root.provider ? String(root.provider.providerName).replace(/ Code$/, "") : ""
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              textFormat: Text.PlainText
              anchors.left: headName.right
              anchors.right: headTime.left
              anchors.rightMargin: Style.space(8)
              anchors.baseline: headName.baseline
              text: " · " + root.heroMeta(root.provider)
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }

            Text {
              id: headTime
              textFormat: Text.PlainText
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: root.provider ? root.clockText(root.provider.updatedAt) : ""
              color: root.dim2
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Text {
            visible: root.providers.length === 0
            width: parent.width
            topPadding: Style.space(24)
            text: "Noch keine Nutzung gefunden.\nDie Anzeige erscheint, sobald Claude benutzt wurde."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
          }

          // ---------- Provider switch ----------
          Row {
            id: providerSwitch
            visible: root.providers.length > 1
            width: parent.width
            spacing: Style.spacing.md

            readonly property real cellWidth: root.providers.length > 0
              ? (width - spacing * (root.providers.length - 1)) / root.providers.length
              : 0

            Repeater {
              model: root.providers

              Button {
                required property var modelData
                required property int index

                width: providerSwitch.cellWidth
                text: modelData.providerName
                selected: index === root.providerIndex
                hasCursor: root.cursorActive && index === root.providerIndex
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                verticalPadding: Style.spacing.controlPaddingY
                onClicked: {
                  root.cursorActive = true
                  root.selectProvider(index)
                }
                onHovered: function(isHovered) { if (isHovered) root.cursorActive = true }
              }
            }
          }

          // ---------- Status ----------
          BorderSurface {
            visible: !!root.provider && String(root.provider.usageStatusText || "") !== ""
            width: parent.width
            implicitHeight: statusText.implicitHeight + Style.spacing.xl * 2
            color: root.alpha(root.urgent, 0.10)
            borderSpec: Border.flat(root.alpha(root.urgent, 0.35), 1)
            radius: Style.cornerRadius

            Text {
              id: statusText
              textFormat: Text.PlainText
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(12)
              text: root.provider ? String(root.provider.authHelpText || "") : ""
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          // ---------- Ringe: aussen Session, innen Woche ----------
          Item {
            id: ringSection
            visible: root.limits.length > 0
            width: parent.width
            implicitHeight: ringBox.height + Style.space(6)

            Item {
              id: ringBox
              width: Style.space(150)
              height: width
              anchors.left: parent.left
              anchors.top: parent.top
              anchors.topMargin: Style.space(4)

              Canvas {
                id: ringCanvas
                anchors.fill: parent
                antialiasing: true

                property var paintKey: [root.sessionValue, root.weekValue, root.sessionElapsed, root.weekElapsed,
                  root.sessionAlarming, root.weekAlarming, String(root.foreground)]
                onPaintKeyChanged: requestPaint()

                onPaint: {
                  var ctx = getContext("2d")
                  ctx.reset()
                  var S = width
                  var c = S / 2
                  var rings = [
                    { r: S * 0.44, w: S * 0.0733, v: root.sessionValue, e: root.sessionElapsed,
                      color: root.sessionAlarming ? root.alarmColor : root.claudeOrange },
                    { r: S * 0.34, w: S * 0.06, v: root.weekValue, e: root.weekElapsed,
                      color: root.weekAlarming ? root.alarmColor : root.claudeOrangeLight }
                  ]
                  for (var i = 0; i < rings.length; i++) {
                    var ring = rings[i]
                    ctx.lineWidth = ring.w
                    ctx.lineCap = "butt"
                    ctx.strokeStyle = root.css(root.alpha(root.foreground, 0.1))
                    ctx.beginPath()
                    ctx.arc(c, c, ring.r, 0, 2 * Math.PI)
                    ctx.stroke()
                    if (ring.v > 0) {
                      ctx.lineCap = "round"
                      ctx.strokeStyle = root.css(ring.color)
                      ctx.beginPath()
                      ctx.arc(c, c, ring.r, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * Math.max(0.02, ring.v))
                      ctx.stroke()
                    }
                    // Weisser Strich = so viel Zeit des Fensters ist schon um.
                    if (ring.e >= 0) {
                      var a = -Math.PI / 2 + 2 * Math.PI * ring.e
                      var r0 = ring.r - ring.w / 2 - 0.5
                      var r1 = ring.r + ring.w / 2 + 0.5
                      ctx.lineCap = "butt"
                      ctx.lineWidth = Math.max(2, Style.space(2))
                      ctx.strokeStyle = root.css(root.foreground)
                      ctx.beginPath()
                      ctx.moveTo(c + r0 * Math.cos(a), c + r0 * Math.sin(a))
                      ctx.lineTo(c + r1 * Math.cos(a), c + r1 * Math.sin(a))
                      ctx.stroke()
                    }
                  }
                }
              }

              Column {
                anchors.centerIn: parent
                spacing: Style.space(3)

                Text {
                  textFormat: Text.PlainText
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: root.sessionWin ? Math.round((1 - root.sessionValue) * 100) + "%" : "—"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Math.round(Style.font.display * 1.25)
                  font.bold: true
                }

                Text {
                  textFormat: Text.PlainText
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: "Session frei"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }
              }
            }

            Column {
              anchors.left: ringBox.right
              anchors.leftMargin: Style.space(18)
              anchors.right: parent.right
              anchors.verticalCenter: ringBox.verticalCenter
              spacing: Style.space(12)

              Repeater {
                model: root.legendRows

                Column {
                  required property var modelData
                  width: parent.width
                  spacing: Style.space(2)

                  Text {
                    textFormat: Text.StyledText
                    width: parent.width
                    text: "<font color='" + modelData.dotColor + "'>" + modelData.dot + "</font> "
                      + modelData.title + " <b>" + modelData.percentText + "</b>"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                  }

                  Text {
                    textFormat: Text.PlainText
                    visible: text !== ""
                    width: parent.width
                    text: modelData.caption
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    elide: Text.ElideRight
                  }
                }
              }
            }
          }

          // ---------- Heute: Prompts · Sessions · Tokens ----------
          Row {
            id: tiles
            visible: !!root.provider && root.provider.hasPromptStats !== false
            width: parent.width
            spacing: Style.space(8)

            Repeater {
              model: root.provider ? [
                { n: String(Number(root.provider.todayPrompts || 0)), l: "Prompts heute" },
                { n: String(Number(root.provider.todaySessions || 0)), l: "Sessions heute" },
                { n: root.tileTokens(Number(root.provider.todayTotalTokens || 0)), l: "Tokens heute" }
              ] : []

              Rectangle {
                required property var modelData
                width: (tiles.width - tiles.spacing * 2) / 3
                height: tileColumn.implicitHeight + Style.space(18)
                radius: Style.space(9)
                color: root.alpha(root.foreground, 0.05)
                border.width: 1
                border.color: root.alpha(root.foreground, 0.08)

                Column {
                  id: tileColumn
                  x: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(2)

                  Text {
                    textFormat: Text.PlainText
                    text: modelData.n
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Math.round(Style.font.heading * 1.125)
                    font.bold: true
                  }

                  Text {
                    textFormat: Text.PlainText
                    text: modelData.l
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }
          }

          // ---------- Prepaid-Guthaben (nur bei Prepaid-Agents) ----------
          PanelSeparator {
            visible: balanceSection.visible
            foreground: root.foreground
          }

          Column {
            id: balanceSection
            visible: !!root.balance
            width: parent.width
            spacing: Style.space(10)

            // The meter shows what is left, not what is used: a prepaid
            // account drains toward empty rather than filling toward a cap.
            readonly property real ratio: root.balance && root.balance.funded > 0
              ? root.clamp(root.balance.remaining / root.balance.funded, 0, 1)
              : -1

            PanelSectionHeader {
              width: parent.width
              text: "BALANCE"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Item {
              width: parent.width
              implicitHeight: Math.max(balanceLabel.implicitHeight, balanceValue.implicitHeight)

              Text {
                id: balanceLabel
                text: "Prepaid credits"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                id: balanceValue
                textFormat: Text.PlainText
                text: root.balance ? root.formatMoney(root.balance.remaining, root.balance.currency) : ""
                color: root.balanceAlarming ? root.urgent : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Meter {
              visible: balanceSection.ratio >= 0
              width: parent.width
              value: balanceSection.ratio
              alarming: root.balanceAlarming
            }

            Text {
              textFormat: Text.PlainText
              visible: text !== ""
              width: parent.width
              text: root.balanceDetailText(root.balance)
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          // ---------- Letzte 7 Tage ----------
          PanelSeparator {
            visible: weekSection.visible
            foreground: root.foreground
          }

          Column {
            id: weekSection
            visible: weekSection.days.length > 0
            width: parent.width
            spacing: Style.spacing.md

            readonly property var days: root.provider ? (root.provider.recentDays || []) : []
            readonly property real peak: Math.max(1, root.weekPeak(root.provider))

            PanelSectionHeader {
              width: parent.width
              text: "LETZTE 7 TAGE"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Row {
              id: weekColumns
              width: parent.width
              height: Style.space(92)
              spacing: Style.space(8)

              Repeater {
                model: weekSection.days

                Item {
                  id: dayColumn
                  required property var modelData
                  readonly property real tokens: Number(modelData.messageCount || 0)
                  readonly property bool today: String(modelData.date || "") === root.todayDate()

                  width: (weekColumns.width - weekColumns.spacing * 6) / 7
                  height: weekColumns.height

                  Text {
                    id: dayName
                    textFormat: Text.PlainText
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: dayColumn.today ? "Heute" : root.dayNameDe(dayColumn.modelData.date)
                    color: dayColumn.today ? root.foreground : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: dayColumn.today
                  }

                  Rectangle {
                    id: dayBar
                    anchors.bottom: dayName.top
                    anchors.bottomMargin: Style.space(4)
                    width: parent.width
                    height: dayColumn.tokens > 0
                      ? Math.max(2, Math.round(Style.space(58) * dayColumn.tokens / weekSection.peak))
                      : 2
                    radius: Math.min(Style.space(4), height / 2)
                    color: dayColumn.today ? root.claudeOrange
                      : (dayColumn.tokens > 0 ? root.alpha(root.foreground, 0.45) : root.alpha(root.foreground, 0.12))
                  }

                  Text {
                    textFormat: Text.PlainText
                    anchors.bottom: dayBar.top
                    anchors.bottomMargin: Style.space(4)
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.columnTokens(dayColumn.tokens)
                    color: dayColumn.today ? root.foreground : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: dayColumn.today
                  }

                  MouseArea {
                    id: dayHover
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                  }

                  PanelToolTip {
                    visible: dayHover.containsMouse
                    text: root.dayTooltip(dayColumn.modelData, dayColumn.today)
                    fontFamily: root.fontFamily
                  }
                }
              }
            }
          }

          // ---------- Modelle: ein Balken + Legende ----------
          PanelSeparator {
            visible: modelSection.visible
            foreground: root.foreground
          }

          Column {
            id: modelSection
            visible: root.allModels.length > 0
            width: parent.width
            spacing: Style.space(8)

            Canvas {
              id: modelBar
              width: parent.width
              height: Style.space(10)
              antialiasing: true

              property var paintKey: [root.allModels, width, String(root.foreground)]
              onPaintKeyChanged: requestPaint()

              onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                var models = root.allModels
                var total = 0
                for (var i = 0; i < models.length; i++) total += models[i].total
                if (total <= 0) return
                var gap = Style.space(2)
                ctx.save()
                ctx.beginPath()
                ctx.roundedRect(0, 0, width, height, height / 2, height / 2)
                ctx.clip()
                var x = 0
                for (var j = 0; j < models.length; j++) {
                  var w = width * models[j].total / total
                  if (w < 1) continue
                  ctx.fillStyle = root.css(root.modelColor(j))
                  ctx.fillRect(x, 0, Math.max(1, w - (j < models.length - 1 ? gap : 0)), height)
                  x += w
                }
                ctx.restore()
              }
            }

            Grid {
              id: modelLegend
              width: parent.width
              columns: 2
              rows: Math.max(1, Math.ceil(root.models.length / 2))
              flow: Grid.TopToBottom
              columnSpacing: Style.space(14)
              rowSpacing: Style.space(5)

              Repeater {
                model: root.models

                Item {
                  id: legendCell
                  required property var modelData
                  required property int index
                  width: (modelLegend.width - modelLegend.columnSpacing) / 2
                  height: legendName.implicitHeight

                  Rectangle {
                    id: legendDot
                    width: Style.space(9)
                    height: width
                    radius: Style.space(2)
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.modelColor(legendCell.index)
                  }

                  Text {
                    id: legendName
                    textFormat: Text.PlainText
                    anchors.left: legendDot.right
                    anchors.leftMargin: Style.space(7)
                    anchors.right: legendShare.left
                    anchors.rightMargin: Style.space(6)
                    anchors.verticalCenter: parent.verticalCenter
                    text: legendCell.modelData.name
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    elide: Text.ElideRight
                  }

                  Text {
                    id: legendShare
                    textFormat: Text.PlainText
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: Math.round(legendCell.modelData.share * 100) + " %"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }

                  MouseArea {
                    id: legendHover
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                  }

                  PanelToolTip {
                    visible: legendHover.containsMouse
                    text: legendCell.modelData.name + " · " + usage.formatTokenCount(legendCell.modelData.total)
                      + " Tokens · " + root.modelTooltip(legendCell.modelData)
                    fontFamily: root.fontFamily
                  }
                }
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: text !== ""
            width: parent.width
            topPadding: Style.space(2)
            text: root.footerText()
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
          }
        }
      }
    }
  }

  // Rounded track showing the percentage of the allowance used.
  component Meter: Item {
    id: meter
    property real value: -1
    property bool alarming: false
    property real thickness: Math.max(Style.space(4), Math.round(Style.spacing.controlHeight * 0.14))

    implicitHeight: thickness

    Rectangle {
      id: meterTrack
      anchors.fill: parent
      radius: height / 2
      color: root.track
    }

    Rectangle {
      anchors.left: meterTrack.left
      anchors.verticalCenter: meterTrack.verticalCenter
      height: meterTrack.height
      radius: meterTrack.radius
      width: meterTrack.width * root.clamp(meter.value, 0, 1)
      color: meter.alarming ? root.urgent : root.foreground

      Behavior on width {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
      }
    }

  }

  // Leisten-Zeichen (cillian): Claude-Stern in Theme-Farbe, darum ein duenner
  // Ring, der sich mit der Session fuellt. Der Ring ragt ueber die 16-px-Box
  // hinaus in den Slot. Alles stillstehend.
  component RingMark: Item {
    id: ringMark
    anchors.fill: parent

    readonly property real diameter: Math.max(16, Math.round(Style.bar.iconSlot * 0.8))
    readonly property real stroke: Math.max(2, Math.round(diameter * 0.1))
    readonly property real starSize: Math.round(diameter * 0.5)
    readonly property real value: root.ringValue
    readonly property color ringColor: root.sessionAlarming ? root.alarmColor : root.foreground
    readonly property color trackColor: root.alpha(root.foreground, 0.22)
    readonly property color markColor: root.alarming ? root.alarmColor : root.foreground

    onValueChanged: ring.requestPaint()
    onRingColorChanged: ring.requestPaint()
    onTrackColorChanged: ring.requestPaint()

    Canvas {
      id: ring
      anchors.centerIn: parent
      width: ringMark.diameter
      height: ringMark.diameter
      antialiasing: true

      onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        var r = (width - ringMark.stroke) / 2
        var cx = width / 2
        var cy = height / 2
        ctx.lineWidth = ringMark.stroke
        ctx.lineCap = "round"
        ctx.strokeStyle = root.css(ringMark.trackColor)
        ctx.beginPath()
        ctx.arc(cx, cy, r, 0, 2 * Math.PI)
        ctx.stroke()
        if (ringMark.value > 0) {
          var start = -Math.PI / 2
          ctx.strokeStyle = root.css(ringMark.ringColor)
          ctx.beginPath()
          ctx.arc(cx, cy, r, start, start + 2 * Math.PI * Math.max(0.03, ringMark.value))
          ctx.stroke()
        }
      }
    }

    Item {
      anchors.centerIn: parent
      width: ringMark.starSize
      height: ringMark.starSize

      Shape {
        width: 256
        height: 257
        scale: ringMark.starSize / 256
        transformOrigin: Item.TopLeft
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
          fillColor: ringMark.markColor
          strokeWidth: -1
          strokeColor: "transparent"
          PathSvg { path: "m50.228 170.321 50.357-28.257.843-2.463-.843-1.361h-2.462l-8.426-.518-28.775-.778-24.952-1.037-24.175-1.296-6.092-1.297L0 125.796l.583-3.759 5.12-3.434 7.324.648 16.202 1.101 24.304 1.685 17.629 1.037 26.118 2.722h4.148l.583-1.685-1.426-1.037-1.101-1.037-25.147-17.045-27.22-18.017-14.258-10.37-7.713-5.25-3.888-4.925-1.685-10.758 7-7.713 9.397.649 2.398.648 9.527 7.323 20.35 15.75L94.817 91.9l3.889 3.24 1.555-1.102.195-.777-1.75-2.917-14.453-26.118-15.425-26.572-6.87-11.018-1.814-6.61c-.648-2.723-1.102-4.991-1.102-7.778l7.972-10.823L71.42 0 82.05 1.426l4.472 3.888 6.61 15.101 10.694 23.786 16.591 32.34 4.861 9.592 2.592 8.879.973 2.722h1.685v-1.556l1.36-18.211 2.528-22.36 2.463-28.776.843-8.1 4.018-9.722 7.971-5.25 6.222 2.981 5.12 7.324-.713 4.73-3.046 19.768-5.962 30.98-3.889 20.739h2.268l2.593-2.593 10.499-13.934 17.628-22.036 7.778-8.749 9.073-9.657 5.833-4.601h11.018l8.1 12.055-3.628 12.443-11.342 14.388-9.398 12.184-13.48 18.147-8.426 14.518.778 1.166 2.01-.194 30.46-6.481 16.462-2.982 19.637-3.37 8.88 4.148.971 4.213-3.5 8.62-20.998 5.184-24.628 4.926-36.682 8.685-.454.324.519.648 16.526 1.555 7.065.389h17.304l32.21 2.398 8.426 5.574 5.055 6.805-.843 5.184-12.962 6.611-17.498-4.148-40.83-9.721-14-3.5h-1.944v1.167l11.666 11.406 21.387 19.314 26.767 24.887 1.36 6.157-3.434 4.86-3.63-.518-23.526-17.693-9.073-7.972-20.545-17.304h-1.36v1.814l4.73 6.935 25.017 37.59 1.296 11.536-1.814 3.76-6.481 2.268-7.13-1.297-14.647-20.544-15.1-23.138-12.185-20.739-1.49.843-7.194 77.448-3.37 3.953-7.778 2.981-6.48-4.925-3.436-7.972 3.435-15.749 4.148-20.544 3.37-16.333 3.046-20.285 1.815-6.74-.13-.454-1.49.194-15.295 20.999-23.267 31.433-18.406 19.702-4.407 1.75-7.648-3.954.713-7.064 4.277-6.286 25.47-32.405 15.36-20.092 9.917-11.6-.065-1.686h-.583L44.07 198.125l-12.055 1.555-5.185-4.86.648-7.972 2.463-2.593 20.35-13.999-.064.065Z" }
        }
      }
    }
  }
}
