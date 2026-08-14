#!/usr/bin/env python3
"""A fake Chromium on the real session bus, for end-to-end tests.

The unit tests in latch.test.js drive the decision machine directly. This
drives the whole stack instead — D-Bus, Quickshell's MPRIS service, the running
shell, the widget — by impersonating the thing that actually misbehaves.

Chromium exposes ONE MPRIS name for the whole browser and swings its metadata
between media sessions. That single detail is what makes the widget hard: the
interruption is not a second player you can tell apart by name, it is the same
player briefly describing a different track.

Scenarios (see --scenario):
  flip      skip where the video session surfaces for ~200 ms in between
  blank     skip where metadata is cleared for ~350 ms in between
  adbreak   the video session holds the bus for 5 s, as during a Spotify ad
  handover  music is paused, then the video session is genuinely played
  clean     a well-behaved atomic skip, as a control

Usage:
  fake_chromium.py --scenario flip --repeat 3
"""
import argparse
import sys
import time

import dbus
import dbus.mainloop.glib
import dbus.service
from gi.repository import GLib

BUS_NAME = "org.mpris.MediaPlayer2.chromium.instance_omatest"
OBJ_PATH = "/org/mpris/MediaPlayer2"
ROOT_IFACE = "org.mpris.MediaPlayer2"
PLAYER_IFACE = "org.mpris.MediaPlayer2.Player"
PROPS_IFACE = "org.freedesktop.DBus.Properties"

# The two sessions, exactly as the real ones present themselves.
VIDEO_TITLE = "FAKE VIDEO TAB | should never reach the bar"
MUSIC = [
    ("Nightcall", "Kavinsky", "OutRun"),
    ("Genesis", "Justice", "Cross"),
    ("Sun", "Two Door Cinema Club", "Beacon"),
    ("Desire", "Years & Years", "Communion"),
]


def log(msg):
    print(f"[{time.monotonic():.3f}] fake  {msg}", flush=True)


def meta(title, artist, album, index):
    return dbus.Dictionary({
        "mpris:trackid": dbus.ObjectPath(f"/org/chromium/MediaPlayer2/TrackList/Track{index}"),
        "mpris:length": dbus.Int64(210_000_000),
        "xesam:title": dbus.String(title),
        "xesam:artist": dbus.Array([dbus.String(artist)], signature="s"),
        "xesam:album": dbus.String(album),
        "mpris:artUrl": dbus.String("file:///tmp/oma-test-art.png"),
    }, signature="sv")


class FakeChromium(dbus.service.Object):
    def __init__(self, bus, args):
        super().__init__(bus, OBJ_PATH)
        self.args = args
        self.index = 0
        self.done = False
        title, artist, album = MUSIC[0]
        self.props = {
            ROOT_IFACE: {
                "Identity": dbus.String("Chromium"),
                "DesktopEntry": dbus.String("chromium"),
                "CanQuit": dbus.Boolean(True),
                "CanRaise": dbus.Boolean(True),
                "HasTrackList": dbus.Boolean(False),
                "SupportedUriSchemes": dbus.Array([], signature="s"),
                "SupportedMimeTypes": dbus.Array([], signature="s"),
            },
            PLAYER_IFACE: {
                "PlaybackStatus": dbus.String("Playing"),
                "LoopStatus": dbus.String("None"),
                "Rate": dbus.Double(1.0),
                "MinimumRate": dbus.Double(1.0),
                "MaximumRate": dbus.Double(1.0),
                "Shuffle": dbus.Boolean(False),
                "Volume": dbus.Double(1.0),
                "Position": dbus.Int64(0),
                "Metadata": meta(title, artist, album, 0),
                "CanGoNext": dbus.Boolean(True),
                "CanGoPrevious": dbus.Boolean(True),
                "CanPlay": dbus.Boolean(True),
                "CanPause": dbus.Boolean(True),
                "CanSeek": dbus.Boolean(False),
                "CanControl": dbus.Boolean(True),
            },
        }

    # ── properties ────────────────────────────────────────────────────────
    @dbus.service.method(PROPS_IFACE, in_signature="ss", out_signature="v")
    def Get(self, iface, prop):
        return self.props[iface][prop]

    @dbus.service.method(PROPS_IFACE, in_signature="s", out_signature="a{sv}")
    def GetAll(self, iface):
        return self.props.get(iface, {})

    @dbus.service.method(PROPS_IFACE, in_signature="ssv")
    def Set(self, iface, prop, value):
        self.emit(iface, {prop: value})

    @dbus.service.signal(PROPS_IFACE, signature="sa{sv}as")
    def PropertiesChanged(self, iface, changed, invalidated):
        pass

    def emit(self, iface, changed):
        self.props[iface].update(changed)
        self.PropertiesChanged(iface, dbus.Dictionary(changed, signature="sv"),
                               dbus.Array([], signature="s"))

    # ── transport, so the widget's buttons do something ───────────────────
    @dbus.service.method(PLAYER_IFACE)
    def Next(self):
        log("Next() from the bar")
        self.step()

    @dbus.service.method(PLAYER_IFACE)
    def Previous(self):
        log("Previous() from the bar")
        self.step()

    @dbus.service.method(PLAYER_IFACE)
    def PlayPause(self):
        now = str(self.props[PLAYER_IFACE]["PlaybackStatus"])
        self.emit(PLAYER_IFACE, {"PlaybackStatus": dbus.String(
            "Paused" if now == "Playing" else "Playing")})

    @dbus.service.method(PLAYER_IFACE)
    def Play(self):
        self.emit(PLAYER_IFACE, {"PlaybackStatus": dbus.String("Playing")})

    @dbus.service.method(PLAYER_IFACE)
    def Pause(self):
        self.emit(PLAYER_IFACE, {"PlaybackStatus": dbus.String("Paused")})

    @dbus.service.method(PLAYER_IFACE)
    def Stop(self):
        self.emit(PLAYER_IFACE, {"PlaybackStatus": dbus.String("Stopped")})

    @dbus.service.method(ROOT_IFACE)
    def Raise(self):
        log("Raise() from the bar")

    @dbus.service.method(ROOT_IFACE)
    def Quit(self):
        pass

    # ── the sessions ──────────────────────────────────────────────────────
    def show_video(self, playing=False):
        """The other tab surfacing: no transport controls, normally paused."""
        self.emit(PLAYER_IFACE, {
            "Metadata": meta(VIDEO_TITLE, "SomeChannel", "", 9000),
            "PlaybackStatus": dbus.String("Playing" if playing else "Paused"),
            "CanGoNext": dbus.Boolean(False),
            "CanGoPrevious": dbus.Boolean(False),
        })

    def show_music(self, index, playing=True):
        title, artist, album = MUSIC[index % len(MUSIC)]
        self.emit(PLAYER_IFACE, {
            "Metadata": meta(title, artist, album, index),
            "PlaybackStatus": dbus.String("Playing" if playing else "Paused"),
            "CanGoNext": dbus.Boolean(True),
            "CanGoPrevious": dbus.Boolean(True),
        })
        return title

    def show_blank(self):
        self.emit(PLAYER_IFACE, {
            "Metadata": dbus.Dictionary({}, signature="sv"),
            "PlaybackStatus": dbus.String("Paused"),
        })

    # ── scenarios ─────────────────────────────────────────────────────────
    def step(self):
        """Run one round of the chosen scenario, then schedule the next."""
        if self.done:
            return False
        scenario = self.args.scenario
        self.index += 1
        if self.index > self.args.repeat:
            self.done = True
            GLib.timeout_add(1200, lambda: (self.args.loop.quit(), False)[1])
            return False

        nxt = self.index

        if scenario == "clean":
            log(f"clean skip -> {MUSIC[nxt % len(MUSIC)][0]}")
            self.show_music(nxt)
            GLib.timeout_add(self.args.period_ms, self.step)
            return False

        if scenario == "handover":
            log("pausing music, then playing the video tab")
            self.show_music(nxt - 1, playing=False)
            GLib.timeout_add(400, lambda: (self.show_video(playing=True), False)[1])
            GLib.timeout_add(self.args.period_ms, self.step)
            return False

        hold = {"flip": 200, "blank": 350, "adbreak": 5000}[scenario]

        if scenario == "blank":
            log(f"gap open: metadata cleared for {hold} ms")
            self.show_blank()
        else:
            log(f"gap open: video tab surfaces for {hold} ms")
            # Mirrors the real ordering: the music session pauses one message
            # BEFORE the other session appears.
            self.show_music(nxt - 1, playing=False)
            GLib.timeout_add(40, lambda: (self.show_video(), False)[1])

        def land():
            title = self.show_music(nxt)
            log(f"gap close: -> {title}")
            return False

        GLib.timeout_add(hold, land)
        GLib.timeout_add(max(self.args.period_ms, hold + 800), self.step)
        return False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--scenario", default="flip",
                    choices=["flip", "blank", "adbreak", "handover", "clean"])
    ap.add_argument("--repeat", type=int, default=3)
    ap.add_argument("--period-ms", type=int, default=2500)
    args = ap.parse_args()

    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    # Hold the reference: BusName releases the well-known name when it is
    # collected, and dropping it here leaves the player running but invisible
    # to anything looking for org.mpris.MediaPlayer2.*.
    name = dbus.service.BusName(BUS_NAME, bus)
    player = FakeChromium(bus, args)
    player.bus_name = name
    args.loop = GLib.MainLoop()

    log(f"up as {BUS_NAME}, scenario={args.scenario} repeat={args.repeat}")
    log(f"first track: {MUSIC[0][0]}")
    GLib.timeout_add(1500, player.step)

    try:
        args.loop.run()
    except KeyboardInterrupt:
        pass
    log("gone")


if __name__ == "__main__":
    main()
