#!/usr/bin/python3
"""Capture the production bar widget with synthetic now-playing data.

Never touches a real media player: Service.qml is replaced by a fixture with
no MPRIS import. Runs fully offscreen with its own HOME and runtime directory.
Run through gpu-lock; refuses a software-rendered capture.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
TOOLS = Path(__file__).resolve().parent
SCALE = 6
WALLPAPER = "/usr/share/omarchy/themes/ristretto/backgrounds/0-launch.png"


def wait_for(predicate, description, timeout=20):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        if predicate(): return
        time.sleep(.1)
    raise RuntimeError("Timed out: " + description)


def complete_png(path):
    if not path.exists() or path.stat().st_size < 12: return False
    with path.open("rb") as image:
        image.seek(-12, 2)
        return image.read() == b'\x00\x00\x00\x00IEND\xaeB`\x82'


def png_size(path):
    with path.open("rb") as image:
        header = image.read(24)
    return int.from_bytes(header[16:20], "big"), int.from_bytes(header[20:24], "big")


def prepare(work):
    home, shell, plugin = (work / name for name in ["home", "shell", "plugin"])
    # A private runtime directory holds only Quickshell's IPC socket; keep its
    # path short enough for a Unix socket.
    runtime = Path(tempfile.mkdtemp(prefix="mpris-", dir=os.environ.get("XDG_RUNTIME_DIR")))
    shell.mkdir()
    plugin.mkdir()
    theme = home / ".local/state/omarchy/current/next-theme"
    theme.mkdir(parents=True)
    shutil.copy("/usr/share/omarchy/themes/ristretto/colors.toml", theme / "colors.toml")
    env = dict(HOME=str(home), PATH="/usr/bin:/bin", LANG="C.UTF-8",
               XDG_RUNTIME_DIR=str(runtime), OMARCHY_PATH="/usr/share/omarchy",
               DISPLAY=os.environ.get("DISPLAY", ":0"))
    if "XAUTHORITY" in os.environ: env["XAUTHORITY"] = os.environ["XAUTHORITY"]
    subprocess.run(["omarchy-theme-set-templates"], env=env, check=True, stdout=subprocess.DEVNULL)
    shutil.copytree(theme, theme.with_name("theme"))
    fonts = home / ".config/fontconfig"
    fonts.mkdir(parents=True)
    (fonts / "fonts.conf").write_text('''<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd"><fontconfig>
<match target="pattern"><test name="family"><string>monospace</string></test>
<edit name="family" mode="assign" binding="strong"><string>JetBrainsMono Nerd Font</string></edit></match>
</fontconfig>''')
    for name in ["Commons", "Ui"]:
        shutil.copytree(Path("/usr/share/omarchy/shell") / name, shell / name)
    # Production widget files; the MPRIS service is swapped for the fixture.
    for name in ["BarWidget.qml", "BarGeometry.js", "ServiceSource.qml", "TextLimit.js", "Transport.js"]:
        shutil.copy(ROOT / name, plugin / name)
    shutil.copy(TOOLS / "FakeService.qml", plugin / "Service.qml")
    shutil.copy(TOOLS / "FakeService.qml", shell / "FakeService.qml")
    shutil.copy(TOOLS / "shell.qml", shell / "shell.qml")
    return env, shell, plugin, runtime


def run_host(env, shell, log, body):
    def call(method, *args):
        result = subprocess.run(["qs", "ipc", "-p", str(shell), "call", "--", "capture", method, *map(str, args)],
                                env=env, capture_output=True, text=True, timeout=10)
        if result.returncode != 0:
            if method != "ready": print(result.stderr, file=sys.stderr, flush=True)
            return ""
        return result.stdout.strip()
    with log.open("w") as stream:
        proc = subprocess.Popen(["qs", "-p", str(shell)], env=env, stdout=stream, stderr=subprocess.STDOUT)
        try:
            wait_for(lambda: call("ready") == "true", "capture host")
            body(call)
        except Exception:
            print(log.read_text()[-6000:], file=sys.stderr)
            raise
        finally:
            proc.terminate()
            proc.wait(timeout=5)
    text = log.read_text()
    for line in text.splitlines():
        if "OpenGL VENDOR" in line or "OpenGL RENDERER" in line or "WARN" in line or "ERROR" in line:
            print(line, file=sys.stderr)
    if "NVIDIA" not in text or "llvmpipe" in text or "Software" in text:
        raise RuntimeError("Capture must use NVIDIA GPU rendering; inspect " + str(log))
    return text


def grab(call, which, path):
    path.unlink(missing_ok=True)
    result = call("grab", which, str(path))
    if result != "ok": raise RuntimeError(which + ": " + result)
    wait_for(lambda: complete_png(path), which)
    print(path, file=sys.stderr, flush=True)


def main():
    with tempfile.TemporaryDirectory(prefix="mpris-capture-", dir=os.environ.get("MPRIS_CAPTURE_TMP")) as work_path:
        work = Path(work_path)
        # Individual captures and logs go to the optional output directory
        # argument, or are discarded with the temporary host.
        output = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else work / "captures"
        output.mkdir(parents=True, exist_ok=True)
        env, shell, plugin, runtime = prepare(work)
        try:
            capture_all(work, env, shell, plugin, output)
        finally:
            shutil.rmtree(runtime, ignore_errors=True)


def capture_all(work, env, shell, plugin, output):
    (work / "screen.json").write_text(json.dumps({"screens": [dict(
        name="CAPTURE", x=0, y=0, width=1200 * SCALE, height=800 * SCALE,
        logicalDpi=96, logicalBaseDpi=96, dpr=1)]}))
    env.update(QT_QPA_PLATFORM=f"offscreen:configfile={work / 'screen.json'}",
               QT_QUICK_BACKEND="rhi", QSG_RHI_BACKEND="opengl", QSG_INFO="1",
               QT_SCALE_FACTOR=str(SCALE), MPRIS_PLUGIN=str(plugin), MPRIS_OUTPUT=str(output),
               MPRIS_MODE="capture")
    geometry = {}

    def capture(call):
        assert call("drawCover") == "true"
        wait_for(lambda: complete_png(output / "cover.png"), "cover")
        wait_for(lambda: json.loads(call("states"))["coverStatus"], "cover loaded")
        time.sleep(.5)
        wide = json.loads(call("states"))["wide"]
        assert wide["visible"] and wide["stage"] == 0 and wide["previousNext"] and wide["art"], wide
        # Narrow the second bar until the real adaptive layout drops
        # previous/next but keeps play/pause, artwork, and a usable label.
        for width in range(560, 853, 2):
            narrow = json.loads(call("setNarrowWidth", width))
            time.sleep(.35)
            narrow = json.loads(call("states"))["narrow"]
            if narrow["stage"] == 1 and narrow["labelWidth"] >= 110: break
        else:
            raise RuntimeError("No compact width found: " + json.dumps(narrow))
        assert narrow["playPause"] and narrow["art"] and not narrow["previousNext"], narrow
        print("narrow", width, narrow, file=sys.stderr)
        time.sleep(.5)
        grab(call, "wide", output / "bar.png")
        grab(call, "narrow", output / "bar-compact.png")
        opened = json.loads(call("openSettings"))
        assert opened["opened"] and opened["popupVisible"], opened
        time.sleep(.8)
        grab(call, "settings", output / "settings.png")
        geometry.update(json.loads(call("widgetGeometry")))

    log_text = run_host(env, shell, work / "capture.log", capture)
    (output / "capture.log").write_text(log_text)
    (output / "cover.png").unlink(missing_ok=True)

    # Compose the 2560x1600 marketplace preview. The marketplace card shows
    # only a strip about 2.7 times as wide as it is tall from the vertical
    # middle, and websites crop to 16:9, so the widget is shown large in the
    # middle band: the bar from just before the widget to its right edge,
    # flush with the canvas edge like the real bar, and the appearance panel
    # opening under it and running off the bottom.
    sizes = {name: png_size(output / name) for name in ["bar.png", "settings.png"]}
    bar_w, bar_h = sizes["bar.png"]
    settings_w, settings_h = sizes["settings.png"]
    margin = 5 * SCALE  # Style.gapsOut between bar and popup.
    clip_x = round((geometry["x"] - 14) * SCALE)
    # The rounded right end runs off the canvas, inside the tray margin.
    bar_x, bar_y = 2560 - (bar_w - clip_x) + 10 * SCALE, 450
    # The panel is shown at 80% so its toggles start inside the crops.
    card_w, card_h = round(settings_w * .8), round(settings_h * .8)
    widget_center = bar_x + round((geometry["x"] + geometry["width"] / 2) * SCALE) - clip_x
    card_x = max(40, min(widget_center - card_w // 2, 2560 - card_w - 40))
    card_y = bar_y + bar_h + margin
    layout = [
        dict(file="bar.png", x=bar_x, y=bar_y, width=bar_w - clip_x, height=bar_h,
             clip=[clip_x, 0, bar_w - clip_x, bar_h], radius=10 * SCALE),
        dict(file="settings.png", x=card_x, y=card_y, width=card_w, height=card_h),
    ]
    print("layout", layout, file=sys.stderr)
    env.update(QT_QPA_PLATFORM=f"offscreen:configfile={work / 'compose.json'}", QT_SCALE_FACTOR="1",
               MPRIS_MODE="compose", MPRIS_WALLPAPER=WALLPAPER, MPRIS_LAYOUT=json.dumps(layout))
    (work / "compose.json").write_text(json.dumps({"screens": [dict(
        name="COMPOSE", x=0, y=0, width=2800, height=1800, logicalDpi=96, logicalBaseDpi=96, dpr=1)]}))
    preview = ROOT / "preview.png"

    def compose(call):
        time.sleep(1.5)
        preview.unlink(missing_ok=True)
        assert call("grabPreview", str(preview)) == "true"
        wait_for(lambda: complete_png(preview), "preview")
        print(preview, png_size(preview), file=sys.stderr)

    run_host(env, shell, work / "compose.log", compose)


if __name__ == "__main__": main()
