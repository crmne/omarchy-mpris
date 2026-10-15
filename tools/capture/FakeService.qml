// Screenshot fixture standing in for Service.qml. It exposes the same
// properties and methods the bar widget reads, with no MPRIS import, so the
// capture host never sees or controls a real media player.
import QtQuick

QtObject {
  id: fixture
  property bool ipcEnabled: false
  property bool playing: true
  property string title: ""
  property string artist: ""
  property string album: ""
  property string artUrl: ""
  readonly property bool hasMedia: title !== "" || artist !== ""
  readonly property QtObject activePlayer: QtObject {
    readonly property bool isPlaying: fixture.playing
    readonly property bool canGoPrevious: true
    readonly property bool canGoNext: true
    readonly property bool canPlay: true
    readonly property bool canPause: true
    readonly property bool canTogglePlaying: true
  }

  function previous() { return false }
  function next() { return false }
  function playPause() { return false }
  function raisePlayer() { return false }
}
