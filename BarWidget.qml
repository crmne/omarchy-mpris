import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "crmne.mpris"

  readonly property var mediaService: bar && bar.shell ? bar.shell.serviceFor("crmne.mpris") : null
  readonly property var activePlayer: mediaService ? mediaService.activePlayer : null
  readonly property bool hasMedia: mediaService ? mediaService.hasMedia : false
  readonly property string title: mediaService ? mediaService.title : ""
  readonly property string artist: mediaService ? mediaService.artist : ""
  readonly property string album: mediaService ? mediaService.album : ""
  readonly property string artUrl: mediaService ? mediaService.artUrl : ""
  readonly property bool showArtist: setting("showArtist", true) === true
  readonly property int maxLabelWidth: Math.max(80, Number(setting("maxLabelWidth", 300)))
  readonly property int configuredArtSize: Math.max(12, Number(setting("albumArtSize", 18)))
  readonly property int artSize: Math.min(configuredArtSize, Math.max(12, barSize - Style.space(6)))
  readonly property string displayText: {
    if (showArtist && artist && title) return artist + " — " + title
    return title || artist
  }
  readonly property string tooltipText: {
    var text = displayText
    if (album) text += (text ? "\n" : "") + album
    return text
  }

  visible: hasMedia
  implicitWidth: hasMedia ? (vertical ? barSize : contents.implicitWidth + Style.space(12)) : 0
  implicitHeight: barSize

  Behavior on implicitWidth {
    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
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

    TransportButton {
      iconText: "󰒮"
      tooltip: "Previous"
      enabled: !!(root.activePlayer && root.activePlayer.canGoPrevious)
      visible: !root.vertical
      onTriggered: root.previous()
    }

    TransportButton {
      iconText: root.activePlayer && root.activePlayer.isPlaying ? "󰏤" : "󰐊"
      tooltip: root.activePlayer && root.activePlayer.isPlaying ? "Pause" : "Play"
      enabled: !!(root.activePlayer && (root.activePlayer.canPlay || root.activePlayer.canPause || root.activePlayer.canTogglePlaying))
      onTriggered: root.playPause()
    }

    TransportButton {
      iconText: "󰒭"
      tooltip: "Next"
      enabled: !!(root.activePlayer && root.activePlayer.canGoNext)
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

      Image {
        id: cover
        anchors.fill: parent
        anchors.margins: 1
        source: root.artUrl
        sourceSize.width: Math.round(width * Screen.devicePixelRatio)
        sourceSize.height: Math.round(height * Screen.devicePixelRatio)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        smooth: true
      }

      Text {
        anchors.centerIn: parent
        visible: root.artUrl === "" || cover.status === Image.Error
        text: "󰝚"
        color: root.bar ? root.bar.barForeground : Color.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
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

    Item {
      id: labelClip
      width: Math.min(root.maxLabelWidth, label.implicitWidth)
      height: Math.max(root.artSize, label.implicitHeight)
      anchors.verticalCenter: parent.verticalCenter
      visible: !root.vertical && root.displayText !== ""
      clip: true

      Text {
        id: label
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: root.displayText
        color: root.bar ? root.bar.barForeground : Color.foreground
        opacity: root.activePlayer && root.activePlayer.isPlaying ? 0.92 : 0.58
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        elide: Text.ElideRight

        Behavior on opacity { NumberAnimation { duration: 140 } }
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
        onEntered: if (root.bar) root.bar.showTooltip(labelClip, root.tooltipText)
        onExited: if (root.bar) root.bar.hideTooltip(labelClip)
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
