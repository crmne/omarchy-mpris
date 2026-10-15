# Media Controls + Album Art for Omarchy

A native Quattro/Quickshell now-playing widget for the Omarchy bar, with media
controls, live album art, and artist/title details:

![Media Controls + Album Art in the Omarchy bar](preview.png)

`previous` · `play/pause` · `next` · `album art` · `artist — title`

On crowded horizontal bars, the widget adapts independently on each monitor.
It shortens the label first, then drops previous/next, play/pause, and artwork
as necessary so it gives space back before the bar sections overlap. The full
track details remain available in the tooltip.

Adaptive sizing measures the visible slots in each bar window, including on
hosts that expose the restricted plugin bar API. It applies in the left and
right sections; centered placement still needs layout cooperation from the
host. If even the compact control cannot fit, the widget temporarily hides
until space is available again.

It works with Spotify and other Linux media players that expose the standard
MPRIS interface. The widget uses Quickshell's MPRIS service directly: it does
not poll `playerctl`, download cover art into `/tmp`, or depend on the old
Waybar scripts. It also works on custom or cloned bars, which do not receive
the shell's plugin services: there the widget runs its own copy of the
service.

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

Click album art or the label to raise the player, and middle-click there for
the previous track. Scrolling anywhere over the controls changes track.
Right-click any part of the widget to open its appearance panel.

The appearance panel and Omarchy bar settings expose adaptive layout,
transport controls, album artwork, artist visibility, album-art size, label
width, and a maximum artist/title character count.

## Screenshots

`preview.png` shows the actual widget and its appearance panel with synthetic
data: an invented artist and tracks and a self-drawn abstract cover. The top
bar shows the full layout while playing; the smaller bar is a narrower bar
where adaptive sizing has dropped previous/next for a paused track.

`tools/capture/` copies the production `BarWidget.qml`, `BarGeometry.js`,
`ServiceSource.qml` and `TextLimit.js` into a temporary offscreen Quickshell
host with Omarchy's installed `Commons` and `Ui`, the Ristretto theme, and
JetBrainsMono Nerd Font. `Service.qml` is replaced by a fixture with no MPRIS
import, so the capture never sees or controls a real media player. The
workspaces, clock and tray icons beside the widget are plain stand-ins drawn
with the bar's font and colors. The background is Omarchy's Ristretto
wallpaper, blurred and darkened.

```bash
gpu-lock /usr/bin/python3 -B tools/capture/capture.py [captures-dir]
```

`gpu-lock` is the maintainer's machine-wide GPU mutex. The script requests
OpenGL and refuses a software-rendered capture.

## Validation

Run the geometry, service-lookup, and label-truncation regression tests with
Qt Quick Test:

```bash
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests
```
