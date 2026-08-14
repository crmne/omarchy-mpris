# Media Controls + Album Art for Omarchy

A native Quattro/Quickshell now-playing widget for the Omarchy bar, with media
controls, live album art, and artist/title details:

![Media Controls + Album Art in the Omarchy bar](preview.png)

`previous` · `play/pause` · `next` · `album art` · `artist — title`

It works with Spotify and other Linux media players that expose the standard
MPRIS interface. The widget uses Quickshell's MPRIS service directly: it does
not poll `playerctl`, download cover art into `/tmp`, or depend on the old
Waybar scripts.

## Install

```bash
omarchy plugin add https://github.com/crmne/omarchy-mpris.git --enable --yes
omarchy bar move crmne.mpris --section right --before omarchy.tray
```

## Requirements

- Omarchy Quattro with its Quickshell-based shell.
- At least one media player exposing the standard MPRIS interface.

There are no additional packages or helper scripts. In particular, this plugin
uses Quickshell's MPRIS service directly and does not require `playerctl`.

## Tests

The logic that decides what the bar shows lives in `MediaLatch.js`, free of QML
and of real time, so it can be driven with a virtual clock:

```bash
node --test tests/latch.test.js     # 23 cases, no shell needed, instant
```

Each case is one observed against a real bus — a metadata gap mid-skip, a
second media session in the same browser surfacing for 200 ms, an ad break that
outlasts a fixed window, a deliberate switch to a paused tab — plus a replay of
a recorded 85-second Spotify Web session.

End-to-end coverage puts a fake Chromium on the real session bus and reads back
what the running shell committed:

```bash
tests/integration.sh          # all scenarios
tests/integration.sh flip     # just one
```

Pause and close other media first: a real player on the bus competes with the
fake for selection and the results stop meaning anything. The script warns when
it sees one.

The fake player needs `python-dbus` and `python-gobject`. Arch installs those
into the system interpreter only, so if a version manager (mise, pyenv, asdf)
owns `python3` the script falls back to `/usr/bin/python3` on its own and says
so. Install them with `omarchy pkg add python-dbus python-gobject`.

## Remove

```bash
omarchy plugin remove crmne.mpris --yes
```

For local development, put or link this repository at
`~/.config/omarchy/plugins/crmne.mpris` and run:

```bash
omarchy-shell shell rescanPlugins
omarchy plugin enable crmne.mpris --section right --before omarchy.tray
```

Click album art or the label to raise the player. Middle/right click there go
to the previous/next track. Scrolling anywhere over the controls also changes
track.

The Omarchy bar settings UI exposes album-art size, label width, and whether
the artist is shown.
