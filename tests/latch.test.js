// Unit tests for MediaLatch.js — the same file the shell loads.
//
// Every case here is one that was observed on a real bus while building this,
// recorded from `omarchy-shell crmne.mpris status` against Spotify Web in
// Chromium with a second media tab open. The comments name what was seen.
//
//   node --test tests/

const { test } = require('node:test')
const assert = require('node:assert')
const { createLatch, trackKey, emptySnapshot } = require('../MediaLatch.js')

// ── Harness ───────────────────────────────────────────────────────────────
// A virtual clock. Real time never enters, so an ad break lasting eight
// seconds costs the test nothing and never flakes.
class Driver {
  constructor (config) {
    this.latch = createLatch(config)
    this.now = 0
    this.alive = ['chromium']
    this.live = { ...emptySnapshot(), playerKey: 'chromium' }
  }

  // Push a new bus state at the current time.
  set (live) {
    this.live = live
    this.latch.update(live, this.alive, this.now)
    return this
  }

  // Advance the clock, firing every timer that comes due on the way.
  advance (ms) {
    const target = this.now + ms
    for (let guard = 0; guard < 1000; guard++) {
      const due = this.latch.nextDeadline()
      if (due < 0 || due > target) break
      this.now = Math.max(this.now, due)
      this.latch.tick(this.now)
    }
    this.now = target
    return this
  }

  bar () { return this.latch.committed() }
  debug () { return this.latch.debug() }
  title () { return this.latch.committed().title }
}

// ── Bus fixtures ──────────────────────────────────────────────────────────
// Spotify: a real music session — playing, and skippable.
function spotify (title, opts = {}) {
  const artist = opts.artist ?? 'Artist'
  const album = opts.album ?? 'Album'
  return {
    hasMedia: true,
    key: trackKey(title, artist, album),
    title, artist, album,
    artUrl: opts.artUrl ?? 'file:///art-' + title + '.png',
    playing: opts.playing ?? true,
    canGoPrevious: opts.canGoPrevious ?? true,
    canGoNext: opts.canGoNext ?? true,
    canPlayPause: opts.canPlayPause ?? true,
    playerKey: opts.playerKey ?? 'chromium'
  }
}

// The background video tab. This is the exact shape that kept stealing the
// bar: no transport controls at all, and paused unless the user starts it.
const YT_TITLE = "I'M TESTING THIS *CRAZY* 1000HZ MONITOR ?!! | SCREAM"
function youtube (opts = {}) {
  return {
    hasMedia: true,
    key: trackKey(YT_TITLE, 'ScreaM', ''),
    title: YT_TITLE, artist: 'ScreaM', album: '',
    artUrl: 'file:///yt.png',
    playing: opts.playing ?? false,
    canGoPrevious: false,
    canGoNext: false,
    canPlayPause: opts.canPlayPause ?? true,
    playerKey: opts.playerKey ?? 'chromium'
  }
}

// Metadata cleared: what a browser reports for a few hundred ms mid-skip.
function blank (playerKey = 'chromium') {
  return { ...emptySnapshot(), playerKey }
}

// ── Baseline ──────────────────────────────────────────────────────────────

test('first track appears immediately, with nothing to protect', () => {
  const d = new Driver()
  d.set(spotify('Fly High'))
  assert.strictEqual(d.title(), 'Fly High')
})

test('an ordinary skip commits with zero delay', () => {
  const d = new Driver()
  d.set(spotify('Fly High'))
  d.set(spotify('LEVELS'))
  // No advance() at all: the classifier saw nothing wrong, so it did not wait.
  assert.strictEqual(d.title(), 'LEVELS')
})

test('pause and resume on the same track are instant', () => {
  const d = new Driver()
  d.set(spotify('Fly High'))
  d.set(spotify('Fly High', { playing: false }))
  assert.strictEqual(d.bar().playing, false)
  assert.strictEqual(d.title(), 'Fly High', 'pausing must not disturb the title')
  d.set(spotify('Fly High', { playing: true }))
  assert.strictEqual(d.bar().playing, true)
})

test('cover art arriving late updates art without a second track change', () => {
  const d = new Driver()
  d.set(spotify('Fly High', { artUrl: '' }))
  const keyBefore = d.bar().key
  d.set(spotify('Fly High', { artUrl: 'file:///late.png' }))
  assert.strictEqual(d.bar().artUrl, 'file:///late.png')
  assert.strictEqual(d.bar().key, keyBefore, 'late art must not read as a new track')
})

// ── Failure mode 1: metadata blanks mid-skip ──────────────────────────────

test('a blank-metadata gap shorter than the grace window is invisible', () => {
  const d = new Driver()
  d.set(spotify('LEVELS'))
  d.set(blank())                       // observed: ~300-350 ms of nothing
  d.advance(300)
  assert.strictEqual(d.title(), 'LEVELS', 'the bar must not empty out mid-skip')
  assert.strictEqual(d.debug().holding, true)
  d.set(spotify('Self Aware'))
  assert.strictEqual(d.title(), 'Self Aware')
})

test('media that never comes back clears the bar after the grace window', () => {
  const d = new Driver()
  d.set(spotify('LEVELS'))
  d.set(blank())
  d.advance(1400)
  assert.strictEqual(d.title(), 'LEVELS', 'still inside the window')
  d.advance(200)
  assert.strictEqual(d.bar().hasMedia, false, 'past the window the bar clears')
})

test('a player leaving the bus mid-grace clears sooner', () => {
  const d = new Driver()
  d.set(spotify('LEVELS'))
  d.alive = []                          // browser quit
  d.set(blank())
  d.advance(500)
  assert.strictEqual(d.bar().hasMedia, false, 'no point waiting 1500 ms for a corpse')
})

// ── Failure mode 2: another media session surfaces mid-skip ───────────────

test('the background video tab never reaches the bar', () => {
  const d = new Driver()
  d.set(spotify('Art of Guitar'))
  d.set(youtube())                      // observed: ~160 ms of the wrong track
  d.advance(160)
  assert.strictEqual(d.title(), 'Art of Guitar', 'a tab with no transport cannot take the bar')
  d.set(spotify('garbanzo'))
  assert.strictEqual(d.title(), 'garbanzo', 'and the real track still lands instantly')
})

test('pausing one message before the flip does not destroy the evidence', () => {
  // The regression that made the classifier leak. Spotify pauses first, so the
  // committed state is already silent by the time the other session arrives;
  // classification has to compare against the reference profile captured when
  // the track was committed, not against the committed state as it stands.
  const d = new Driver()
  d.set(spotify("I'm So Excited"))
  d.set(spotify("I'm So Excited", { playing: false }))   // pause lands first
  d.set(youtube())                                        // then the flip
  d.advance(200)
  assert.strictEqual(d.title(), "I'm So Excited", 'must still be recognised as an interloper')
})

test('an ad break cannot win by outlasting a fixed window', () => {
  // Observed twice: the video tab held the bus for 1497 ms and 1499 ms, just
  // past a 1500 ms wait, and took the bar both times.
  const d = new Driver()
  d.set(spotify('The Less I Know The Better'))
  d.set(youtube())
  d.advance(8000)                        // far past any single settle window
  assert.strictEqual(d.title(), 'The Less I Know The Better')
  d.set(spotify('Take Me (To The Moon)'))
  assert.strictEqual(d.title(), 'Take Me (To The Moon)')
})

test('suppression gives up eventually rather than locking a session out', () => {
  const d = new Driver()
  d.set(spotify('NOW OR NEVER'))
  d.set(youtube())
  d.advance(1000 * 60 * 2)               // two minutes of refusing
  assert.strictEqual(d.bar().title, YT_TITLE,
    'past the round cap the bar has to accept what is actually there')
})

test('the suppression budget is per interruption, not per session', () => {
  // Regression: suppressRounds was only reset on commit, so every absorbed
  // flip spent from one shared budget. After about twenty skips — an evening's
  // listening — the next interruption exhausted it and took the bar for good.
  const d = new Driver()
  d.set(spotify('Song'))
  for (let i = 0; i < 40; i++) {
    d.set(youtube())
    d.advance(2000)               // a full suppression round elapses
    assert.strictEqual(d.title(), 'Song', `interruption ${i} should still be absorbed`)
    d.set(spotify('Song'))        // the bus reverts; the interruption is over
    d.advance(10)
  }
})

test('an interruption that ends resets the budget it was spending', () => {
  const d = new Driver()
  d.set(spotify('Song'))
  d.set(youtube())
  d.advance(4000)
  assert.ok(d.debug().suppressRounds > 0, 'should have spent rounds while refusing')
  d.set(spotify('Song'))
  assert.strictEqual(d.debug().suppressRounds, 0, 'and get them back once it is over')
})

test('clearing the bar forgets pending bounce bookkeeping', () => {
  const d = new Driver()
  d.set(spotify('A'))
  d.set(spotify('B'))             // arms the bounce detector
  d.set(blank())
  d.advance(2000)                 // grace expires, bar clears
  assert.strictEqual(d.bar().hasMedia, false)
  d.set(spotify('A'))
  assert.deepStrictEqual(d.debug().suspects, [], 'a stale bounce must not teach it anything')
})

// ── Failure mode 3: the user deliberately switches ────────────────────────

test('pausing Spotify and playing the video tab hands the bar over at once', () => {
  // The stuck case: every interloper tell fires on a deliberate handover — no
  // transport controls, a known suspect key, a capability drop — so without an
  // override the bar sits on the paused track for the whole suppression cap.
  const d = new Driver()
  d.set(spotify('Say My Name - Remix'))
  d.set(spotify('Say My Name - Remix', { playing: false }))  // user pauses Spotify
  d.set(youtube({ playing: true }))                          // user plays YouTube
  assert.strictEqual(d.bar().title, YT_TITLE, 'no wait: this was chosen deliberately')
  assert.strictEqual(d.bar().playing, true)
})

test('the handover override does not let a playing tab steal from a playing track', () => {
  const d = new Driver()
  d.set(spotify('Boston'))               // still playing
  d.set(youtube({ playing: true }))      // flips while Spotify plays
  d.advance(300)
  assert.strictEqual(d.title(), 'Boston', 'committed track is playing, so this is still a flash')
})

test('a genuine switch to another real player is accepted', () => {
  const d = new Driver()
  d.alive = ['chromium', 'vlc']
  d.set(spotify('Boston'))
  d.set(spotify('Boston', { playing: false }))
  d.set(spotify('Some Film', { playerKey: 'vlc', playing: true }))
  assert.strictEqual(d.title(), 'Some Film')
})

// ── When the video tab is the main event, not the interruption ────────────

// A second video session: like `youtube()`, no transport controls either.
function video (title, opts = {}) {
  return {
    hasMedia: true,
    key: trackKey(title, 'Channel', ''),
    title, artist: 'Channel', album: '',
    artUrl: 'file:///v.png',
    playing: opts.playing ?? true,
    canGoPrevious: false,
    canGoNext: false,
    canPlayPause: true,
    playerKey: 'chromium'
  }
}

test('moving between two video tabs is never delayed', () => {
  // Neither has transport controls, so the capability tell must not arm —
  // it is only meaningful when the track being replaced had controls itself.
  const d = new Driver()
  d.set(video('Video A'))
  d.set(video('Video B'))
  assert.strictEqual(d.title(), 'Video B')
})

test('a video that opens paused is shown promptly, not held for an ad break', () => {
  // Regression: "fell silent as it changed" is circumstantial, but it used to
  // buy the full multi-round budget, so opening a video that did not autoplay
  // left the previous title on the bar for over thirty seconds.
  const d = new Driver()
  d.set(video('Video A'))
  d.set(video('Video B', { playing: false }))
  d.advance(400)
  assert.strictEqual(d.title(), 'Video B', 'one settle window is enough for a weak tell')
})

test('pressing play on a newly opened video commits it at once', () => {
  const d = new Driver()
  d.set(video('Video A'))
  d.set(video('Video B', { playing: false }))
  d.set(video('Video B', { playing: true }))
  assert.strictEqual(d.title(), 'Video B')
})

test('a weak tell still absorbs a brief flash', () => {
  const d = new Driver()
  d.set(video('Video A'))
  d.set(video('Video B', { playing: false }))
  d.advance(100)                       // inside the single settle window
  assert.strictEqual(d.title(), 'Video A')
  d.set(video('Video A'))              // it was only a flash
  assert.strictEqual(d.title(), 'Video A')
})

// ── Learning ──────────────────────────────────────────────────────────────

test('a track that flashes past and reverts is remembered', () => {
  const d = new Driver()
  d.set(spotify('SPA'))
  // Make it slip through once by looking entirely normal.
  d.set(spotify('Advertisement', { canGoNext: true, canGoPrevious: true }))
  assert.strictEqual(d.title(), 'Advertisement')
  d.set(spotify('SPA'))                  // bus bounces straight back
  assert.strictEqual(d.title(), 'SPA')
  assert.ok(d.debug().suspects.includes(trackKey('Advertisement', 'Artist', 'Album')),
    'the flash should have been learned')
})

test('a learned suspect is refused on sight the next time', () => {
  const d = new Driver()
  d.set(spotify('SPA'))
  d.set(spotify('Advertisement', { canGoNext: true, canGoPrevious: true }))
  d.set(spotify('SPA'))                  // learn it
  d.set(spotify('Advertisement', { canGoNext: true, canGoPrevious: true }))
  d.advance(200)
  assert.strictEqual(d.title(), 'SPA', 'second time it never reaches the bar')
})

test('a suspect that genuinely sticks is forgiven', () => {
  const d = new Driver()
  d.set(spotify('SPA'))
  d.set(spotify('Advertisement', { canGoNext: true, canGoPrevious: true }))
  d.set(spotify('SPA'))
  d.set(spotify('Advertisement', { canGoNext: true, canGoPrevious: true }))
  d.advance(1000 * 60 * 2)               // it really is playing
  assert.strictEqual(d.title(), 'Advertisement')
  assert.ok(!d.debug().suspects.includes(trackKey('Advertisement', 'Artist', 'Album')),
    'having earned its place it should no longer be a suspect')
})

test('alternating tracks never teach it that the real track is the interruption', () => {
  // Regression: restoring after a bounce used to re-arm the detector pointing
  // back the way it came, so an A-B-A-B alternation read every leg as a bounce
  // and marked the real track as the suspect.
  const d = new Driver()
  const real = trackKey('SPA', 'Artist', 'Album')
  d.set(spotify('SPA'))
  for (let i = 0; i < 4; i++) {
    d.set(spotify('Advertisement', { canGoNext: true, canGoPrevious: true }))
    d.advance(50)
    d.set(spotify('SPA'))
    d.advance(50)
  }
  assert.ok(!d.debug().suspects.includes(real), 'the real track must never become a suspect')
})

test('the suspect list is bounded', () => {
  const d = new Driver()
  d.set(spotify('base'))
  for (let i = 0; i < 20; i++) {
    d.set(spotify('flash' + i, { canGoNext: true, canGoPrevious: true }))
    d.set(spotify('base'))
  }
  assert.ok(d.debug().suspects.length <= 8, 'must not grow without bound')
})

// ── A suspicion is a guess, and is treated like one ───────────────────────

test('a learned suspect costs one window, not an ad break', () => {
  // Regression, caught by the integration suite's `clean` control: a track
  // learned as a suspect used to be a strong tell, so playing it deliberately
  // later held the bar on the previous title for tens of seconds.
  const d = new Driver()
  const flash = 'Genesis'
  d.set(spotify('Nightcall'))
  d.set(spotify(flash))                 // slips through looking normal
  d.set(spotify('Nightcall'))           // bounces back, so it is learned
  assert.ok(d.debug().suspects.length > 0, 'precondition: it was learned')

  d.set(spotify(flash))                 // now played for real
  d.advance(400)
  assert.strictEqual(d.title(), flash, 'one settle window, then believed')
})

test('suspicions expire', () => {
  const d = new Driver()
  d.set(spotify('Nightcall'))
  d.set(spotify('Genesis'))
  d.set(spotify('Nightcall'))
  assert.ok(d.debug().suspects.length > 0)
  d.advance(6 * 60 * 1000)              // past the five minute TTL

  // Asserted through behaviour rather than the list: committing with no delay
  // at all is what "no longer a suspect" means. A live suspicion would still
  // cost one settle window.
  d.set(spotify('Genesis'))
  assert.strictEqual(d.title(), 'Genesis',
    'a flash from ten minutes ago says nothing about now')
  assert.deepStrictEqual(d.debug().suspects, [], 'and the entry is gone')
})

test('a suspect still absorbs the flash it was learned for', () => {
  const d = new Driver()
  d.set(spotify('Nightcall'))
  d.set(spotify('Genesis'))
  d.set(spotify('Nightcall'))
  d.set(spotify('Genesis'))             // flashes again
  d.advance(100)                        // inside the window
  assert.strictEqual(d.title(), 'Nightcall', 'absorbed, which is the point')
})

// ── Shapes I could not rule out by reading ────────────────────────────────

test('an interloper that DOES have transport controls gets one window', () => {
  // A second music session — YouTube Music, a podcast app — defeats the
  // capability tell, since it has next/previous like the real one. Only the
  // circumstantial "went quiet" tell is left, so a brief flash is absorbed
  // and anything persistent is accepted. Documented rather than claimed.
  const d = new Driver()
  d.set(spotify('Real Track'))
  d.set(spotify('Podcast Episode', { playing: false, artist: 'Some Show' }))
  d.advance(100)
  assert.strictEqual(d.title(), 'Real Track', 'a brief flash is still absorbed')
  d.advance(500)
  assert.strictEqual(d.title(), 'Podcast Episode', 'but it is believed if it persists')
})

test('metadata arriving in pieces settles on the finished track', () => {
  // Players fill the title in before the artist. Each partial state is a
  // different key, so this must not commit twice or strand a half-track.
  const d = new Driver()
  d.set(spotify('Old Song'))
  d.set(spotify('New Song', { artist: '' }))
  d.set(spotify('New Song', { artist: 'Real Artist' }))
  d.advance(600)
  assert.strictEqual(d.title(), 'New Song')
  assert.strictEqual(d.bar().artist, 'Real Artist')
})

test('a gap that ends on a different track commits the new one', () => {
  const d = new Driver()
  d.set(spotify('Before'))
  d.set(blank())
  d.advance(200)
  assert.strictEqual(d.title(), 'Before', 'bridged')
  d.set(spotify('After'))
  assert.strictEqual(d.title(), 'After', 'and the new track lands at once')
})

test('holding down next does not strand the bar on an early track', () => {
  const d = new Driver()
  d.set(spotify('Start'))
  for (let i = 0; i < 12; i++) {
    d.set(spotify('Rapid ' + i))
    d.advance(60)
  }
  d.advance(1000)
  assert.strictEqual(d.title(), 'Rapid 11', 'ends on whatever was last')
})

test('a paused player with metadata is still shown', () => {
  // Paused is not absent. The widget dims the label rather than hiding it.
  const d = new Driver()
  d.set(spotify('Paused Song', { playing: false }))
  assert.strictEqual(d.title(), 'Paused Song')
  assert.strictEqual(d.bar().playing, false)
})

test('stopping and starting again re-commits', () => {
  const d = new Driver()
  d.set(spotify('Song'))
  d.set(blank())
  d.advance(2000)
  assert.strictEqual(d.bar().hasMedia, false)
  d.set(spotify('Song'))
  assert.strictEqual(d.title(), 'Song', 'nothing on the bar, so no reason to wait')
})

test('track keys cannot alias across the title and artist boundary', () => {
  // The key is a join, so a title containing the separator must not collide
  // with a different title/artist split.
  assert.notStrictEqual(trackKey('A␟B', '', ''), trackKey('A', 'B', ''))
  assert.notStrictEqual(trackKey('Song', 'Artist', ''), trackKey('Song', '', 'Artist'))
})

test('changing the grace setting at runtime takes effect', () => {
  const d = new Driver()
  d.set(spotify('Song'))
  d.latch.config.graceMs = 100
  d.set(blank())
  d.advance(300)
  assert.strictEqual(d.bar().hasMedia, false, 'the shorter window applies')
})

// ── Configuration ─────────────────────────────────────────────────────────

test('settleMs of 0 disables absorption entirely', () => {
  const d = new Driver({ settleMs: 0 })
  d.set(spotify('Art of Guitar'))
  d.set(youtube())
  assert.strictEqual(d.bar().title, YT_TITLE, 'opted out, so nothing is filtered')
})

test('graceMs of 0 clears the bar the moment metadata goes', () => {
  const d = new Driver({ graceMs: 0 })
  d.set(spotify('LEVELS'))
  d.set(blank())
  assert.strictEqual(d.bar().hasMedia, false)
})

// ── Full reproduction ─────────────────────────────────────────────────────

test('replays a recorded Spotify Web session without showing one wrong track', () => {
  // Transcribed from a real 85 s recording: each entry is [ms, bus state].
  // Interleaved blanks and video-tab flips are exactly as they were observed.
  const d = new Driver()
  const feed = [
    [0,     spotify('think you are someone new')],
    [11262, youtube()],
    [12750, spotify('think you are someone new')],
    [14569, youtube()],
    [17658, spotify('think you are someone new')],
    [18470, youtube({ playing: true })],
    [18578, spotify('think you are someone new')],
    [18655, spotify('NOW OR NEVER')],
    [27647, youtube()],
    [30814, spotify('NOW OR NEVER')],
    [31901, blank()],
    [31944, youtube({ playing: true })],
    [32071, spotify('NOW OR NEVER')],
    [32160, spotify('Hurt You')],
    [33661, blank()],
    [33701, youtube({ playing: true })],
    [33805, spotify('Hurt You')],
    [34056, spotify('The Rhythm of the Night')],
    [35639, youtube()],
    [35863, spotify('Hurt You')],
    [37958, spotify('The Rhythm of the Night')],
    [54007, youtube()],
    [57901, spotify('The Rhythm of the Night')],
    [59881, youtube()],
    [62010, spotify('The Rhythm of the Night')]
  ]

  const shown = new Set()
  let clock = 0
  for (const [at, state] of feed) {
    d.advance(at - clock)
    clock = at
    d.set(state)
    if (d.bar().hasMedia) shown.add(d.bar().title)
  }

  assert.ok(!shown.has(YT_TITLE), 'the video tab must never have appeared on the bar')
  assert.ok(!shown.has(''), 'the bar must never have gone blank')
  assert.deepStrictEqual([...shown], [
    'think you are someone new', 'NOW OR NEVER', 'Hurt You', 'The Rhythm of the Night'
  ], 'only the four real tracks, each committed once, in order')
})

test('every real track in the recording is still reached', () => {
  // Absorption is only worth anything if it does not also swallow real music.
  const d = new Driver()
  const tracks = ['I Run', 'Key To My Heart', 'Pineapple', 'Lose U', 'Kisses', 'Way Too Self Aware']
  d.set(spotify('Say My Name - Remix'))
  for (const t of tracks) {
    d.set(youtube())          // the flip that precedes every skip
    d.advance(120)
    d.set(spotify(t))         // the real track
    assert.strictEqual(d.title(), t, `${t} should be on the bar with no delay`)
  }
})
