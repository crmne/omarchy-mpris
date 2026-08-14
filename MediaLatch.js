// Decision machine for what the bar shows.
//
// Deliberately free of QML, Quickshell and real time: it takes a snapshot of
// the bus plus a timestamp and answers with a snapshot to display. That makes
// every case below reproducible in a test with a virtual clock, which matters
// because the interesting bugs here are all about *ordering* — a player that
// pauses one message before it switches sessions, metadata that arrives in
// pieces, an ad break that outlasts a fixed window.
//
// Players lie during a track change. The three shapes seen in the wild:
//
//   1. Metadata is cleared for a few hundred ms before the next track lands.
//   2. With more than one media session in one browser, the player briefly
//      advertises the *other* session — a paused video in another tab.
//   3. During an ad break, that other session can hold the bus for seconds.
//
// The host drives it: call update() whenever the bus changes, tick() when
// nextDeadline() comes due, and render committed().

var DEFAULTS = {
  graceMs: 1500,          // keep the current track this long after media vanishes
  settleMs: 350,          // how long a *suspicious* track must hold still
  lostPlayerGraceMs: 400, // shorter wait once the player has left the bus
  bounceMs: 1500,         // window in which a revert marks the interruption
  maxSuspects: 8,
  maxSuppressRounds: 20   // ceiling so a real handover is never locked out
}

function emptySnapshot() {
  return {
    hasMedia: false, key: "", title: "", artist: "", album: "", artUrl: "",
    playing: false, canGoPrevious: false, canGoNext: false, canPlayPause: false,
    playerKey: ""
  }
}

// title/artist/album identify a track. The art URL is excluded on purpose:
// players routinely send cover art a beat after the rest of the metadata, and
// that is the same track arriving in pieces, not a new one.
function trackKey(title, artist, album) {
  return String(title || "") + "" + String(artist || "") + "" + String(album || "")
}

function createLatch(options) {
  var cfg = {}
  for (var d in DEFAULTS) cfg[d] = DEFAULTS[d]
  if (options) {
    for (var o in options) if (options[o] !== undefined && options[o] !== null) cfg[o] = options[o]
  }

  var com = emptySnapshot()
  var live = emptySnapshot()
  var aliveKeys = []

  // What the committed track looked like when it was committed, while it was
  // still healthy. Classification compares against this rather than against
  // the committed state as it stands now: a player that pauses a beat before
  // it switches sessions would otherwise erase the very evidence that the
  // switch is not a real track change.
  var ref = { playing: false, canGoPrevious: false, canGoNext: false, canPlayPause: false }

  var suspects = []
  var displacedKey = ""
  var lastCommittedKey = ""
  var bounceUntil = -1
  var suppressRounds = 0
  var graceDueAt = -1
  var settleDueAt = -1

  function isSuspect(key) {
    return !!key && suspects.indexOf(key) !== -1
  }

  function markSuspect(key) {
    if (!key || isSuspect(key)) return
    suspects.push(key)
    while (suspects.length > cfg.maxSuspects) suspects.shift()
  }

  function clearSuspect(key) {
    var index = suspects.indexOf(key)
    if (index !== -1) suspects.splice(index, 1)
  }

  function committedPlayerAlive() {
    return !!com.playerKey && aliveKeys.indexOf(com.playerKey) !== -1
  }

  function suspiciousWait() {
    return Math.max(1, Math.max(cfg.settleMs, cfg.graceMs))
  }

  // How much reason there is to doubt an incoming track.
  //
  //   "none"   — commit at once, so an ordinary skip never waits
  //   "strong" — the shape of a background session, worth outwaiting an ad
  //   "weak"   — merely circumstantial; give it one window, then believe it
  //
  // The distinction matters. "It has no transport controls" is close to a
  // logical guarantee: you skipped, so whatever answers must have a next.
  // "It went quiet" is only a hint, and it is also what a video you just
  // opened paused looks like — holding that for the full ad-break budget
  // leaves the bar on the previous title for half a minute.
  function interloperStrength() {
    if (!com.hasMedia) return "none"

    // Someone pressed play on something else. A session that is playing while
    // the one on the bar is paused was chosen deliberately — a background tab
    // surfacing mid-skip is always paused, so nothing else looks like this.
    // Checked first, because a deliberate handover to a video tab trips every
    // other tell at once and would otherwise stay stuck behind them.
    if (live.playing && !com.playing) return "none"

    // Seen this exact track flash past before.
    if (isSuspect(live.key)) return "strong"

    // A session you cannot skip through is not the session you are skipping
    // through. This is what a background video tab looks like beside Spotify.
    // Only armed when the committed track had transport of its own, so moving
    // between two videos — neither of which has any — is not suspicious.
    if ((ref.canGoNext || ref.canGoPrevious) && !live.canGoNext && !live.canGoPrevious) return "strong"

    // Lost even play/pause: not a player state anyone asked for.
    if (ref.canPlayPause && !live.canPlayPause) return "strong"

    // Fell silent at the same instant the track changed.
    if (ref.playing && !live.playing) return "weak"

    // A different player, and not even playing, has no claim on the bar.
    if (com.playerKey && live.playerKey && !live.playing && com.playerKey !== live.playerKey) return "weak"

    return "none"
  }

  // Fields that change without it being a different track.
  function commitVolatile() {
    com.playerKey = live.playerKey
    com.artUrl = live.artUrl
    com.playing = live.playing
    com.canGoPrevious = live.canGoPrevious
    com.canGoNext = live.canGoNext
    com.canPlayPause = live.canPlayPause
  }

  // armBounce is false when this commit is itself a restoration after a
  // bounce. Re-arming there points the detector back the way it came, so an
  // A-B-A-B alternation reads every leg as a bounce and ends up learning the
  // real track as the interruption — precisely backwards.
  function commitAll(now, armBounce) {
    graceDueAt = -1
    settleDueAt = -1

    // Remember what this displaced. If the bus returns to it shortly, whatever
    // we are committing now was a flash, and gets recognised next time.
    var previous = com.key
    if (armBounce !== false && previous && previous !== live.key) {
      displacedKey = previous
      lastCommittedKey = live.key
      bounceUntil = now + cfg.bounceMs
    }

    clearSuspect(live.key)
    suppressRounds = 0

    com.hasMedia = true
    com.key = live.key
    com.title = live.title
    com.artist = live.artist
    com.album = live.album

    ref.playing = live.playing
    ref.canGoPrevious = live.canGoPrevious
    ref.canGoNext = live.canGoNext
    ref.canPlayPause = live.canPlayPause

    commitVolatile()
  }

  function commitEmpty() {
    graceDueAt = -1
    settleDueAt = -1
    suppressRounds = 0
    // Nothing is on the bar, so there is nothing left to have been displaced.
    bounceUntil = -1
    displacedKey = ""
    lastCommittedKey = ""
    var blank = emptySnapshot()
    for (var k in blank) com[k] = blank[k]
    ref.playing = false
    ref.canGoPrevious = false
    ref.canGoNext = false
    ref.canPlayPause = false
  }

  function evaluate(now) {
    if (!live.hasMedia) {
      settleDueAt = -1
      if (!com.hasMedia) return
      if (cfg.graceMs <= 0) { commitEmpty(); return }
      if (graceDueAt < 0) {
        graceDueAt = now + Math.max(1, committedPlayerAlive()
          ? cfg.graceMs : Math.min(cfg.graceMs, cfg.lostPlayerGraceMs))
      }
      return
    }

    graceDueAt = -1

    // Same track: playback state and late-arriving art go straight through, so
    // pressing play never waits on a settle window.
    if (com.hasMedia && live.key === com.key) {
      settleDueAt = -1
      // The bus is back on what the bar shows, so whatever was interrupting is
      // over. Hand back the rounds it spent: the budget exists to bound one
      // interruption, and charging every future one against the same total
      // means a long listening session eventually runs out and lets a
      // background tab through.
      suppressRounds = 0
      commitVolatile()
      return
    }

    // Nothing on screen yet, or settling disabled: show it at once.
    if (!com.hasMedia || cfg.settleMs <= 0) { commitAll(now); return }

    // The bus has come back to what we just displaced, so what we committed in
    // between never really happened. Learn it, and restore at once.
    if (bounceUntil >= 0 && now < bounceUntil && live.key === displacedKey) {
      markSuspect(lastCommittedKey)
      bounceUntil = -1
      displacedKey = ""
      lastCommittedKey = ""
      commitAll(now, false)
      return
    }

    var strength = interloperStrength()

    // Nothing suspicious about it: straight to the bar, no delay.
    if (strength === "none") { commitAll(now); return }

    if (settleDueAt < 0) {
      settleDueAt = now + (strength === "strong" ? suspiciousWait() : Math.max(1, cfg.settleMs))
    }
  }

  function tick(now) {
    var fired = false

    if (graceDueAt >= 0 && now >= graceDueAt) {
      commitEmpty()
      evaluate(now)
      fired = true
    }

    if (settleDueAt >= 0 && now >= settleDueAt) {
      settleDueAt = -1
      fired = true
      if (!live.hasMedia) {
        evaluate(now)
      } else if (interloperStrength() === "strong" && suppressRounds < cfg.maxSuppressRounds) {
        // Still looks wrong, so keep refusing it. One window is not enough: a
        // Spotify ad break parks the real session for far longer than any
        // fixed wait, and the background tab would win by outlasting it.
        // Only a strong tell earns this; a weak one has had its window and is
        // taken at its word.
        suppressRounds++
        settleDueAt = now + suspiciousWait()
      } else {
        commitAll(now)
      }
    }

    return fired
  }

  function update(nextLive, alivePlayerKeys, now) {
    live = nextLive
    aliveKeys = alivePlayerKeys || []
    evaluate(now)

    // The player went away mid-grace: nothing is coming back, so cut the wait
    // short rather than showing a stale track for the full window.
    if (graceDueAt >= 0 && !committedPlayerAlive()) {
      var shortened = now + Math.max(1, Math.min(cfg.graceMs, cfg.lostPlayerGraceMs))
      if (shortened < graceDueAt) graceDueAt = shortened
    }
  }

  return {
    config: cfg,
    update: update,
    tick: tick,
    committed: function () {
      var copy = {}
      for (var k in com) copy[k] = com[k]
      return copy
    },
    nextDeadline: function () {
      var due = -1
      if (graceDueAt >= 0) due = graceDueAt
      if (settleDueAt >= 0 && (due < 0 || settleDueAt < due)) due = settleDueAt
      return due
    },
    // Introspection for the status IPC and for tests.
    debug: function () {
      return {
        suspects: suspects.slice(),
        suppressRounds: suppressRounds,
        graceDueAt: graceDueAt,
        settleDueAt: settleDueAt,
        holding: com.hasMedia && (!live.hasMedia || live.key !== com.key)
      }
    }
  }
}

// QML imports the top-level functions directly and never sees this; node uses
// it to require the very same file the shell runs.
if (typeof module !== "undefined" && module.exports) {
  module.exports = { createLatch: createLatch, trackKey: trackKey, emptySnapshot: emptySnapshot, DEFAULTS: DEFAULTS }
}
