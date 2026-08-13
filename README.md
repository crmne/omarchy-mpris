# crmne MPRIS for Omarchy

A native Quattro/Quickshell bar plugin that restores the media cluster from the
old Waybar setup:

![MPRIS + Album Art in the Omarchy bar](preview.png)

`previous` · `play/pause` · `next` · `album art` · `artist — title`

The widget uses Quickshell's MPRIS service directly. It does not poll
`playerctl`, download cover art into `/tmp`, or depend on the old Waybar
scripts.

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

Click album art or the label to raise the player. Middle/right click there go
to the previous/next track. Scrolling anywhere over the controls also changes
track.

The Omarchy bar settings UI exposes album-art size, label width, and whether
the artist is shown.
