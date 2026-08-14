import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import "MediaLatch.js" as MediaLatch

// Thin shell around MediaLatch.js: read the bus, hand snapshots to the latch,
// publish what it says to show. All the decisions — and all the reasoning
// about why players cannot be trusted mid-skip — live in the .js, where they
// can be tested against a virtual clock. See tests/.
Item {
  id: root

  property string preferredPlayerKey: ""

  // Keep serving the current track this long after a player drops its
  // metadata entirely. 0 disables it.
  property int graceMs: 5000

  // How long a *suspicious* track must hold still before it reaches the bar.
  // Tracks that look genuine never wait, so this is not a latency the bar pays
  // on an ordinary skip. 0 disables the check.
  property int settleMs: 350

  readonly property var players: Mpris.players ? Mpris.players.values : []
  readonly property var sourcePlayers: availablePlayers()

  // ── Live view of the bus ──────────────────────────────────────────────
  readonly property var livePlayer: chooseActivePlayer()

  // Cover art on its own is not a track. Players clear the title before the
  // rest of the metadata, and treating that moment as real media puts a
  // nameless entry on the bar.
  readonly property bool liveHasMedia: livePlayer !== null
    && livePlayer.playbackState !== MprisPlaybackState.Stopped
    && (liveTitle !== "" || liveArtist !== "")
  readonly property string liveTitle: livePlayer ? String(livePlayer.trackTitle || "") : ""
  readonly property string liveArtist: livePlayer ? String(livePlayer.trackArtist || "") : ""
  readonly property string liveAlbum: livePlayer ? String(livePlayer.trackAlbum || "") : ""
  readonly property string liveArtUrl: livePlayer ? String(livePlayer.trackArtUrl || "") : ""
  readonly property bool livePlaying: !!(livePlayer && livePlayer.isPlaying)
  readonly property bool liveCanGoPrevious: !!(livePlayer && livePlayer.canGoPrevious)
  readonly property bool liveCanGoNext: !!(livePlayer && livePlayer.canGoNext)
  readonly property bool liveCanPlayPause: !!(livePlayer
    && (livePlayer.canPlay || livePlayer.canPause || livePlayer.canTogglePlaying))

  // Everything the widget renders, folded into one string, so a single handler
  // catches any change worth reacting to.
  readonly property string liveSignature: (liveHasMedia ? "1" : "0")
    + liveTitle + "" + liveArtist + "" + liveAlbum + "" + liveArtUrl
    + (livePlaying ? "1" : "0") + (liveCanGoPrevious ? "1" : "0")
    + (liveCanGoNext ? "1" : "0") + (liveCanPlayPause ? "1" : "0")

  // ── Committed snapshot, mirrored out of the latch ─────────────────────
  property bool comHasMedia: false
  property string comPlayerKey: ""
  property string comTitle: ""
  property string comArtist: ""
  property string comAlbum: ""
  property string comArtUrl: ""
  property bool comPlaying: false
  property bool comCanGoPrevious: false
  property bool comCanGoNext: false
  property bool comCanPlayPause: false
  property bool comHolding: false
  property int comSuspects: 0

  // ── Public surface ────────────────────────────────────────────────────
  readonly property var activePlayer: comHasMedia
    ? (findByKey(comPlayerKey) || livePlayer) : livePlayer
  readonly property bool hasMedia: comHasMedia
  readonly property string title: comTitle
  readonly property string artist: comArtist
  readonly property string album: comAlbum
  readonly property string artUrl: comArtUrl
  readonly property bool isPlaying: comPlaying
  readonly property bool canGoPrevious: comCanGoPrevious
  readonly property bool canGoNext: comCanGoNext
  readonly property bool canPlayPause: comCanPlayPause
  readonly property bool holding: comHolding

  property var latch: null
  property real scheduledFor: -1

  // MPRIS properties do not all land in one go: a player can change the title
  // in one message and its next/previous capability in the next. Deciding
  // synchronously would classify against a half-applied state, so collapse
  // every change within an event-loop turn into one decision.
  property bool evalQueued: false

  Component.onCompleted: {
    latch = MediaLatch.createLatch({ graceMs: graceMs, settleMs: settleMs })
    pump()
  }

  onLiveSignatureChanged: schedulePump()
  onLivePlayerChanged: schedulePump()
  onPlayersChanged: schedulePump()
  onGraceMsChanged: applyConfig()
  onSettleMsChanged: applyConfig()

  Timer {
    id: latchTimer
    repeat: false
    onTriggered: {
      if (!root.latch) return
      root.latch.tick(Date.now())
      root.publish()
    }
  }

  function applyConfig() {
    if (!latch) return
    latch.config.graceMs = graceMs
    latch.config.settleMs = settleMs
    latch.config.lostPlayerGraceMs = Math.min(graceMs, 400)
    pump()
  }

  function schedulePump() {
    if (evalQueued) return
    evalQueued = true
    Qt.callLater(pump)
  }

  function liveSnapshot() {
    return {
      hasMedia: liveHasMedia,
      key: MediaLatch.trackKey(liveTitle, liveArtist, liveAlbum),
      title: liveTitle,
      artist: liveArtist,
      album: liveAlbum,
      artUrl: liveArtUrl,
      playing: livePlaying,
      canGoPrevious: liveCanGoPrevious,
      canGoNext: liveCanGoNext,
      canPlayPause: liveCanPlayPause,
      playerKey: playerKey(livePlayer)
    }
  }

  function alivePlayerKeys() {
    var keys = []
    for (var i = 0; i < players.length; i++) keys.push(playerKey(players[i]))
    return keys
  }

  function pump() {
    evalQueued = false
    if (!latch) return
    latch.update(liveSnapshot(), alivePlayerKeys(), Date.now())
    publish()
  }

  function publish() {
    var c = latch.committed()
    comHasMedia = c.hasMedia
    comPlayerKey = c.playerKey
    comTitle = c.title
    comArtist = c.artist
    comAlbum = c.album
    comArtUrl = c.artUrl
    comPlaying = c.playing
    comCanGoPrevious = c.canGoPrevious
    comCanGoNext = c.canGoNext
    comCanPlayPause = c.canPlayPause

    var d = latch.debug()
    comHolding = d.holding
    comSuspects = d.suspects.length

    var due = latch.nextDeadline()
    if (due < 0) {
      latchTimer.stop()
      scheduledFor = -1
      return
    }
    if (scheduledFor === due && latchTimer.running) return
    scheduledFor = due
    latchTimer.interval = Math.max(1, due - Date.now())
    latchTimer.restart()
  }

  function playerKey(player) {
    if (!player) return ""
    return String(player.dbusName || player.desktopEntry || player.identity || player.uniqueId || "")
  }

  function findByKey(key) {
    if (!key) return null
    for (var i = 0; i < players.length; i++) {
      if (playerKey(players[i]) === key) return players[i]
    }
    return null
  }

  function playerAlive(player) {
    if (!player) return false
    for (var i = 0; i < players.length; i++) {
      if (players[i] === player) return true
    }
    return false
  }

  function isProxy(player) {
    if (!player) return false
    var dbus = String(player.dbusName || "").toLowerCase()
    var desktop = String(player.desktopEntry || "").toLowerCase()
    return dbus.indexOf("playerctld") !== -1 || desktop === "playerctld"
  }

  function hasTrack(player) {
    return !!(player && (player.trackTitle || player.trackArtist || player.trackArtUrl))
  }

  function isAvailable(player) {
    return !!(player && player.playbackState !== MprisPlaybackState.Stopped && hasTrack(player))
  }

  function availablePlayers() {
    var result = []
    for (var i = 0; i < players.length; i++) {
      if (isAvailable(players[i])) result.push(players[i])
    }
    return result
  }

  function findPreferred() {
    if (!preferredPlayerKey) return null
    for (var i = 0; i < sourcePlayers.length; i++) {
      if (playerKey(sourcePlayers[i]) === preferredPlayerKey) return sourcePlayers[i]
    }
    return null
  }

  function firstMatching(playing, proxy) {
    for (var i = 0; i < sourcePlayers.length; i++) {
      var player = sourcePlayers[i]
      if (!!player.isPlaying === playing && isProxy(player) === proxy) return player
    }
    return null
  }

  function chooseActivePlayer() {
    var preferred = findPreferred()
    if (preferred && preferred.isPlaying) return preferred

    return firstMatching(true, false)
      || firstMatching(true, true)
      || preferred
      || firstMatching(false, false)
      || firstMatching(false, true)
      || null
  }

  // The player to send commands to: whichever one the widget is actually
  // showing, and only while it is still on the bus, so a control press during
  // a gap cannot touch a corpse.
  function controlPlayer() {
    if (playerAlive(activePlayer)) return activePlayer
    if (playerAlive(livePlayer)) return livePlayer
    return null
  }

  function remember(player) {
    var key = playerKey(player)
    if (key) preferredPlayerKey = key
  }

  function playPause() {
    var player = controlPlayer()
    if (!player) return false

    if (player.isPlaying && player.canPause) player.pause()
    else if (!player.isPlaying && player.canPlay) player.play()
    else if (player.canTogglePlaying) player.togglePlaying()
    else return false

    remember(player)
    return true
  }

  function previous() {
    var player = controlPlayer()
    if (!player || !player.canGoPrevious) return false
    player.previous()
    remember(player)
    return true
  }

  function next() {
    var player = controlPlayer()
    if (!player || !player.canGoNext) return false
    player.next()
    remember(player)
    return true
  }

  function raisePlayer() {
    var player = controlPlayer()
    if (!player || !player.canRaise) return false
    player.raise()
    remember(player)
    return true
  }

  function statusObject() {
    var player = activePlayer
    return {
      available: hasMedia,
      playing: isPlaying,
      holding: holding,
      liveTitle: liveTitle,
      suspects: comSuspects,
      dbg: latch ? latch.debug() : null,
      liveHasMedia: liveHasMedia,
      player: player ? String(player.identity || player.desktopEntry || player.dbusName || "") : "",
      artist: artist,
      title: title,
      album: album,
      artUrl: artUrl,
      canGoPrevious: canGoPrevious,
      canGoNext: canGoNext
    }
  }

  IpcHandler {
    target: "crmne.mpris"

    function status(): string {
      return JSON.stringify(root.statusObject())
    }

    function playPause(): string {
      return root.playPause() ? "ok" : "unhandled"
    }

    function previous(): string {
      return root.previous() ? "ok" : "unhandled"
    }

    function next(): string {
      return root.next() ? "ok" : "unhandled"
    }

    function raise(): string {
      return root.raisePlayer() ? "ok" : "unhandled"
    }
  }
}
