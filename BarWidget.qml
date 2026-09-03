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
  readonly property bool showControls: setting("showControls", true) === true
  readonly property bool showAlbumArt: setting("showAlbumArt", true) === true
  readonly property bool adaptiveLayout: setting("adaptiveLayout", true) === true
  readonly property int maxCharacters: Math.max(10, Math.min(120, Number(setting("maxCharacters", 48))))
  readonly property int maxLabelWidth: Math.max(80, Number(setting("maxLabelWidth", 300)))
  readonly property int configuredArtSize: Math.max(12, Number(setting("albumArtSize", 18)))
  readonly property int artSize: Math.min(configuredArtSize, Math.max(12, barSize - Style.space(6)))
  readonly property string fullDisplayText: {
    if (showArtist && artist && title) return artist + " — " + title
    return title || artist
  }
  readonly property string displayText: limitCharacters(fullDisplayText, maxCharacters)
  readonly property string tooltipText: {
    var text = fullDisplayText
    if (album) text += (text ? "\n" : "") + album
    if (!vertical) text += (text ? "\n" : "") + "Right-click: appearance"
    return text
  }
  readonly property int buttonWidth: Style.space(20)
  readonly property int contentSpacing: Style.space(4)
  readonly property int horizontalPadding: Style.space(12)
  readonly property int preferredLabelWidth: Math.min(maxLabelWidth, Math.ceil(label.implicitWidth))
  readonly property int minimumAdaptiveLabelWidth: Math.min(preferredLabelWidth, Style.space(80))
  property real adaptiveWidthBudget: 100000
  readonly property int adaptiveStage: calculateAdaptiveStage()
  readonly property bool previousNextVisible: !vertical && showControls && adaptiveStage === 0
  readonly property bool playPauseVisible: vertical || (showControls && (adaptiveStage <= 1 || adaptiveStage === 4))
  readonly property bool albumArtVisible: !vertical && showAlbumArt
    && (adaptiveStage <= 2 || (adaptiveStage === 4 && !showControls))
  readonly property bool labelVisible: !vertical && displayText !== ""
    && (adaptiveStage <= 3 || (adaptiveStage === 4 && !showControls && !showAlbumArt))
  readonly property int effectiveLabelWidth: calculateEffectiveLabelWidth()

  property bool settingsOpen: false
  readonly property bool opened: settingsOpen

  visible: hasMedia
  implicitWidth: hasMedia ? (vertical ? barSize : contents.implicitWidth + Style.space(12)) : 0
  implicitHeight: barSize

  Behavior on implicitWidth {
    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
  }

  Timer {
    interval: 250
    running: root.visible && !root.vertical && root.adaptiveLayout
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshAdaptiveWidthBudget()
  }

  onBarChanged: Qt.callLater(refreshAdaptiveWidthBudget)

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

  function limitCharacters(text, maximum) {
    var value = String(text || "")
    var limit = Math.max(1, Number(maximum) || 1)
    if (value.length <= limit) return value
    return value.slice(0, Math.max(1, limit - 1)).trim() + "…"
  }

  function widthFor(buttonCount, includeArt, includeLabel, labelWidth) {
    var count = buttonCount + (includeArt ? 1 : 0) + (includeLabel ? 1 : 0)
    if (count === 0) return 0
    return horizontalPadding
      + buttonCount * buttonWidth
      + (includeArt ? artSize : 0)
      + (includeLabel ? labelWidth : 0)
      + Math.max(0, count - 1) * contentSpacing
  }

  function hostSlot() {
    var slots = bar && bar.moduleSlots ? bar.moduleSlots : []
    for (var i = 0; i < slots.length; i++) {
      if (slots[i] && slots[i].activeItem === root) return slots[i]
    }
    return null
  }

  // Omarchy currently anchors its left, center, and right bar groups
  // independently. Measure the span left between this group and the other
  // groups so this widget can volunteer its own width before they overlap.
  function calculateAdaptiveWidthBudget() {
    if (vertical || !adaptiveLayout || !bar || !bar.moduleSlots) return 100000

    var ownSlot = hostSlot()
    if (!ownSlot) return 100000

    var window = null
    try {
      window = root.QsWindow.window
    } catch (e) {
    }
    if (!window || !window.contentItem) return 100000

    var screenWidth = Number(window.contentItem.width || window.width || 0)
    if (screenWidth <= 0) return 100000

    var region = String(ownSlot.region || "")
    var sameRegionWidth = 0
    var leftObstacle = Style.space(8)
    var rightObstacle = screenWidth - Style.space(8)
    var foundLeftObstacle = false
    var foundRightObstacle = false
    var slots = bar.moduleSlots

    for (var i = 0; i < slots.length; i++) {
      var slot = slots[i]
      if (!slot || slot === ownSlot || slot.visible !== true || slot.width <= 0 || slot.height <= 0)
        continue
      if (slot.activeItem && slot.activeItem.visible !== true) continue

      var slotWindow = null
      try {
        slotWindow = typeof bar.slotWindow === "function" ? bar.slotWindow(slot) : slot.QsWindow.window
      } catch (e) {
      }
      if (!slotWindow) continue
      if (typeof bar.sameWindow === "function" && !bar.sameWindow(slotWindow, window)) continue
      if (typeof bar.sameWindow !== "function" && slotWindow !== window) continue

      if (String(slot.region || "") === region) {
        sameRegionWidth += Number(slot.width || 0)
        continue
      }

      var point = null
      try {
        point = slot.mapToItem(window.contentItem, 0, 0)
      } catch (e) {
      }
      if (!point) continue

      if (region === "right") {
        leftObstacle = Math.max(leftObstacle, Number(point.x) + Number(slot.width || 0))
        foundLeftObstacle = true
      } else if (region === "left") {
        rightObstacle = Math.min(rightObstacle, Number(point.x))
        foundRightObstacle = true
      }
    }

    var edgeMargin = Style.space(8)
    var collisionGap = Style.space(8)
    if (region === "right") {
      if (!foundLeftObstacle) leftObstacle = edgeMargin
      return Math.max(0, screenWidth - edgeMargin - leftObstacle - collisionGap - sameRegionWidth)
    }
    if (region === "left") {
      if (!foundRightObstacle) rightObstacle = screenWidth - edgeMargin
      return Math.max(0, rightObstacle - edgeMargin - collisionGap - sameRegionWidth)
    }

    // A centered widget can sit on either side of the center anchor, so there
    // is no stable one-sided budget to claim without cooperation from the bar.
    return 100000
  }

  function refreshAdaptiveWidthBudget() {
    var next = calculateAdaptiveWidthBudget()
    if (Math.abs(next - adaptiveWidthBudget) >= 1) adaptiveWidthBudget = next
  }

  function calculateAdaptiveStage() {
    if (vertical || !adaptiveLayout) return 0

    var hasLabel = displayText !== ""
    var labelFloor = hasLabel ? minimumAdaptiveLabelWidth : 0
    var buttons = showControls ? 3 : 0
    var budget = adaptiveWidthBudget

    if (budget >= widthFor(buttons, showAlbumArt, hasLabel, labelFloor)) return 0
    if (showControls && budget >= widthFor(1, showAlbumArt, hasLabel, labelFloor)) return 1
    if (budget >= widthFor(0, showAlbumArt, hasLabel, labelFloor)) return 2
    if (budget >= widthFor(0, false, hasLabel, labelFloor)) return 3
    return 4
  }

  function calculateEffectiveLabelWidth() {
    if (!labelVisible) return 0
    if (!adaptiveLayout) return preferredLabelWidth

    var buttons = (previousNextVisible ? 2 : 0) + (playPauseVisible ? 1 : 0)
    var fixedOnly = widthFor(buttons, albumArtVisible, false, 0)
    var fixedCount = buttons + (albumArtVisible ? 1 : 0)
    var labelGap = fixedCount > 0 ? contentSpacing : 0
    return Math.max(1, Math.min(preferredLabelWidth,
      Math.floor(adaptiveWidthBudget - fixedOnly - labelGap)))
  }

  function close() {
    settingsOpen = false
  }

  function open() {
    settingsOpen = true
  }

  function toggle() {
    settingsOpen = !settingsOpen
  }

  function previewSetting(key, value) {
    var next = Object.assign({}, settings || {})
    next[key] = value
    settings = next
  }

  function saveSetting(key, value) {
    previewSetting(key, value)
    if (bar && bar.shell && typeof bar.shell.updateEntryInline === "function")
      bar.shell.updateEntryInline(moduleName, settings)
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
      visible: root.previousNextVisible
      onTriggered: root.previous()
    }

    TransportButton {
      iconText: root.activePlayer && root.activePlayer.isPlaying ? "󰏤" : "󰐊"
      tooltip: root.activePlayer && root.activePlayer.isPlaying ? "Pause" : "Play"
      enabled: !!(root.activePlayer && (root.activePlayer.canPlay || root.activePlayer.canPause || root.activePlayer.canTogglePlaying))
      visible: root.playPauseVisible
      onTriggered: root.playPause()
    }

    TransportButton {
      iconText: "󰒭"
      tooltip: "Next"
      enabled: !!(root.activePlayer && root.activePlayer.canGoNext)
      visible: root.previousNextVisible
      onTriggered: root.next()
    }

    Item {
      id: artContainer
      width: root.artSize
      height: root.artSize
      anchors.verticalCenter: parent.verticalCenter
      visible: root.albumArtVisible

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
          else if (mouse.button === Qt.RightButton) root.toggle()
          else root.raisePlayer()
        }
        onWheel: function(wheel) { root.wheelAction(wheel) }
        onEntered: if (root.bar) root.bar.showTooltip(artContainer, root.tooltipText)
        onExited: if (root.bar) root.bar.hideTooltip(artContainer)
      }
    }

    Item {
      id: labelClip
      width: root.effectiveLabelWidth
      height: Math.max(root.artSize, label.implicitHeight)
      anchors.verticalCenter: parent.verticalCenter
      visible: root.labelVisible
      clip: true

      Text {
        id: label
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: root.displayText
        textFormat: Text.PlainText
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
          else if (mouse.button === Qt.RightButton) root.toggle()
          else root.raisePlayer()
        }
        onWheel: function(wheel) { root.wheelAction(wheel) }
        onEntered: if (root.bar) root.bar.showTooltip(labelClip, root.tooltipText)
        onExited: if (root.bar) root.bar.hideTooltip(labelClip)
      }
    }
  }

  PopupCard {
    id: settingsPopup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.settingsOpen
    contentWidth: fittedContentWidth(Style.space(330))
    contentHeight: fittedContentHeight(settingsColumn.implicitHeight)

    Column {
      id: settingsColumn
      anchors.fill: parent
      spacing: Style.space(10)

      Text {
        text: "NOW PLAYING"
        color: root.bar ? root.bar.foreground : Color.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }

      Text {
        width: parent.width
        text: root.fullDisplayText || "No track metadata"
        textFormat: Text.PlainText
        color: root.bar ? Qt.darker(root.bar.foreground, 1.45) : Color.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }

      PanelSeparator {
        foreground: root.bar ? root.bar.foreground : Color.foreground
      }

      SettingSlider {
        label: "Maximum characters"
        suffix: ""
        minimum: 10
        maximum: 120
        step: 1
        currentValue: Number(root.setting("maxCharacters", 48))
        onPreviewed: function(value) { root.previewSetting("maxCharacters", Math.round(value)) }
        onCommitted: function(value) { root.saveSetting("maxCharacters", Math.round(value)) }
      }

      SettingSlider {
        label: "Maximum label width"
        suffix: "px"
        minimum: 80
        maximum: 600
        step: 10
        currentValue: Number(root.setting("maxLabelWidth", 300))
        onPreviewed: function(value) { root.previewSetting("maxLabelWidth", Math.round(value / 10) * 10) }
        onCommitted: function(value) { root.saveSetting("maxLabelWidth", Math.round(value / 10) * 10) }
      }

      SettingSlider {
        label: "Album art size"
        suffix: "px"
        minimum: 12
        maximum: 22
        step: 1
        currentValue: Number(root.setting("albumArtSize", 18))
        onPreviewed: function(value) { root.previewSetting("albumArtSize", Math.round(value)) }
        onCommitted: function(value) { root.saveSetting("albumArtSize", Math.round(value)) }
      }

      Toggle {
        width: parent.width
        label: "Adapt to available space"
        description: "Shrink this widget before bar sections overlap."
        checked: root.adaptiveLayout
        foreground: root.bar ? root.bar.foreground : Color.foreground
        accent: Color.accent
        fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
        onClicked: root.saveSetting("adaptiveLayout", !root.adaptiveLayout)
      }

      Toggle {
        width: parent.width
        label: "Show transport controls"
        description: "Previous, play/pause, and next buttons."
        checked: root.showControls
        foreground: root.bar ? root.bar.foreground : Color.foreground
        accent: Color.accent
        fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
        onClicked: root.saveSetting("showControls", !root.showControls)
      }

      Toggle {
        width: parent.width
        label: "Show album art"
        description: "Keep artwork beside the track label when space allows."
        checked: root.showAlbumArt
        foreground: root.bar ? root.bar.foreground : Color.foreground
        accent: Color.accent
        fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
        onClicked: root.saveSetting("showAlbumArt", !root.showAlbumArt)
      }

      Toggle {
        width: parent.width
        label: "Show artist"
        description: "Place the artist before the track title."
        checked: root.showArtist
        foreground: root.bar ? root.bar.foreground : Color.foreground
        accent: Color.accent
        fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
        onClicked: root.saveSetting("showArtist", !root.showArtist)
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
      enabled: true
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      cursorShape: button.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: function(event) {
        if (event.button === Qt.RightButton) root.toggle()
        else if (button.enabled) button.triggered()
      }
      onWheel: function(wheel) { root.wheelAction(wheel) }
      onEntered: if (root.bar && button.tooltip) root.bar.showTooltip(button, button.tooltip)
      onExited: if (root.bar) root.bar.hideTooltip(button)
    }
  }

  component SettingSlider: Column {
    id: sliderSetting

    required property string label
    property string suffix: ""
    required property real minimum
    required property real maximum
    required property real step
    required property real currentValue

    signal previewed(real value)
    signal committed(real value)

    width: parent ? parent.width : implicitWidth
    spacing: Style.space(5)

    Item {
      width: parent.width
      implicitHeight: Math.max(settingLabel.implicitHeight, settingValue.implicitHeight)

      Text {
        id: settingLabel
        anchors.left: parent.left
        text: sliderSetting.label
        color: root.bar ? root.bar.foreground : Color.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
      }

      Text {
        id: settingValue
        anchors.right: parent.right
        text: Math.round(slider.dragging ? slider.liveValue : sliderSetting.currentValue) + sliderSetting.suffix
        color: root.bar ? Qt.darker(root.bar.foreground, 1.35) : Color.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
      }
    }

    PanelSlider {
      id: slider
      width: parent.width
      bar: root.bar
      minimum: sliderSetting.minimum
      maximum: sliderSetting.maximum
      step: sliderSetting.step
      integer: true
      value: sliderSetting.currentValue
      onMoved: function(value) { sliderSetting.previewed(value) }
      onReleased: function(value) { sliderSetting.committed(value) }
    }
  }
}
