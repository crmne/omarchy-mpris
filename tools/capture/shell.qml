// Isolated screenshot host: the production bar widget and Omarchy's own Ui
// kit, fed synthetic now-playing fixtures. Run by capture.py.
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

ShellRoot {
  id: host

  readonly property string pluginDir: Quickshell.env("MPRIS_PLUGIN")
  readonly property string outputDir: Quickshell.env("MPRIS_OUTPUT")
  readonly property bool composing: Quickshell.env("MPRIS_MODE") === "compose"
  readonly property string coverUrl: "file://" + outputDir + "/cover.png"
  property bool coverReady: false

  Component.onCompleted: Style.cornerRadius = 10

  // Self-drawn abstract album cover (no real artwork).
  FloatingWindow {
    visible: !host.composing
    implicitWidth: 96; implicitHeight: 96
    color: "transparent"
    Item {
      id: cover
      width: 96; height: 96
      Rectangle {
        anchors.fill: parent
        gradient: Gradient {
          orientation: Gradient.Vertical
          GradientStop { position: 0.0; color: "#f6b26b" }
          GradientStop { position: 0.55; color: "#d0603d" }
          GradientStop { position: 1.0; color: "#3a1f3d" }
        }
      }
      Rectangle { x: 18; y: 14; width: 46; height: 46; radius: 23; color: "#fde9c8"; opacity: 0.9 }
      Rectangle { x: -10; y: 62; width: 120; height: 14; rotation: -8; color: "#2a1630"; opacity: 0.75 }
      Rectangle { x: -10; y: 78; width: 120; height: 30; rotation: -8; color: "#1b0f20" }
    }
  }

  component FakeShell: QtObject {
    property var service: null
    function serviceFor(id) { return id === "crmne.mpris" ? service : null }
  }

  component Api: PluginBarApi {
    pluginId: "crmne.mpris"
    moduleName: "crmne.mpris"
    foreground: Color.bar.text
    barForeground: Color.bar.text
    background: Color.bar.background
    urgent: Color.bar.active
    fontFamily: Style.font.family
    barSize: Style.bar.sizeHorizontal
    foregroundAnimationEnabled: false
    _requestPopout: function(owner) { activePopout = owner }
    _releasePopout: function(owner) { if (activePopout === owner) activePopout = null }
  }

  // A slot shaped like Bar.qml's ModuleSlot (region + activeItem), which is
  // what the widget's adaptive layout measures.
  component Slot: Item {
    property string region: "right"
    property Item activeItem: null
    width: activeItem && activeItem.visible ? activeItem.implicitWidth : 0
    height: Style.bar.sizeHorizontal
  }

  // Stand-ins for the neighbouring built-in modules, drawn with the bar's
  // font and colors. Only the media widget is the plugin.
  component Glyphs: Row {
    property alias model: repeater.model
    property real dim: 1
    spacing: Style.space(12)
    leftPadding: Style.space(6)
    rightPadding: Style.space(6)
    height: Style.bar.sizeHorizontal
    Repeater {
      id: repeater
      Text {
        required property var modelData
        anchors.verticalCenter: parent.verticalCenter
        text: modelData.text
        opacity: modelData.dim ? 0.45 : 1
        color: Color.bar.text
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
    }
  }

  component BarStrip: Item {
    id: strip
    property alias widget: widgetLoader.item
    readonly property real clockX: clockSlot.x
    property var service
    property string clock: "Wed 21:40"
    readonly property Api api: Api { shell: FakeShell { service: strip.service } }
    height: Style.bar.sizeHorizontal

    Rectangle { anchors.fill: parent; color: Color.bar.background }

    Slot {
      region: "left"
      x: Style.space(8)
      activeItem: children[0]
      Glyphs { model: [{ text: "1" }, { text: "2", dim: true }, { text: "3", dim: true }, { text: "4", dim: true }] }
    }

    Slot {
      id: clockSlot
      region: "center"
      anchors.horizontalCenter: parent.horizontalCenter
      activeItem: children[0]
      Glyphs { model: [{ text: strip.clock }] }
    }

    Row {
      anchors.right: parent.right
      anchors.rightMargin: Style.space(8)
      Slot {
        id: mediaSlot
        Loader {
          id: widgetLoader
          source: "file://" + host.pluginDir + "/BarWidget.qml"
          onLoaded: {
            item.bar = strip.api
            mediaSlot.activeItem = item
          }
        }
      }
      Slot {
        activeItem: children[0]
        Glyphs { model: [{ text: "󰂯" }, { text: "󰤨" }, { text: "󰕾" }, { text: "󰁹" }] }
      }
    }
  }

  FakeService {
    id: playingService
    playing: true
    artist: "Vela Coast"
    title: "Glasswork"
    album: "Low Tide Signals"
    artUrl: host.coverReady ? host.coverUrl : ""
  }

  FakeService {
    id: pausedService
    playing: false
    artist: "Vela Coast"
    title: "Paper Satellites"
    album: "Low Tide Signals"
    artUrl: host.coverReady ? host.coverUrl : ""
  }

  FloatingWindow {
    id: wideWindow
    visible: !host.composing
    implicitWidth: 853; implicitHeight: Style.bar.sizeHorizontal
    color: "transparent"
    BarStrip { id: wide; width: parent.width; service: playingService }
  }

  FloatingWindow {
    id: narrowWindow
    visible: !host.composing
    implicitWidth: 560; implicitHeight: Style.bar.sizeHorizontal
    color: "transparent"
    BarStrip { id: narrow; width: parent.width; service: pausedService; clock: "Thu 08:15" }
  }

  function settingsPopup() {
    var data = wide.widget ? wide.widget.data : []
    for (var i = 0; i < data.length; i++) {
      if (data[i] && typeof data[i].fittedContentWidth === "function") return data[i]
    }
    return null
  }

  function state(strip) {
    var w = strip.widget
    return {
      visible: w.visible, stage: w.adaptiveStage, width: w.implicitWidth,
      budget: w.adaptiveWidthBudget, stripWidth: strip.width,
      label: w.displayText, labelWidth: w.effectiveLabelWidth,
      previousNext: w.previousNextVisible, playPause: w.playPauseVisible,
      art: w.albumArtVisible, labelVisible: w.labelVisible, opened: w.opened
    }
  }

  // Composition: real captures over Omarchy's Ristretto wallpaper.
  FloatingWindow {
    visible: host.composing
    implicitWidth: 2560; implicitHeight: 1600
    color: "#090503"
    Item {
      id: composition
      width: 2560; height: 1600
      Image {
        anchors.fill: parent
        source: host.composing ? Quickshell.env("MPRIS_WALLPAPER") : ""
        fillMode: Image.PreserveAspectCrop
        layer.enabled: true
        layer.effect: MultiEffect { blurEnabled: true; blurMax: 32; blur: 0.8 }
      }
      Rectangle { anchors.fill: parent; color: "#9e000000" }
      Repeater {
        model: host.composing ? JSON.parse(Quickshell.env("MPRIS_LAYOUT")) : []
        Item {
          id: placed
          required property var modelData
          x: modelData.x; y: modelData.y
          width: modelData.width; height: modelData.height
          layer.enabled: true
          layer.effect: MultiEffect { shadowEnabled: true; shadowBlur: 0.9; shadowOpacity: 0.65; shadowVerticalOffset: 18 }
          Rectangle {
            id: mask
            anchors.fill: parent
            radius: placed.modelData.radius || 0
            visible: false
            layer.enabled: true
          }
          Image {
            anchors.fill: parent
            source: "file://" + host.outputDir + "/" + placed.modelData.file
            sourceClipRect: placed.modelData.clip ? Qt.rect(placed.modelData.clip[0], placed.modelData.clip[1],
              placed.modelData.clip[2], placed.modelData.clip[3]) : undefined
            smooth: true; mipmap: true
            layer.enabled: !!placed.modelData.radius
            layer.effect: MultiEffect { maskEnabled: true; maskSource: mask }
          }
        }
      }
    }
  }

  IpcHandler {
    target: "capture"
    function ready(): bool {
      if (host.composing) return true
      return !!wide.widget && !!narrow.widget && !!settingsPopup()
    }
    function drawCover(): bool {
      return cover.grabToImage(result => {
        result.saveToFile(host.outputDir + "/cover.png")
        host.coverReady = true
      })
    }
    function setNarrowWidth(width: int): string {
      // An offscreen window keeps its first size; remap it at the new width.
      narrowWindow.visible = false
      narrowWindow.implicitWidth = width
      narrowWindow.visible = true
      narrow.widget.refreshAdaptiveWidthBudget()
      return JSON.stringify(state(narrow))
    }
    function states(): string {
      return JSON.stringify({ wide: state(wide), narrow: state(narrow), coverStatus: host.coverReady })
    }
    function openSettings(): string {
      wide.widget.open()
      var popup = settingsPopup()
      return JSON.stringify({ opened: wide.widget.opened, popupVisible: popup.visible,
        width: popup.implicitWidth, height: popup.implicitHeight })
    }
    function widgetGeometry(): string {
      var w = wide.widget
      var p = w.mapToItem(null, 0, 0)
      return JSON.stringify({ x: p.x, width: w.width, barWidth: wideWindow.width,
        compactClockX: narrow.clockX })
    }
    function grab(which: string, path: string): string {
      var item = which === "wide" ? wide : which === "narrow" ? narrow
        : which === "settings" ? settingsPopup().contentItem[0].parent.parent : null
      if (!item) return "No item " + which
      return item.grabToImage(result => result.saveToFile(path)) ? "ok" : "Capture failed"
    }
    function grabPreview(path: string): bool {
      return composition.grabToImage(result => result.saveToFile(path))
    }
  }
}
