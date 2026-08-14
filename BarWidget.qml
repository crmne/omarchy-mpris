import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "crmne.mpris"

  readonly property var mediaService: bar && bar.shell ? bar.shell.serviceFor("crmne.mpris") : null
  readonly property bool hasMedia: mediaService ? mediaService.hasMedia : false
  readonly property string title: mediaService ? mediaService.title : ""
  readonly property string artist: mediaService ? mediaService.artist : ""
  readonly property string album: mediaService ? mediaService.album : ""
  readonly property string artUrl: mediaService ? mediaService.artUrl : ""

  // Latched by the service, so none of these flicker while a player clears its
  // metadata between tracks.
  readonly property bool isPlaying: mediaService ? mediaService.isPlaying : false
  readonly property bool canGoPrevious: mediaService ? mediaService.canGoPrevious : false
  readonly property bool canGoNext: mediaService ? mediaService.canGoNext : false
  readonly property bool canPlayPause: mediaService ? mediaService.canPlayPause : false

  readonly property bool showArtist: setting("showArtist", true) === true
  readonly property int maxLabelWidth: Math.max(80, Math.min(600, Number(setting("maxLabelWidth", 300))))
  readonly property int configuredArtSize: Math.max(12, Math.min(22, Number(setting("albumArtSize", 18))))
  readonly property int artSize: Math.min(configuredArtSize, Math.max(12, barSize - Style.space(6)))

  // Clamps mirror the min/max each setting declares in manifest.json.
  readonly property int transitionMs: Math.max(0, Math.min(800, Number(setting("transitionMs", 260))))
  readonly property int graceMs: Math.max(0, Math.min(5000, Number(setting("trackChangeGrace", 1500))))
  readonly property int settleMs: Math.max(0, Math.min(2000, Number(setting("trackSettle", 350))))
  readonly property string labelWidthMode: {
    var mode = String(setting("labelWidth", "smooth"))
    return (mode === "stable" || mode === "fixed") ? mode : "smooth"
  }

  // Animations stay off until the widget has settled one beat after being
  // created, so a shell reload or a theme swap does not replay every entrance.
  // `foregroundAnimationEnabled` is the bar's own "hold still" flag.
  property bool armed: false
  readonly property bool animate: transitionMs > 0 && armed && (!bar || bar.foregroundAnimationEnabled)

  readonly property string displayText: {
    if (showArtist && artist && title) return artist + " — " + title
    return title || artist
  }
  readonly property string tooltipText: {
    var text = displayText
    if (album) text += (text ? "\n" : "") + album
    return text
  }

  // 0 = fully collapsed, 1 = fully present. Drives width and opacity together
  // so appearing and disappearing are the same gesture played either way.
  property real presence: hasMedia ? 1 : 0
  readonly property real contentWidth: contents.implicitWidth + Style.space(12)

  Behavior on presence {
    enabled: root.animate
    NumberAnimation { duration: Math.round(root.transitionMs * 1.2); easing.type: Easing.InOutCubic }
  }

  clip: true
  visible: presence > 0.002
  implicitWidth: vertical ? barSize : Math.round(contentWidth * presence)
  implicitHeight: vertical ? Math.round(barSize * presence) : barSize

  function syncServiceSettings() {
    if (!mediaService) return
    if (mediaService.graceMs !== undefined) mediaService.graceMs = graceMs
    if (mediaService.settleMs !== undefined) mediaService.settleMs = settleMs
  }

  onGraceMsChanged: syncServiceSettings()
  onSettleMsChanged: syncServiceSettings()
  onMediaServiceChanged: syncServiceSettings()

  Component.onCompleted: {
    syncServiceSettings()
    armTimer.start()
  }

  Timer {
    id: armTimer
    interval: 350
    repeat: false
    onTriggered: root.armed = true
  }

  function previous() {
    if (mediaService) mediaService.previous()
  }

  function playPause() {
    if (mediaService) mediaService.playPause()
  }

  function next() {
    if (mediaService) mediaService.next()
  }

  function raisePlayer() {
    if (mediaService) mediaService.raisePlayer()
  }

  function wheelAction(wheel) {
    if (wheel.angleDelta.y > 0) previous()
    else if (wheel.angleDelta.y < 0) next()
  }

  Row {
    id: contents
    anchors.centerIn: parent
    spacing: Style.space(4)
    opacity: root.presence

    TransportButton {
      iconText: "󰒮"
      tooltip: "Previous"
      enabled: root.canGoPrevious
      visible: !root.vertical
      onTriggered: root.previous()
    }

    TransportButton {
      iconText: root.isPlaying ? "󰏤" : "󰐊"
      tooltip: root.isPlaying ? "Pause" : "Play"
      enabled: root.canPlayPause
      onTriggered: root.playPause()
    }

    TransportButton {
      iconText: "󰒭"
      tooltip: "Next"
      enabled: root.canGoNext
      visible: !root.vertical
      onTriggered: root.next()
    }

    Item {
      id: artContainer
      width: root.artSize
      height: root.artSize
      anchors.verticalCenter: parent.verticalCenter
      visible: !root.vertical

      Rectangle {
        anchors.fill: parent
        radius: Style.space(3)
        color: root.bar ? Style.normalFillFor(root.bar.barForeground, Color.accent) : "transparent"
      }

      CrossfadeArt {
        id: cover
        anchors.fill: parent
        anchors.margins: 1
        source: root.artUrl
        duration: root.transitionMs
        animate: root.animate
      }

      Text {
        anchors.centerIn: parent
        text: "󰝚"
        color: root.bar ? root.bar.barForeground : Color.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        opacity: cover.hasArt ? 0 : 1
        visible: opacity > 0.002

        Behavior on opacity {
          enabled: root.animate
          NumberAnimation { duration: root.transitionMs; easing.type: Easing.InOutQuad }
        }
      }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: function(mouse) {
          if (mouse.button === Qt.MiddleButton) root.previous()
          else if (mouse.button === Qt.RightButton) root.next()
          else root.raisePlayer()
        }
        onWheel: function(wheel) { root.wheelAction(wheel) }
        onEntered: if (root.bar) root.bar.showTooltip(artContainer, root.tooltipText)
        onExited: if (root.bar) root.bar.hideTooltip(artContainer)
      }
    }

    RollText {
      id: labelRoll
      anchors.verticalCenter: parent.verticalCenter
      visible: !root.vertical && root.displayText !== ""
      text: root.displayText
      maxWidth: root.maxLabelWidth
      minHeight: root.artSize
      widthMode: root.labelWidthMode
      duration: root.transitionMs
      animate: root.animate
      textColor: root.bar ? root.bar.barForeground : Color.foreground
      fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
      pixelSize: Style.font.body
      settledOpacity: root.isPlaying ? 0.92 : 0.58

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: function(mouse) {
          if (mouse.button === Qt.MiddleButton) root.previous()
          else if (mouse.button === Qt.RightButton) root.next()
          else root.raisePlayer()
        }
        onWheel: function(wheel) { root.wheelAction(wheel) }
        onEntered: if (root.bar) root.bar.showTooltip(labelRoll, root.tooltipText)
        onExited: if (root.bar) root.bar.hideTooltip(labelRoll)
      }
    }
  }

  // Two stacked labels driven by a single 0..1 `phase`. The outgoing title
  // rises and fades while the incoming one arrives from below, and the clip
  // width animates alongside, so a track change reads as one motion instead of
  // a collapse followed by a re-entry.
  component RollText: Item {
    id: roll

    property string text: ""
    property int maxWidth: 300
    property int minHeight: 0
    property string widthMode: "smooth"
    property int duration: 260
    property bool animate: true
    property color textColor: "white"
    property string fontFamily: "monospace"
    property int pixelSize: 12
    property real settledOpacity: 1.0

    property string currentText: ""
    property string previousText: ""
    property real phase: 1
    property real heldWidth: 0

    readonly property real travel: Math.max(5, Math.round(height * 0.5))
    readonly property real naturalWidth: Math.min(maxWidth, incoming.implicitWidth)

    clip: true
    opacity: settledOpacity
    implicitHeight: Math.max(minHeight, incoming.implicitHeight)
    implicitWidth: {
      if (widthMode === "fixed") return maxWidth
      if (widthMode === "stable") return heldWidth
      return naturalWidth
    }

    Behavior on opacity {
      enabled: roll.animate
      NumberAnimation { duration: 140 }
    }

    Behavior on implicitWidth {
      enabled: roll.animate
      NumberAnimation { duration: roll.duration; easing.type: Easing.InOutCubic }
    }

    // "stable" grows the moment a longer title needs the room, but only gives
    // width back once the title has stopped changing — rapid skipping through
    // a playlist stops shoving the rest of the bar around.
    onNaturalWidthChanged: {
      if (naturalWidth >= heldWidth) {
        shrinkTimer.stop()
        heldWidth = naturalWidth
      } else {
        shrinkTimer.restart()
      }
    }

    onTextChanged: {
      if (text === currentText) return
      if (!animate || currentText === "") {
        previousText = ""
        currentText = text
        phase = 1
        return
      }
      previousText = currentText
      currentText = text
      rollAnim.restart()
    }

    Component.onCompleted: heldWidth = naturalWidth

    Timer {
      id: shrinkTimer
      interval: 2000
      repeat: false
      onTriggered: roll.heldWidth = roll.naturalWidth
    }

    NumberAnimation {
      id: rollAnim
      target: roll
      property: "phase"
      from: 0
      to: 1
      duration: roll.duration
      easing.type: Easing.OutCubic
    }

    Text {
      id: incoming
      x: 0
      y: (roll.height - height) / 2 + (1 - roll.phase) * roll.travel
      width: Math.min(roll.maxWidth, implicitWidth)
      text: roll.currentText
      color: roll.textColor
      font.family: roll.fontFamily
      font.pixelSize: roll.pixelSize
      elide: Text.ElideRight
      opacity: roll.phase
    }

    Text {
      id: outgoing
      x: 0
      y: (roll.height - height) / 2 - roll.phase * roll.travel
      width: Math.min(roll.maxWidth, implicitWidth)
      text: roll.previousText
      color: roll.textColor
      font.family: roll.fontFamily
      font.pixelSize: roll.pixelSize
      elide: Text.ElideRight
      opacity: 1 - roll.phase
      visible: opacity > 0.002
    }
  }

  // Album art swaps through two layers: the new cover is decoded on the hidden
  // layer and only crossfaded in once it is actually ready, so changing tracks
  // never flashes an empty square.
  component CrossfadeArt: Item {
    id: art

    property string source: ""
    property int duration: 260
    property bool animate: true
    property bool showA: true

    readonly property Image front: showA ? imgA : imgB
    readonly property Image back: showA ? imgB : imgA
    readonly property bool hasArt: front.status === Image.Ready

    function reveal(image) {
      if (image === front) return
      if (String(image.source) !== art.source) return
      if (art.source === "" || image.status === Image.Ready || image.status === Image.Error)
        art.showA = !art.showA
    }

    onSourceChanged: {
      if (String(front.source) === source) return
      back.source = source
      // An already-cached cover reports no status change, so poke the swap
      // once the assignment has settled.
      Qt.callLater(function() { art.reveal(art.back) })
    }

    Image {
      id: imgA
      anchors.fill: parent
      sourceSize.width: Math.round(art.width * Screen.devicePixelRatio)
      sourceSize.height: Math.round(art.height * Screen.devicePixelRatio)
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      cache: true
      smooth: true
      opacity: art.showA ? 1 : 0
      visible: opacity > 0.002
      onStatusChanged: art.reveal(imgA)

      Behavior on opacity {
        enabled: art.animate
        NumberAnimation { duration: art.duration; easing.type: Easing.InOutQuad }
      }
    }

    Image {
      id: imgB
      anchors.fill: parent
      sourceSize.width: Math.round(art.width * Screen.devicePixelRatio)
      sourceSize.height: Math.round(art.height * Screen.devicePixelRatio)
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      cache: true
      smooth: true
      opacity: art.showA ? 0 : 1
      visible: opacity > 0.002
      onStatusChanged: art.reveal(imgB)

      Behavior on opacity {
        enabled: art.animate
        NumberAnimation { duration: art.duration; easing.type: Easing.InOutQuad }
      }
    }
  }

  component TransportButton: Item {
    id: button

    required property string iconText
    property string tooltip: ""
    signal triggered()

    implicitWidth: Style.space(20)
    implicitHeight: root.artSize
    opacity: enabled ? 1.0 : 0.32

    Behavior on opacity { NumberAnimation { duration: 120 } }

    Rectangle {
      anchors.fill: parent
      radius: Style.space(4)
      color: mouse.containsMouse && button.enabled
        ? Style.hoverFillFor(root.bar ? root.bar.barForeground : Color.foreground, Color.accent)
        : "transparent"
    }

    Text {
      anchors.centerIn: parent
      text: button.iconText
      color: root.bar ? root.bar.barForeground : Color.foreground
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.body
    }

    MouseArea {
      id: mouse
      anchors.fill: parent
      enabled: button.enabled
      hoverEnabled: true
      cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: button.triggered()
      onWheel: function(wheel) { root.wheelAction(wheel) }
      onEntered: if (root.bar && button.tooltip) root.bar.showTooltip(button, button.tooltip)
      onExited: if (root.bar) root.bar.hideTooltip(button)
    }
  }
}
