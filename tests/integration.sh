#!/usr/bin/env bash
# End-to-end tests against the running shell.
#
# latch.test.js proves the decision machine is right. This proves the machine is
# actually wired up: a fake Chromium goes on the real session bus, Quickshell's
# MPRIS service picks it up, the service commits, and we read back what the bar
# is showing over IPC.
#
#   tests/integration.sh            all scenarios
#   tests/integration.sh flip       just one
#
# Note: this drives the shell you are looking at, so the bar will visibly react.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
VIDEO_TITLE="FAKE VIDEO TAB | should never reach the bar"
PASS=0
FAIL=0

SKIP=0
say() { printf '%s\n' "$*"; }
ok()   { PASS=$((PASS+1)); say "  ok   — $1"; }
bad()  { FAIL=$((FAIL+1)); say "  FAIL — $1"; }
skip() { SKIP=$((SKIP+1)); say "  skip — $1"; }

# The fake competes with any real player for selection, and loses whenever one
# is actually playing. Every assertion then fails for the same uninteresting
# reason, which reads as a product bug. Detect it and say so instead: none of
# the fake's own tracks reached the bar, so the run proved nothing.
contended() {
  local shown="$1" line foreign=""
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    case "$line" in
      Nightcall|Genesis|Sun|Desire|"$VIDEO_TITLE") ;;
      *) foreign="$line"; break ;;
    esac
  done <<<"$shown"
  [ -z "$foreign" ] && return 1
  say "  skip — inconclusive: another player put \"$foreign\" on the bar"
  say "         pause your own media and re-run."
  SKIP=$((SKIP+1))
  return 0
}

# The fake player needs python-dbus and PyGObject, which Arch installs into the
# system interpreter only. A version manager (mise, pyenv, asdf) puts its own
# python3 first on PATH, and that one has neither — so pick explicitly rather
# than failing later with an empty result that looks like a product bug.
PY=""
for candidate in /usr/bin/python3 python3; do
  command -v "$candidate" >/dev/null 2>&1 || continue
  if "$candidate" -c "import dbus, dbus.service, dbus.mainloop.glib; from gi.repository import GLib" 2>/dev/null; then
    PY="$candidate"
    break
  fi
done
if [ -z "$PY" ]; then
  say "no python with dbus + PyGObject found (checked /usr/bin/python3 and python3 on PATH)."
  say "install them with: omarchy pkg add python-dbus python-gobject"
  exit 1
fi
[ "$PY" = "/usr/bin/python3" ] || say "using $PY for the fake player"

command -v omarchy-shell >/dev/null || { say "omarchy-shell not found"; exit 1; }
if ! omarchy-shell crmne.mpris status >/dev/null 2>&1; then
  say "the shell is not running, or the plugin is not loaded."
  say "start it, then: omarchy plugin enable crmne.mpris"
  exit 1
fi

ART=/tmp/oma-test-art.png
if [ ! -f "$ART" ] && command -v magick >/dev/null; then
  magick -size 96x96 gradient:'#e94f37-#1b3b6f' "$ART" 2>/dev/null || true
fi

others=$(busctl --user list 2>/dev/null | grep -c "org.mpris.MediaPlayer2" || true)
if [ "${others:-0}" -gt 0 ]; then
  say "note: ${others} real MPRIS player(s) already on the bus; they can affect results."
  say "      pause and close other media for a clean run."
  say ""
fi

# Run one scenario, returning every distinct title the bar showed.
# $1 scenario  $2 repeat  $3 seconds to watch
run_scenario() {
  local scenario="$1" repeat="$2" secs="$3"
  local seen fakelog
  seen=$(mktemp)
  fakelog=$(mktemp)

  "$PY" "$HERE/fake_chromium.py" --scenario "$scenario" --repeat "$repeat" \
    > "$fakelog" 2>&1 &
  local pid=$!
  # Take the fake down even if the run is interrupted, so it cannot linger on
  # the bus and confuse the next run — or the user's actual bar.
  trap 'kill '"$pid"' 2>/dev/null; rm -f "'"$seen"'" "'"$fakelog"'"' RETURN INT TERM

  # Confirm the fake actually owns its bus name before trusting a single
  # reading. Without this a dead fake yields an empty result set, which reads
  # as "the widget showed nothing" rather than "the rig never started".
  local up=0
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    if busctl --user list 2>/dev/null | grep -q "instance_omatest"; then up=1; break; fi
    sleep 0.3
  done
  if [ "$up" -eq 0 ]; then
    say "  !! the fake player never reached the bus; its output was:"
    sed 's/^/     /' "$fakelog"
    return 1
  fi

  local endat=$(( $(date +%s%N)/1000000 + secs*1000 ))
  while [ $(( $(date +%s%N)/1000000 )) -lt "$endat" ]; do
    omarchy-shell crmne.mpris status 2>/dev/null \
      | grep -o '"title":"[^"]*"' | cut -d'"' -f4 >> "$seen"
  done

  kill "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  sort -u "$seen" | grep -v '^$'
}

scenario_flip() {
  say "flip — the video tab surfaces for 200 ms on every skip"
  local shown; shown=$(run_scenario flip 3 12)
  contended "$shown" && return
  if grep -qxF "$VIDEO_TITLE" <<<"$shown"; then
    bad "the video tab reached the bar"
  else
    ok "the video tab never reached the bar"
  fi
  if grep -qxF "Genesis" <<<"$shown" && grep -qxF "Sun" <<<"$shown"; then
    ok "the real tracks still landed"
  else
    bad "real tracks were swallowed; saw: $(tr '\n' '/' <<<"$shown")"
  fi
}

scenario_blank() {
  say "blank — metadata cleared for 350 ms on every skip"
  local shown; shown=$(run_scenario blank 3 12)
  contended "$shown" && return
  if grep -qxF "Genesis" <<<"$shown"; then
    ok "tracks landed across the gap"
  else
    bad "tracks were lost; saw: $(tr '\n' '/' <<<"$shown")"
  fi
  if [ -n "$shown" ]; then
    ok "the bar never emptied"
  else
    bad "the bar went empty"
  fi
}

scenario_adbreak() {
  say "adbreak — the video tab holds the bus for 5 s"
  local shown; shown=$(run_scenario adbreak 2 16)
  contended "$shown" && return
  if grep -qxF "$VIDEO_TITLE" <<<"$shown"; then
    bad "the video tab won by outlasting the window"
  else
    ok "a 5 s intrusion was still absorbed"
  fi
}

scenario_handover() {
  say "handover — music paused, then the video tab genuinely played"
  local shown; shown=$(run_scenario handover 2 12)
  contended "$shown" && return
  if grep -qxF "$VIDEO_TITLE" <<<"$shown"; then
    ok "a deliberate switch was accepted"
  else
    bad "the bar stayed stuck on the paused track"
  fi
}

scenario_clean() {
  say "clean — a well-behaved player, as a control"
  local shown; shown=$(run_scenario clean 3 11)
  contended "$shown" && return
  if grep -qxF "Genesis" <<<"$shown" && grep -qxF "Sun" <<<"$shown"; then
    ok "ordinary skips pass straight through"
  else
    bad "a well-behaved player was disturbed; saw: $(tr '\n' '/' <<<"$shown")"
  fi
}

only="${1:-all}"
for s in flip blank adbreak handover clean; do
  if [ "$only" = "all" ] || [ "$only" = "$s" ]; then
    "scenario_$s"
    say ""
  fi
done

say "integration: $PASS passed, $FAIL failed, $SKIP skipped"
[ "$FAIL" -eq 0 ]
